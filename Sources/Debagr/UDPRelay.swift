import Foundation
import Network

final class UDPRelay {
  private let listener: RelayListener
  var isHealthy: Bool { listener.isHealthy }

  init(
    bindInterface: NWInterface?, remoteHost: NWEndpoint.Host, remotePort: UInt16,
    localPort: UInt16, localInterfaceAddress: String, accessPolicy: RelayAccessPolicy
  ) throws {
    listener = try RelayListener(
      transport: .udp, bindInterface: bindInterface,
      remoteHost: remoteHost, remotePort: remotePort, localPort: localPort,
      localInterfaceAddress: localInterfaceAddress, accessPolicy: accessPolicy
    ) { local, remote, queue, stopped in
      let flow = UDPFlow(local: local, remote: remote, queue: queue, onStop: stopped)
      flow.start()
      return { flow.stop() }
    }
  }

  func start(completion: @escaping (Result<Void, Error>) -> Void) {
    listener.start(completion: completion)
  }
  func stop() { listener.stop() }
}

private final class UDPFlow {
  private let local: NWConnection
  private let remote: NWConnection
  private let queue: DispatchQueue
  private let onStop: () -> Void
  private let stateLock = NSLock()
  private var stopped = false
  private var idleTimer: DispatchSourceTimer?
  private var lastActivity = ProcessInfo.processInfo.systemUptime

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

    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 30, repeating: 30)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      if ProcessInfo.processInfo.systemUptime - self.lastActivity >= 120 { self.stop() }
    }
    idleTimer = timer
    timer.resume()
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

    idleTimer?.cancel()
    idleTimer = nil
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

      self.lastActivity = ProcessInfo.processInfo.systemUptime
      if let data {
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
