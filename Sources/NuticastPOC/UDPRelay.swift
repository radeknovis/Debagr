import Foundation
import Network

final class UDPRelay {
  private let bindInterface: NWInterface
  private let remoteHost: NWEndpoint.Host
  private let remotePort: UInt16
  private let localPort: UInt16
  private let localInterfaceAddress: String
  private let accessPolicy: RelayAccessPolicy
  private let queue: DispatchQueue

  private var listener: NWListener?
  private var flows: [UUID: UDPFlow] = [:]
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
    self.queue = DispatchQueue(label: "nuticast-poc.udp-relay-\(localPort)")
  }

  func start(completion: @escaping (Result<Void, Error>) -> Void) {
    guard listener == nil else {
      completion(.success(()))
      return
    }

    do {
      let parameters = NWParameters.udp
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

    let activeFlows = Array(flows.values)
    flows.removeAll()
    for flow in activeFlows {
      flow.stop()
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
    let remoteConnection = NWConnection(to: remoteEndpoint, using: .udp)
    let identifier = UUID()
    let flow = UDPFlow(
      local: connection,
      remote: remoteConnection,
      queue: queue
    ) { [weak self] in
      self?.flows.removeValue(forKey: identifier)
    }

    flows[identifier] = flow
    flow.start()
  }
}

private final class UDPFlow {
  private let local: NWConnection
  private let remote: NWConnection
  private let queue: DispatchQueue
  private let onStop: () -> Void
  private let stateLock = NSLock()
  private var stopped = false

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
      switch state {
      case .failed, .cancelled:
        self?.stop()
      default:
        break
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

    source.receiveMessage { [weak self] data, _, _, error in
      guard let self, !self.isStopped else { return }

      if error != nil {
        self.stop()
        return
      }

      if let data, !data.isEmpty {
        destination.send(
          content: data,
          completion: .contentProcessed { [weak self] error in
            if error != nil {
              self?.stop()
            }
          })
      }

      self.receive(from: source, forwardingTo: destination)
    }
  }

  private var isStopped: Bool {
    stateLock.lock()
    let value = stopped
    stateLock.unlock()
    return value
  }
}
