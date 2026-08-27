import Foundation
import Network

final class RelayPair {
  let localPort: UInt16

  private let tcp: TCPRelay
  private let udp: UDPRelay
  private let stateLock = NSLock()
  private var readyListenerCount = 0
  private var didComplete = false
  private var didFail = false
  private var completion: ((Result<Void, Error>) -> Void)?

  init(
    bindInterface: NWInterface,
    remoteHost: NWEndpoint.Host,
    remotePort: UInt16,
    localPort: UInt16,
    localInterfaceAddress: String,
    accessPolicy: RelayAccessPolicy
  ) throws {
    self.localPort = localPort
    self.tcp = try TCPRelay(
      bindInterface: bindInterface,
      remoteHost: remoteHost,
      remotePort: remotePort,
      localPort: localPort,
      localInterfaceAddress: localInterfaceAddress,
      accessPolicy: accessPolicy
    )
    self.udp = try UDPRelay(
      bindInterface: bindInterface,
      remoteHost: remoteHost,
      remotePort: remotePort,
      localPort: localPort,
      localInterfaceAddress: localInterfaceAddress,
      accessPolicy: accessPolicy
    )
  }

  func start(completion: @escaping (Result<Void, Error>) -> Void) {
    stateLock.lock()
    self.completion = completion
    stateLock.unlock()

    tcp.start { [weak self] result in
      self?.listenerFinished(result)
    }
    stateLock.lock()
    let shouldStartUDP = !didFail
    stateLock.unlock()
    guard shouldStartUDP else {
      udp.stop()
      return
    }
    udp.start { [weak self] result in
      self?.listenerFinished(result)
    }
  }

  func stop() {
    tcp.stop()
    udp.stop()
  }

  deinit {
    stop()
  }

  private func listenerFinished(_ result: Result<Void, Error>) {
    var callback: ((Result<Void, Error>) -> Void)?
    var callbackResult: Result<Void, Error>?

    stateLock.lock()
    guard !didComplete else {
      stateLock.unlock()
      return
    }

    switch result {
    case .success:
      readyListenerCount += 1
      if readyListenerCount == 2 {
        didComplete = true
        callback = completion
        completion = nil
        callbackResult = .success(())
      }
    case .failure(let error):
      didComplete = true
      didFail = true
      callback = completion
      completion = nil
      callbackResult = .failure(error)
    }
    stateLock.unlock()

    guard let callback, let callbackResult else { return }
    if case .failure = callbackResult {
      tcp.stop()
      udp.stop()
    }
    callback(callbackResult)
  }
}

final class RelayManager {
  private let bindInterface: NWInterface
  private let remoteHost: NWEndpoint.Host
  private let localInterfaceAddress: String
  private let localPortRange: ClosedRange<UInt16>
  private let accessPolicy: RelayAccessPolicy
  private let queue = DispatchQueue(label: "nuticast-poc.relay-manager")

  private var claimedPorts = Set<UInt16>()
  private var pairs: [UInt16: RelayPair] = [:]
  private var stopped = false

  private init(
    bindInterface: NWInterface,
    remoteHost: NWEndpoint.Host,
    localInterfaceAddress: String,
    localPortRange: ClosedRange<UInt16>,
    accessPolicy: RelayAccessPolicy
  ) {
    self.bindInterface = bindInterface
    self.remoteHost = remoteHost
    self.localInterfaceAddress = localInterfaceAddress
    self.localPortRange = localPortRange
    self.accessPolicy = accessPolicy
  }

  convenience init(
    bindInterface: NWInterface,
    remoteHost: String,
    localInterfaceAddress: String,
    localPortRange: ClosedRange<UInt16>,
    allowLANClients: Bool
  ) throws {
    guard NetworkSupport.isAllowedTailscaleIPv4(remoteHost) else {
      throw RelayError.invalidDestination(remoteHost)
    }
    self.init(
      bindInterface: bindInterface,
      remoteHost: NWEndpoint.Host(remoteHost),
      localInterfaceAddress: localInterfaceAddress,
      localPortRange: localPortRange,
      accessPolicy: RelayAccessPolicy(
        localInterfaceAddress: localInterfaceAddress,
        allowLANClients: allowLANClients
      )
    )
  }

  convenience init(
    bindInterface: NWInterface,
    remoteHost: String,
    localInterfaceAddress: String,
    localPortRange: ClosedRange<UInt16>,
    accessPolicy: RelayAccessPolicy
  ) throws {
    let normalizedHost = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedHost.isEmpty,
      normalizedHost.rangeOfCharacter(from: .controlCharacters) == nil,
      NetworkSupport.isAllowedBonjourDestinationHost(normalizedHost)
    else {
      throw RelayError.invalidDestinationHost(remoteHost)
    }
    self.init(
      bindInterface: bindInterface,
      remoteHost: NWEndpoint.Host(normalizedHost),
      localInterfaceAddress: localInterfaceAddress,
      localPortRange: localPortRange,
      accessPolicy: accessPolicy
    )
  }

  func start(remotePort: UInt16, completion: @escaping (Result<UInt16, Error>) -> Void) {
    guard remotePort > 0 else {
      completion(.failure(RelayError.invalidPort(remotePort)))
      return
    }
    queue.async { [weak self] in
      self?.startNext(
        remotePort: remotePort,
        candidateIndex: 0,
        lastFailure: nil,
        completion: completion
      )
    }
  }

  func stop() {
    queue.sync {
      stopped = true
      let activePairs = Array(pairs.values)
      pairs.removeAll()
      claimedPorts.removeAll()
      for pair in activePairs {
        pair.stop()
      }
    }
  }

  deinit {
    stop()
  }

  private func startNext(
    remotePort: UInt16,
    candidateIndex: Int,
    lastFailure: String?,
    completion: @escaping (Result<UInt16, Error>) -> Void
  ) {
    guard !stopped else {
      completion(.failure(RelayError.listenerFailed("relay manager stopped")))
      return
    }

    let candidates = Array(localPortRange)
    guard candidateIndex < candidates.count else {
      completion(
        .failure(
          RelayError.noAvailableLocalPort(localPortRange, lastFailure: lastFailure)))
      return
    }

    let candidate = candidates[candidateIndex]
    if claimedPorts.contains(candidate) {
      startNext(
        remotePort: remotePort,
        candidateIndex: candidateIndex + 1,
        lastFailure: lastFailure,
        completion: completion
      )
      return
    }

    claimedPorts.insert(candidate)

    do {
      let pair = try RelayPair(
        bindInterface: bindInterface,
        remoteHost: remoteHost,
        remotePort: remotePort,
        localPort: candidate,
        localInterfaceAddress: localInterfaceAddress,
        accessPolicy: accessPolicy
      )
      pairs[candidate] = pair

      pair.start { [weak self] result in
        guard let self else { return }
        self.queue.async {
          guard !self.stopped else {
            self.pairs.removeValue(forKey: candidate)?.stop()
            self.claimedPorts.remove(candidate)
            return
          }

          switch result {
          case .success:
            completion(.success(candidate))
          case .failure(let error):
            self.pairs.removeValue(forKey: candidate)
            self.claimedPorts.remove(candidate)
            self.startNext(
              remotePort: remotePort,
              candidateIndex: candidateIndex + 1,
              lastFailure: error.localizedDescription,
              completion: completion
            )
          }
        }
      }
    } catch {
      claimedPorts.remove(candidate)
      startNext(
        remotePort: remotePort,
        candidateIndex: candidateIndex + 1,
        lastFailure: error.localizedDescription,
        completion: completion
      )
    }
  }
}
