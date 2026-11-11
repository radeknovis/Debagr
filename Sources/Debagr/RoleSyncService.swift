import AppKit
import Foundation
import Network

// All mutable channel state is confined to the service serial queue.
private final class RoleSyncChannel: @unchecked Sendable {
  let connection: NWConnection
  private let queue: DispatchQueue
  private var buffer = Data()
  private var receiveID = UUID()
  private var failure: (@Sendable (Error) -> Void)?
  private var ready: (@Sendable () -> Void)?
  private(set) var closed = false

  init(_ connection: NWConnection, queue: DispatchQueue) {
    self.connection = connection
    self.queue = queue
  }

  func start(_ ready: @escaping @Sendable () -> Void, failed: @escaping @Sendable (Error) -> Void) {
    self.ready = ready
    failure = failed
    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        let callback = self.ready
        self.ready = nil
        callback?()
      case .failed(let error): self.fail(error)
      default: break
      }
    }
    connection.start(queue: queue)
  }

  func send<T: Encodable>(_ value: T, completion: (@Sendable () -> Void)? = nil) {
    do {
      let data = try JSONEncoder().encode(value)
      guard data.count <= 16_384 else { throw USBIPError.invalid("Role message is too large.") }
      connection.send(
        content: data + Data([10]),
        completion: .contentProcessed { [weak self] error in
          if let error { self?.fail(error) } else { completion?() }
        })
    } catch { fail(error) }
  }

  func receive<T: Decodable & Sendable>(
    _ type: T.Type, timeout: TimeInterval,
    completion: @escaping @Sendable (Result<T, Error>) -> Void
  ) {
    let id = UUID()
    receiveID = id
    failure = { completion(.failure($0)) }
    @Sendable func read() {
      guard !closed, receiveID == id else { return }
      if let newline = buffer.firstIndex(of: 10) {
        let line = Data(buffer[..<newline])
        buffer.removeSubrange(...newline)
        receiveID = UUID()
        do { completion(.success(try JSONDecoder().decode(type, from: line))) } catch {
          fail(error)
        }
        return
      }
      connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
        [weak self] data, _, complete, error in
        guard let self, !self.closed, self.receiveID == id else { return }
        if let data { self.buffer.append(data) }
        if self.buffer.count > 16_384 {
          self.fail(USBIPError.invalid("Role message is too large."))
        } else if self.buffer.contains(10) {
          read()
        } else if complete || error != nil {
          self.fail(error ?? USBIPError.invalid("The other Mac closed the role connection."))
        } else {
          read()
        }
      }
    }
    queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let self, !self.closed, self.receiveID == id else { return }
      self.fail(
        USBIPError.invalid(
          "Role pairing timed out. No two-way confirmation was received; refresh and retry."))
    }
    read()
  }

  func close() {
    closed = true
    failure = nil
    ready = nil
    connection.stateUpdateHandler = nil
    connection.cancel()
  }

  func fail(_ error: Error) {
    guard !closed else { return }
    let callback = failure
    close()
    callback?(error)
  }
}

// Protocol state belongs to queue; UI callbacks execute on the main actor. Configure before start.
final class RoleSyncService: @unchecked Sendable {
  static let port: NWEndpoint.Port = 49_389
  static let defaultKeyURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Debagr/role-sync-key.raw")
  let local: RoleSyncNode
  let identity: RoleSyncIdentity
  private let store: RoleSyncStore
  private let queue = DispatchQueue(label: "debagr.role-sync")
  private var listener: NWListener?
  private var channels: [UUID: RoleSyncChannel] = [:]
  private var pendingApproval = false
  private var lastApproval = Date.distantPast
  var canChangeRoles: @MainActor @Sendable () -> Bool = { !USBIPSessionController().isRunning }
  var approvePair:
    @MainActor @Sendable (
      String, String, DebagrMachineRole, @escaping @MainActor @Sendable (Bool) -> Void
    ) -> Void = {
      name, code, role, completion in
      NSApplication.shared.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = "Pair with \(name)?"
      alert.informativeText =
        "Compare code \(code) with the code shown on \(name). This Mac will become \(role.title). Once paired, either Mac can change both roles."
      alert.addButton(withTitle: "Pair")
      alert.addButton(withTitle: "Cancel")
      completion(alert.runModal() == .alertFirstButtonReturn)
    }
  var trustMeshConnection: (NWConnection) -> Bool = { connection in
    guard let path = connection.currentPath,
      case .hostPort(let local, _) = path.localEndpoint,
      case .hostPort(let remote, _) = path.remoteEndpoint
    else { return false }
    return TailscaleClient().isPersonalMeshConnection(
      localAddress: String(describing: local), remoteAddress: String(describing: remote))
  }
  var onChanged: (@MainActor @Sendable () -> Void)?
  var onApplying: (@MainActor @Sendable (Bool) -> Void)?
  var onError: (@MainActor @Sendable (String) -> Void)?

  init(local: RoleSyncNode, defaults: UserDefaults, keyURL: URL) throws {
    self.local = local
    identity = try RoleSyncIdentity(keyURL: keyURL)
    store = RoleSyncStore(defaults: defaults, local: local)
  }

  func start(
    port: NWEndpoint.Port = RoleSyncService.port,
    ready: (@Sendable (NWEndpoint.Port) -> Void)? = nil
  ) {
    queue.async { [self] in
      guard listener == nil else { return }
      do {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.any), port: port)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.service = NWListener.Service(name: local.name, type: "_debagr-role._tcp")
        listener.stateUpdateHandler = { [weak self, weak listener] state in
          if case .ready = state, let port = listener?.port { ready?(port) }
          if case .failed(let error) = state { self?.report(error.localizedDescription) }
        }
        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener.start(queue: queue)
      } catch { report(error.localizedDescription) }
    }
  }

  func stop() {
    queue.async { [self] in
      listener?.cancel()
      listener = nil
      // Fail instead of close: a pending role exchange must still reach its completion.
      for channel in channels.values {
        channel.fail(USBIPError.invalid("Role pairing stopped before both Macs confirmed. Retry."))
      }
      channels.removeAll()
    }
  }

  func clear() {
    queue.async { [self] in
      store.clear()
      changed()
    }
  }

  func assign(
    role: DebagrMachineRole, peer: DebagrPeer, endpoint: NWEndpoint,
    progress: @escaping @MainActor @Sendable (String) -> Void,
    completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void
  ) {
    exchangeRoles(
      role: role, peer: peer, endpoint: endpoint, progress: progress, completion: completion)
  }

  func verify(
    peer: DebagrPeer, endpoint: NWEndpoint,
    completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void
  ) {
    exchangeRoles(
      role: nil, peer: peer, endpoint: endpoint, progress: { _ in }, completion: completion)
  }

  private func exchangeRoles(
    role: DebagrMachineRole?, peer: DebagrPeer, endpoint: NWEndpoint,
    progress: @escaping @MainActor @Sendable (String) -> Void,
    completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void
  ) {
    queue.async { [self] in
      let id = UUID()
      @Sendable func finish(_ result: Result<Void, Error>) {
        channels.removeValue(forKey: id)?.close()
        DispatchQueue.main.async { completion(result) }
      }
      do {
        guard let keyText = peer.roleSyncPublicKey, let key = Data(base64Encoded: keyText),
          key.count == 32
        else {
          throw USBIPError.invalid("Update Debagr on the other Mac to enable two-way role pairing.")
        }
        try store.checkPeer(peer.nodeID, publicKey: key, replacingPeer: role != nil)
        if role == nil, store.trustedKey(for: peer.nodeID) != key {
          throw USBIPError.invalid("Pair these Macs before starting a connection.")
        }
        let candidate = try role.map {
          try store.proposal(
            role: $0, peer: RoleSyncNode(id: peer.nodeID, name: peer.name))
        }
        let channel = RoleSyncChannel(NWConnection(to: endpoint, using: .tcp), queue: queue)
        channels[id] = channel
        channel.start(
          { [self] in
            channel.receive(RoleSyncHello.self, timeout: 5) { [self] helloResult in
              do {
                let hello = try helloResult.get()
                guard hello.version == 1, hello.nodeID == peer.nodeID, hello.publicKey == key,
                  UUID(uuidString: hello.nonce) != nil
                else {
                  throw USBIPError.invalid("The role endpoint does not match the selected Mac.")
                }
                let requestID = UUID().uuidString
                let payload = RoleSyncPayload(
                  requestID: requestID, nonce: hello.nonce, sender: local,
                  targetID: peer.nodeID, assignment: candidate, error: nil)
                let request = try SignedRoleMessage(payload: payload, identity: identity)
                let code = request.verificationCode(remoteKey: key)
                let needsCode =
                  role != nil && store.trustedKey(for: peer.nodeID) == nil
                  && !trustMeshConnection(channel.connection)
                if role != nil {
                  DispatchQueue.main.async {
                    progress(
                      needsCode
                        ? "Pairing code: \(code). Accept the matching code on \(peer.name), then confirm it on this Mac."
                        : "Connecting securely to \(peer.name)…")
                  }
                }
                channel.send(request)
                channel.receive(SignedRoleMessage.self, timeout: role == nil ? 5 : 120) {
                  [self] result in
                  do {
                    let reply = try result.get().verified(
                      expectedKey: key, targetID: local.id, nonce: hello.nonce)
                    guard reply.sender.id == peer.nodeID, reply.requestID == requestID else {
                      throw USBIPError.invalid("Role confirmation does not match this request.")
                    }
                    if let error = reply.error { throw USBIPError.invalid(error) }
                    guard let assignment = reply.assignment else {
                      throw USBIPError.invalid("No role assignment was confirmed.")
                    }
                    guard let role else {
                      guard try store.confirms(assignment, remoteID: peer.nodeID) else {
                        throw USBIPError.invalid(
                          "The paired roles changed. Refresh and set the roles again before starting."
                        )
                      }
                      finish(.success(()))
                      return
                    }
                    @Sendable func apply() {
                      do {
                        try store.apply(
                          assignment, remote: reply.sender, publicKey: key, replacingPeer: true)
                        changed()
                        finish(.success(()))
                      } catch { finish(.failure(error)) }
                    }
                    guard needsCode else {
                      apply()
                      return
                    }
                    // The other Mac's acceptance proves nothing about who it is: a device that
                    // only imitates Debagr accepts at once. This Mac's user confirms the code too.
                    DispatchQueue.main.async { [self] in
                      approvePair(peer.name, code, role) { [self] accepted in
                        queue.async { [self] in
                          // Timed out or stopped while the question was open.
                          guard channels[id] != nil else { return }
                          if accepted {
                            apply()
                          } else {
                            finish(
                              .failure(USBIPError.invalid("Pairing was cancelled on this Mac.")))
                          }
                        }
                      }
                    }
                  } catch { finish(.failure(error)) }
                }
              } catch { finish(.failure(error)) }
            }
          }, failed: { finish(.failure($0)) })
        queue.asyncAfter(deadline: .now() + (role == nil ? 12 : 130)) { [self] in
          if channels[id] != nil {
            finish(.failure(USBIPError.invalid("The other Mac did not confirm the role update.")))
          }
        }
      } catch { finish(.failure(error)) }
    }
  }

  private func accept(_ connection: NWConnection) {
    guard channels.count < 8, case .hostPort(let host, _) = connection.endpoint,
      NetworkSupport.isAllowedPrivateVPNIPv4(String(describing: host))
        || String(describing: host) == "127.0.0.1"
    else {
      connection.cancel()
      return
    }
    let id = UUID()
    let channel = RoleSyncChannel(connection, queue: queue)
    channels[id] = channel
    let nonce = UUID().uuidString
    @Sendable func close() { channels.removeValue(forKey: id)?.close() }
    channel.start(
      { [self] in
        channel.send(
          RoleSyncHello(version: 1, nodeID: local.id, publicKey: identity.publicKey, nonce: nonce))
        channel.receive(SignedRoleMessage.self, timeout: 5) { [self] result in
          do {
            let message = try result.get()
            let payload = try message.verified(
              expectedKey: message.publicKey, targetID: local.id, nonce: nonce)
            guard payload.error == nil else { throw USBIPError.invalid("Invalid role request.") }
            @Sendable func reply(assignment: SyncedMachineRoles?, error: String?) {
              do {
                let response = try SignedRoleMessage(
                  payload: RoleSyncPayload(
                    requestID: payload.requestID,
                    nonce: nonce, sender: local, targetID: payload.sender.id,
                    assignment: assignment, error: error), identity: identity)
                channel.send(response, completion: close)
              } catch { close() }
            }
            do { try store.checkPeer(payload.sender.id, publicKey: message.publicKey) } catch {
              reply(assignment: nil, error: error.localizedDescription)
              return
            }
            let pinned = store.trustedKey(for: payload.sender.id) != nil
            let trusted = pinned || (payload.assignment != nil && trustMeshConnection(connection))
            guard let assignment = payload.assignment else {
              guard pinned, let current = store.current,
                try store.confirms(current, remoteID: payload.sender.id)
              else {
                reply(assignment: nil, error: "Pair these Macs again before starting a connection.")
                return
              }
              reply(assignment: current, error: nil)
              return
            }
            guard assignment.authorID == payload.sender.id else {
              reply(assignment: nil, error: "Invalid role assignment author.")
              return
            }
            try assignment.validate(localID: local.id, remoteID: payload.sender.id)
            guard trusted || (!pendingApproval && Date().timeIntervalSince(lastApproval) >= 10)
            else {
              reply(assignment: nil, error: "Another pairing approval is pending. Retry shortly.")
              return
            }
            if !trusted {
              pendingApproval = true
              lastApproval = Date()
            }
            DispatchQueue.main.async { [self] in
              @Sendable func decide(_ accepted: Bool) {
                queue.async { [self] in
                  if !trusted { pendingApproval = false }
                  guard !channel.closed else {
                    close()
                    return
                  }
                  guard accepted else {
                    reply(
                      assignment: nil, error: "Pairing was declined or a USB connection is active.")
                    return
                  }
                  do {
                    let winner = try store.apply(
                      assignment, remote: payload.sender, publicKey: message.publicKey)
                    changed()
                    reply(assignment: winner, error: nil)
                  } catch { reply(assignment: nil, error: error.localizedDescription) }
                  DispatchQueue.main.async { [weak self] in self?.onApplying?(false) }
                }
              }
              guard canChangeRoles() else {
                decide(false)
                return
              }
              if trusted {
                onApplying?(true)
                decide(true)
              } else {
                approvePair(
                  payload.sender.name, message.verificationCode(remoteKey: identity.publicKey),
                  (try? assignment.selection(for: local.id).role) ?? .client
                ) { [self] accepted in
                  let allowed = accepted && canChangeRoles()
                  if allowed { onApplying?(true) }
                  decide(allowed)
                }
              }
            }
          } catch { close() }
        }
      }, failed: { _ in close() })
    queue.asyncAfter(deadline: .now() + 125) { close() }
  }

  private func changed() { DispatchQueue.main.async { [weak self] in self?.onChanged?() } }
  private func report(_ message: String) {
    DispatchQueue.main.async { [weak self] in self?.onError?(message) }
  }
}
