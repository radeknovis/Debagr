import Foundation
import Network

enum RelayError: LocalizedError {
  case invalidPort(UInt16)
  case invalidDestination(String)
  case invalidDestinationHost(String)
  case noAvailableLocalPort(ClosedRange<UInt16>, lastFailure: String?)
  case listenerFailed(String)
  case startupTimedOut
  case explicitAddressBindingUnavailable

  var errorDescription: String? {
    switch self {
    case .invalidPort(let port):
      return "Invalid relay port: \(port)."
    case .invalidDestination(let host):
      return "Relay destination is not an allowed Tailscale IPv4 address: \(host)."
    case .invalidDestinationHost(let host):
      return "Relay destination is not an allowed local Bonjour host: \(host)."
    case .noAvailableLocalPort(let range, let lastFailure):
      let details = lastFailure.map { " Last listener error: \($0)" } ?? ""
      return
        "No local relay port was available in \(range.lowerBound)...\(range.upperBound).\(details)"
    case .listenerFailed(let details):
      return "Relay listener failed: \(details)"
    case .startupTimedOut:
      return "Timed out while waiting for relay listeners to become ready."
    case .explicitAddressBindingUnavailable:
      return "Exact local-address binding requires macOS 26 or newer."
    }
  }
}

struct RelayAccessPolicy {
  private let allowedSourceAddresses: Set<String>?

  init(localInterfaceAddress: String, allowLANClients: Bool) {
    if allowLANClients {
      self.allowedSourceAddresses = nil
    } else {
      self.allowedSourceAddresses = [localInterfaceAddress, "127.0.0.1", "::1"]
    }
  }

  init(allowedSourceAddresses: Set<String>) {
    self.allowedSourceAddresses = allowedSourceAddresses
  }

  func allows(_ connection: NWConnection) -> Bool {
    guard let allowedSourceAddresses else { return true }

    guard case .hostPort(let host, _) = connection.endpoint else {
      return false
    }

    let sourceAddress = String(describing: host)
    return allowedSourceAddresses.contains(sourceAddress)
  }
}

final class TCPRelay {
  private let bindInterface: NWInterface
  private let remoteHost: NWEndpoint.Host
  private let remotePort: UInt16
  private let localPort: UInt16
  private let localInterfaceAddress: String
  private let accessPolicy: RelayAccessPolicy
  private let queue: DispatchQueue

  private var listener: NWListener?
  private var bridges: [UUID: TCPBridge] = [:]
  private var startCompletion: ((Result<Void, Error>) -> Void)?
  private var didCompleteStart = false

  init(
    bindInterface: NWInterface,
    remoteHost: NWEndpoint.Host,
    remotePort: UInt16,
    localPort: UInt16,
    localInterfaceAddress: String,
    accessPolicy: RelayAccessPolicy
  ) throws {
    guard localPort > 0, remotePort > 0 else {
      throw RelayError.invalidPort(localPort == 0 ? localPort : remotePort)
    }

    self.bindInterface = bindInterface
    self.remoteHost = remoteHost
    self.remotePort = remotePort
    self.localPort = localPort
    self.localInterfaceAddress = localInterfaceAddress
    self.accessPolicy = accessPolicy
    self.queue = DispatchQueue(label: "debagr.tcp-relay-\(localPort)")
  }

  func start(completion: @escaping (Result<Void, Error>) -> Void) {
    guard listener == nil else {
      completion(.success(()))
      return
    }

    do {
      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = true
      parameters.requiredInterface = bindInterface

      guard let port = NWEndpoint.Port(rawValue: localPort) else {
        throw RelayError.invalidPort(localPort)
      }

      guard #available(macOS 26.0, *) else {
        throw RelayError.explicitAddressBindingUnavailable
      }
      _ = parameters.localEndpoint(
        .hostPort(
          host: NWEndpoint.Host(localInterfaceAddress),
          port: port
        ))
      // The exact local endpoint carries both the bind address and port.
      // Passing `on: port` as well makes Network.framework reject the listener
      // with EINVAL before it can enter the ready state.
      let listener = try NWListener(using: parameters)
      self.listener = listener
      self.startCompletion = completion
      self.didCompleteStart = false

      listener.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          self.finishStart(.success(()))
        case .failed(let error):
          self.finishStart(.failure(RelayError.listenerFailed(error.localizedDescription)))
        case .cancelled:
          self.finishStart(.failure(RelayError.listenerFailed("cancelled")))
        case .setup, .waiting:
          break
        @unknown default:
          break
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        self?.accept(connection)
      }
      listener.start(queue: queue)
    } catch {
      completion(.failure(error))
    }
  }

  func stop() {
    listener?.cancel()
    listener = nil

    let activeBridges = Array(bridges.values)
    bridges.removeAll()
    for bridge in activeBridges {
      bridge.stop()
    }
  }

  deinit {
    stop()
  }

  private func finishStart(_ result: Result<Void, Error>) {
    guard !didCompleteStart else { return }
    didCompleteStart = true
    let completion = startCompletion
    startCompletion = nil
    completion?(result)
  }

  private func accept(_ connection: NWConnection) {
    guard accessPolicy.allows(connection) else {
      connection.cancel()
      return
    }

    guard let remotePort = NWEndpoint.Port(rawValue: remotePort) else {
      connection.cancel()
      return
    }

    let remoteEndpoint = NWEndpoint.hostPort(
      host: remoteHost,
      port: remotePort
    )
    let remoteConnection = NWConnection(to: remoteEndpoint, using: .tcp)
    let identifier = UUID()
    let bridge = TCPBridge(
      local: connection,
      remote: remoteConnection,
      queue: queue
    ) { [weak self] in
      self?.bridges.removeValue(forKey: identifier)
    }

    bridges[identifier] = bridge
    bridge.start()
  }
}

private final class TCPBridge {
  private let local: NWConnection
  private let remote: NWConnection
  private let queue: DispatchQueue
  private let onStop: () -> Void
  private let stateLock = NSLock()
  private var stopped = false
  private var localInputComplete = false
  private var remoteInputComplete = false

  init(
    local: NWConnection,
    remote: NWConnection,
    queue: DispatchQueue,
    onStop: @escaping () -> Void
  ) {
    self.local = local
    self.remote = remote
    self.queue = queue
    self.onStop = onStop
  }

  func start() {
    local.stateUpdateHandler = { [weak self] state in
      if case .failed = state {
        self?.stop()
      }
    }
    remote.stateUpdateHandler = { [weak self] state in
      switch state {
      case .failed, .cancelled:
        self?.stop()
      default:
        break
      }
    }

    local.start(queue: queue)
    remote.start(queue: queue)
    receive(from: local, forwardingTo: remote)
    receive(from: remote, forwardingTo: local)
  }

  func stop() {
    stateLock.lock()
    guard !stopped else {
      stateLock.unlock()
      return
    }
    stopped = true
    stateLock.unlock()

    local.cancel()
    remote.cancel()
    onStop()
  }

  private func receive(from source: NWConnection, forwardingTo destination: NWConnection) {
    guard !isStopped else { return }

    source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      [weak self] data, _, isComplete, error in
      guard let self, !self.isStopped else { return }

      if error != nil {
        self.stop()
        return
      }

      let shouldFinishAfterSend = isComplete && self.markInputComplete(for: source)
      let sendCompletion: NWConnection.SendCompletion = .contentProcessed { [weak self] error in
        guard let self else { return }
        if error != nil || (shouldFinishAfterSend && self.areBothInputsComplete) {
          self.stop()
        }
      }

      if let data, !data.isEmpty {
        destination.send(content: data, isComplete: isComplete, completion: sendCompletion)
      } else if isComplete {
        destination.send(content: nil, isComplete: true, completion: sendCompletion)
      }

      if !isComplete {
        self.receive(from: source, forwardingTo: destination)
      }
    }
  }

  private func markInputComplete(for source: NWConnection) -> Bool {
    stateLock.lock()
    if source === local {
      localInputComplete = true
    } else {
      remoteInputComplete = true
    }
    let bothComplete = localInputComplete && remoteInputComplete
    stateLock.unlock()
    return bothComplete
  }

  private var areBothInputsComplete: Bool {
    stateLock.lock()
    let bothComplete = localInputComplete && remoteInputComplete
    stateLock.unlock()
    return bothComplete
  }

  private var isStopped: Bool {
    stateLock.lock()
    let value = stopped
    stateLock.unlock()
    return value
  }
}
