import Foundation
import Network

struct DebagrPeer: Codable, Equatable {
  let protocolVersion: Int
  let nodeID: String
  let name: String
  let roles: [String]
  var machineRole: DebagrMachineRole? = nil
  var pairedNodeID: String? = nil
  var roleSyncPublicKey: String? = nil
  var connectedDeviceNames: [String]? = nil
  var sipStatus: SystemIntegrityStatus? = nil

  static func roles(in executablePaths: String) -> [String] {
    let names = Set(
      executablePaths.split(separator: "\n").map {
        URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)).lastPathComponent
      })
    var roles = ["app"]
    if names.contains("usbip-macos") { roles.append("client") }
    if names.contains("longcable-server") { roles.append("server") }
    return roles
  }

  static func decode(_ data: Data) throws -> DebagrPeer {
    guard data.count <= 16_384 else { throw USBIPError.invalid("Discovery response too large.") }
    let peer = try JSONDecoder().decode(DebagrPeer.self, from: data)
    guard peer.protocolVersion == 1, !peer.nodeID.isEmpty, peer.nodeID.count <= 128,
      !peer.name.isEmpty, peer.name.count <= 128, !peer.roles.isEmpty,
      peer.roles.allSatisfy({ ["app", "client", "server"].contains($0) })
    else {
      throw USBIPError.invalid("Unsupported discovery response.")
    }
    if let pairedNodeID = peer.pairedNodeID {
      guard !pairedNodeID.isEmpty, pairedNodeID.count <= 128, pairedNodeID != peer.nodeID else {
        throw USBIPError.invalid("Invalid paired machine in discovery response.")
      }
    }
    if let names = peer.connectedDeviceNames {
      guard names.count <= 32,
        names.allSatisfy({
          !$0.isEmpty && $0.count <= 128 && !$0.contains(where: \.isNewline)
        })
      else { throw USBIPError.invalid("Invalid USB device summary in discovery response.") }
    }
    if let key = peer.roleSyncPublicKey, Data(base64Encoded: key)?.count != 32 {
      throw USBIPError.invalid("Invalid role pairing key in discovery response.")
    }
    return peer
  }

  var roleDescription: String {
    roles.map {
      switch $0 {
      case "client": return "USB import process"
      case "server": return "USB export process"
      default: return "Debagr app"
      }
    }.joined(separator: ", ")
  }
}

struct DiscoveredDebagrPeer: Equatable {
  let peer: DebagrPeer
  let address: String
  let source: String
  var endpoint: NWEndpoint? = nil
  var lastSeen: Date = Date()

  var hasRecentInventory: Bool { Date().timeIntervalSince(lastSeen) < 12 }
}

/// Discovery is informational: USB product names omit identifiers; no control commands are accepted.
final class DebagrPeerDiscovery {
  static let port: NWEndpoint.Port = 49_388
  static let serviceType = "_debagr._tcp"
  private let queue = DispatchQueue(label: "debagr.peer-discovery")
  private let worker = DispatchQueue(label: "debagr.peer-inventory")
  private var cachedSIPStatus: SystemIntegrityStatus?
  private let nodeID: String
  private let roleStore: MachineRoleStore
  var localNodeID: String { nodeID }
  var localSelection: MachineRoleSelection? { get throws { try roleStore.load() } }
  private var snapshot: DebagrPeer
  private var listener: NWListener?
  private var browser: NWBrowser?
  private var timer: DispatchSourceTimer?
  private var connections: [UUID: NWConnection] = [:]
  private var peers: [String: DiscoveredDebagrPeer] = [:]
  private var generation = 0
  private var scanning = false
  private var roleSync: RoleSyncService?
  private var roleSyncError: String?
  var canChangeRoles: () -> Bool = { !USBIPSessionController().isRunning }
  var onRoleSyncApplying: ((Bool) -> Void)?
  var onChange: (([DiscoveredDebagrPeer], String) -> Void)?

  init(defaults: UserDefaults = .standard, identityURL: URL = RoleSyncService.defaultKeyURL) {
    roleStore = MachineRoleStore(defaults: defaults)
    let key = "usbip-discovery-node-id"
    nodeID = defaults.string(forKey: key) ?? UUID().uuidString
    defaults.set(nodeID, forKey: key)
    snapshot = DebagrPeer(
      protocolVersion: 1, nodeID: nodeID,
      name: Host.current().localizedName ?? ProcessInfo.processInfo.hostName, roles: ["app"])
    if let selection = try? roleStore.load() {
      snapshot.machineRole = selection.role
      snapshot.pairedNodeID = selection.peerID
    }
    do {
      let service = try RoleSyncService(
        local: RoleSyncNode(id: nodeID, name: snapshot.name),
        defaults: defaults, keyURL: identityURL)
      roleSync = service
      snapshot.roleSyncPublicKey = service.identity.publicKey.base64EncodedString()
      service.onChanged = { [weak self] in self?.refresh() }
      service.onError = { [weak self] error in
        self?.queue.async { [weak self] in self?.emit("Role pairing: \(error)") }
      }
      service.canChangeRoles = { [weak self] in self?.canChangeRoles() ?? false }
      service.onApplying = { [weak self] in self?.onRoleSyncApplying?($0) }
    } catch { roleSyncError = error.localizedDescription }
  }

  func assignRoles(
    role: DebagrMachineRole, peer: DiscoveredDebagrPeer,
    progress: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let roleSync else {
      completion(.failure(USBIPError.invalid(roleSyncError ?? "Role pairing is unavailable.")))
      return
    }
    do {
      roleSync.assign(
        role: role, peer: peer.peer, endpoint: try roleEndpoint(for: peer), progress: progress,
        completion: completion)
    } catch { completion(.failure(error)) }
  }

  func verifyPeer(peer: DiscoveredDebagrPeer, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let roleSync else {
      completion(.failure(USBIPError.invalid(roleSyncError ?? "Role pairing is unavailable.")))
      return
    }
    do {
      roleSync.verify(
        peer: peer.peer, endpoint: try roleEndpoint(for: peer), completion: completion)
    } catch { completion(.failure(error)) }
  }

  private func roleEndpoint(for peer: DiscoveredDebagrPeer) throws -> NWEndpoint {
    let endpoint: NWEndpoint
    if case .service(let name, _, let domain, let interface) = peer.endpoint {
      endpoint = .service(
        name: name, type: "_debagr-role._tcp", domain: domain, interface: interface)
    } else if case .hostPort(let host, _) = peer.endpoint {
      endpoint = .hostPort(host: host, port: RoleSyncService.port)
    } else if let host = peer.address.components(separatedBy: ":").first,
      NetworkSupport.isAllowedPrivateVPNIPv4(host)
    {
      endpoint = .hostPort(host: NWEndpoint.Host(host), port: RoleSyncService.port)
    } else {
      throw USBIPError.invalid("Refresh discovery before pairing with this Mac.")
    }
    return endpoint
  }

  func select(role: DebagrMachineRole, peer: DebagrPeer) throws {
    try roleStore.save(
      MachineRoleSelection(role: role, peerID: peer.nodeID, peerName: peer.name),
      localNodeID: nodeID)
    refresh()
  }

  func clearSelection() {
    if let roleSync {
      roleSync.clear()
    } else {
      roleStore.clear()
      refresh()
    }
  }

  func start() {
    roleSync?.start()
    queue.async { [self] in
      guard listener == nil else { return }
      do {
        let parameters = NWParameters.tcp
        // IPv4 private networks are the existing Debagr discovery scope.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.any), port: Self.port)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.service = NWListener.Service(name: snapshot.name, type: Self.serviceType)
        listener.newConnectionHandler = { [weak self] in self?.answer($0) }
        listener.stateUpdateHandler = { [weak self] state in
          if case .failed(let error) = state {
            self?.emit(
              "Advertising unavailable: \(error.localizedDescription). Discovery still works.")
          }
        }
        listener.start(queue: queue)
      } catch { emit("Advertising unavailable: \(error.localizedDescription)") }
      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(deadline: .now(), repeating: 5)
      timer.setEventHandler { [weak self] in
        guard let self else { return }
        self.refreshLocal()
        for entry in self.peers.values
        where entry.peer.nodeID != self.nodeID && entry.peer.roles.contains("app") {
          if let endpoint = entry.endpoint {
            self.probe(endpoint, source: entry.source, scan: self.generation)
          }
        }
      }
      self.timer = timer
      timer.resume()
    }
  }

  func stop() {
    roleSync?.stop()
    queue.async { [self] in
      generation += 1
      scanning = false
      timer?.cancel()
      timer = nil
      browser?.cancel()
      browser = nil
      listener?.cancel()
      listener = nil
      for connection in connections.values { connection.cancel() }
      connections.removeAll()
    }
  }

  func refresh() {
    queue.async { [self] in
      generation += 1
      let scan = generation
      scanning = true
      browser?.cancel()
      for connection in connections.values { connection.cancel() }
      connections.removeAll()
      peers.removeAll()
      refreshLocal()
      emit("Looking for Builders and Clients…")
      let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
      self.browser = browser
      browser.browseResultsChangedHandler = { [weak self] results, _ in
        guard let self, self.generation == scan else { return }
        for result in results { self.probe(result.endpoint, source: "Local network", scan: scan) }
      }
      browser.stateUpdateHandler = { [weak self] state in
        if case .failed(let error) = state {
          self?.emit("Local network discovery: \(error.localizedDescription)")
        }
      }
      browser.start(queue: queue)
      worker.async { [weak self] in
        let result = Result { try TailscaleClient().onlinePeers() }
        self?.queue.async { [weak self] in
          guard let self, self.generation == scan, self.scanning else { return }
          switch result {
          case .success(let peers):
            for peer in peers {
              self.probe(
                .hostPort(host: NWEndpoint.Host(peer.ipAddress), port: Self.port),
                source: "Tailscale", scan: scan)
              self.probeLegacyServer(peer, scan: scan)
            }
            self.emit("Searching local network and \(peers.count) online Tailscale peers…")
          case .failure(let error):
            self.emit("Searching local network. Tailscale: \(error.localizedDescription)")
          }
        }
      }
      queue.asyncAfter(deadline: .now() + 8) { [weak self] in
        guard let self, self.generation == scan else { return }
        self.scanning = false
        self.emit(
          "Scan finished. Refresh to check again. Older Debagr apps need updating to advertise.")
      }
    }
  }

  private func refreshLocal() {
    worker.async { [weak self] in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/ps")
      process.arguments = ["-axo", "comm="]
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      let roles: [String]
      do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
          throw USBIPError.invalid("Process inventory failed")
        }
        roles = DebagrPeer.roles(in: String(decoding: data, as: UTF8.self))
      } catch {
        self?.queue.async { [weak self] in
          self?.emit("Local process discovery failed: \(error.localizedDescription)")
        }
        return
      }
      let sipStatus = self?.cachedSIPStatus ?? SystemIntegrityStatus.probe()
      if sipStatus != .unknown { self?.cachedSIPStatus = sipStatus }
      let deviceNames = try? USBIPDevice.connected().filter(\.isAppleMobileDevice)
        .prefix(32).map(\.inventoryName)
      self?.queue.async { [weak self] in
        guard let self else { return }
        self.snapshot = DebagrPeer(
          protocolVersion: 1, nodeID: self.nodeID,
          name: self.snapshot.name, roles: roles)
        self.snapshot.roleSyncPublicKey = self.roleSync?.identity.publicKey.base64EncodedString()
        self.snapshot.connectedDeviceNames = deviceNames
        self.snapshot.sipStatus = sipStatus
        do {
          if let selection = try self.roleStore.load() {
            try selection.validate(localNodeID: self.nodeID)
            self.snapshot.machineRole = selection.role
            self.snapshot.pairedNodeID = selection.peerID
          }
        } catch { self.emit("Unable to load machine role: \(error.localizedDescription)") }
        self.peers[self.nodeID] = DiscoveredDebagrPeer(
          peer: self.snapshot,
          address: "This Mac", source: "Local processes")
        self.emit()
      }
    }
  }

  private func answer(_ connection: NWConnection) {
    guard case .hostPort(let host, _) = connection.endpoint,
      NetworkSupport.isAllowedPrivateVPNIPv4(String(describing: host))
        || String(describing: host) == "127.0.0.1"
    else {
      connection.cancel()
      return
    }
    guard connections.count < 64 else {
      connection.cancel()
      return
    }
    let id = UUID()
    connections[id] = connection
    connection.start(queue: queue)
    let data = (try? JSONEncoder().encode(snapshot)) ?? Data()
    connection.send(
      content: data + Data([10]),
      completion: .contentProcessed { [weak self] _ in
        connection.cancel()
        self?.connections.removeValue(forKey: id)
      })
    queue.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.connections.removeValue(forKey: id)?.cancel()
    }
  }

  private func probe(_ endpoint: NWEndpoint, source: String, scan: Int) {
    exchange(endpoint, request: nil) { [weak self] data, resolved in
      guard let self, self.generation == scan,
        let peer = try? DebagrPeer.decode(data), peer.nodeID != self.nodeID
      else { return }
      // Prefer the authenticated mesh route when Bonjour discovers the same Mac too.
      if source != "Tailscale", self.peers[peer.nodeID]?.source == "Tailscale" { return }
      self.peers[peer.nodeID] = DiscoveredDebagrPeer(
        peer: peer,
        address: String(describing: resolved), source: source, endpoint: resolved)
      self.emit()
    }
  }

  static func isUSBIPReply(_ data: Data) -> Bool {
    // USB/IP OP_REP_DEVLIST: version, reply opcode, success status, device count.
    data.count >= 12 && Array(data.prefix(8)) == [1, 17, 0, 5, 0, 0, 0, 0]
  }

  private func probeLegacyServer(_ peer: SelectedNetworkPeer, scan: Int) {
    exchange(
      .hostPort(host: NWEndpoint.Host(peer.ipAddress), port: 3240),
      request: Data([1, 17, 128, 5, 0, 0, 0, 0])
    ) { [weak self] data, _ in
      guard let self, self.generation == scan, Self.isUSBIPReply(data) else { return }
      let id = "usbip:\(peer.ipAddress)"
      self.peers[id] = DiscoveredDebagrPeer(
        peer: DebagrPeer(protocolVersion: 1, nodeID: id, name: peer.hostname, roles: ["server"]),
        address: "\(peer.ipAddress):3240", source: "USB/IP protocol reply")
      self.emit()
    }
  }

  private func exchange(
    _ endpoint: NWEndpoint, request: Data?, received: @escaping (Data, NWEndpoint) -> Void
  ) {
    guard connections.count < 64 else { return }
    let id = UUID()
    let connection = NWConnection(to: endpoint, using: .tcp)
    connections[id] = connection
    var buffer = Data()
    func finish(_ data: Data?) {
      guard connections.removeValue(forKey: id) != nil else { return }
      let resolved = connection.currentPath?.remoteEndpoint ?? endpoint
      connection.stateUpdateHandler = nil
      connection.cancel()
      if let data { received(data, resolved) }
    }
    func read() {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
        data, _, complete, error in
        if let data { buffer.append(data) }
        if buffer.count > 16_384 {
          finish(nil)
        } else if request != nil && buffer.count >= 12 {
          finish(buffer)
        } else if let end = buffer.firstIndex(of: 10) {
          finish(Data(buffer[..<end]))
        } else if complete || error != nil {
          finish(buffer)
        } else {
          read()
        }
      }
    }
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        if let request {
          connection.send(
            content: request,
            completion: .contentProcessed { error in
              if error != nil { finish(nil) } else { read() }
            })
        } else {
          read()
        }
      case .failed, .cancelled: finish(nil)
      default: break
      }
    }
    connection.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 3) { finish(nil) }
  }

  private func emit(_ status: String = "") {
    let rows = peers.values.sorted {
      $0.peer.name.localizedStandardCompare($1.peer.name) == .orderedAscending
    }
    DispatchQueue.main.async { [weak self] in self?.onChange?(rows, status) }
  }
}
