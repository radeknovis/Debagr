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

    let sourceAddress: String
    switch host {
    case .ipv4(let address):
      sourceAddress = address.debugDescription.components(separatedBy: "%")[0]
    case .ipv6(let address):
      sourceAddress = address.debugDescription.components(separatedBy: "%")[0]
    default: return false
    }
    return allowedSourceAddresses.contains(sourceAddress)
  }
}

final class TCPRelay {
  private let listener: RelayListener
  var isHealthy: Bool { listener.isHealthy }

  init(
    bindInterface: NWInterface, remoteHost: NWEndpoint.Host, remotePort: UInt16,
    localPort: UInt16, localInterfaceAddress: String, accessPolicy: RelayAccessPolicy
  ) throws {
    listener = try RelayListener(
      transport: .tcp, bindInterface: bindInterface,
      remoteHost: remoteHost, remotePort: remotePort, localPort: localPort,
      localInterfaceAddress: localInterfaceAddress, accessPolicy: accessPolicy
    ) { local, remote, queue, stopped in
      let flow = TCPBridge(local: local, remote: remote, queue: queue, onStop: stopped)
      flow.start()
      return { flow.stop() }
    }
  }

  func start(completion: @escaping (Result<Void, Error>) -> Void) {
    listener.start(completion: completion)
  }
  func stop() { listener.stop() }
}

private final class TCPBridge {
  private let local: NWConnection
  private let remote: NWConnection
  private let queue: DispatchQueue
  private let onStop: () -> Void
  private let stateLock = NSLock()
  private var stopped = false
  private var waitingDeadline: DispatchWorkItem?
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
      switch state {
      case .failed, .cancelled: self?.stop()
      default: break
      }
    }
    remote.stateUpdateHandler = { [weak self] state in
      switch state {
      case .waiting:
        guard let self, self.waitingDeadline == nil else { return }
        let deadline = DispatchWorkItem { [weak self] in self?.stop() }
        self.waitingDeadline = deadline
        self.queue.asyncAfter(deadline: .now() + 15, execute: deadline)
      case .ready:
        self?.waitingDeadline?.cancel()
        self?.waitingDeadline = nil
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

    waitingDeadline?.cancel()
    waitingDeadline = nil
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
        } else if !isComplete {
          self.receive(from: source, forwardingTo: destination)
        }
      }

      if let data, !data.isEmpty {
        destination.send(content: data, isComplete: isComplete, completion: sendCompletion)
      } else if isComplete {
        destination.send(content: nil, isComplete: true, completion: sendCompletion)
      }

      if (data == nil || data?.isEmpty == true) && !isComplete {
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
