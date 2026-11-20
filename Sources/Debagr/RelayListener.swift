import Foundation
import Network

/// Serial ownership shared by stream and datagram listeners; their data paths stay separate.
final class RelayListener {
  enum Transport { case tcp, udp }
  typealias MakeFlow = (NWConnection, NWConnection, DispatchQueue, @escaping () -> Void) -> (
    () -> Void
  )
  private let transport: Transport
  private let bindInterface: NWInterface?
  private let remoteHost: NWEndpoint.Host
  private let remotePort: NWEndpoint.Port
  private let localPort: NWEndpoint.Port
  private let localAddress: String
  private let accessPolicy: RelayAccessPolicy
  private let makeFlow: MakeFlow
  private let queue: DispatchQueue
  private let queueKey = DispatchSpecificKey<Bool>()
  private let healthy = LockedValue(false)
  var isHealthy: Bool { healthy.get() }
  private var listener: NWListener?
  private var flows: [UUID: () -> Void] = [:]
  private var completion: ((Result<Void, Error>) -> Void)?

  init(
    transport: Transport, bindInterface: NWInterface?, remoteHost: NWEndpoint.Host,
    remotePort: UInt16, localPort: UInt16, localInterfaceAddress: String,
    accessPolicy: RelayAccessPolicy, makeFlow: @escaping MakeFlow
  ) throws {
    guard let remote = NWEndpoint.Port(rawValue: remotePort), remotePort > 0,
      let local = NWEndpoint.Port(rawValue: localPort), localPort > 0
    else {
      throw RelayError.invalidPort(localPort == 0 ? localPort : remotePort)
    }
    self.transport = transport
    self.bindInterface = bindInterface
    self.remoteHost = remoteHost
    self.remotePort = remote
    self.localPort = local
    self.localAddress = localInterfaceAddress
    self.accessPolicy = accessPolicy
    self.makeFlow = makeFlow
    queue = DispatchQueue(label: "debagr.listener-\(transport)-\(localPort)")
    queue.setSpecific(key: queueKey, value: true)
  }

  func start(completion: @escaping (Result<Void, Error>) -> Void) {
    queue.async { [self] in
      guard self.listener == nil else {
        completion(
          self.isHealthy
            ? .success(()) : .failure(RelayError.listenerFailed("listener is not ready")))
        return
      }
      self.completion = completion
      do {
        let parameters: NWParameters = self.transport == .tcp ? .tcp : .udp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterface = self.bindInterface
        parameters.requiredLocalEndpoint = .hostPort(
          host: NWEndpoint.Host(self.localAddress), port: self.localPort)
        // Supplying `on: port` as well causes EINVAL with an exact local endpoint.
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
          guard let self else { return }
          switch state {
          case .ready:
            self.healthy.set(true)
            self.finish(.success(()))
          case .failed(let error):
            self.healthy.set(false)
            self.finish(.failure(RelayError.listenerFailed(error.localizedDescription)))
          case .cancelled:
            self.healthy.set(false)
            self.finish(.failure(RelayError.listenerFailed("cancelled")))
          default: break
          }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: self.queue)
      } catch {
        self.healthy.set(false)
        self.finish(.failure(error))
      }
    }
  }

  private func finish(_ result: Result<Void, Error>) {
    let callback = completion
    completion = nil
    callback?(result)
  }

  private func accept(_ local: NWConnection) {
    guard flows.count < 256, accessPolicy.allows(local) else {
      local.cancel()
      return
    }
    let parameters: NWParameters
    if transport == .tcp {
      let tcp = NWProtocolTCP.Options()
      tcp.enableKeepalive = true
      tcp.keepaliveIdle = 30
      tcp.keepaliveInterval = 10
      tcp.keepaliveCount = 3
      parameters = NWParameters(tls: nil, tcp: tcp)
    } else {
      parameters = .udp
    }
    let remote = NWConnection(host: remoteHost, port: remotePort, using: parameters)
    let id = UUID()
    flows[id] = makeFlow(local, remote, queue) { [weak self] in self?.flows.removeValue(forKey: id)
    }
  }

  func stop() {
    if DispatchQueue.getSpecific(key: queueKey) == nil {
      queue.sync { self.stop() }
      return
    }
    healthy.set(false)
    listener?.stateUpdateHandler = nil
    listener?.cancel()
    listener = nil
    finish(.failure(RelayError.listenerFailed("stopped")))
    let stops = Array(flows.values)
    flows.removeAll()
    for stop in stops { stop() }
  }

  deinit { stop() }
}
