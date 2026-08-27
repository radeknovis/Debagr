import Foundation

final class RemoteForwarderApplication: ApplicationLifecycle {
  private let options: CommandLineOptions
  private var relayManager: RelayManager?
  private var bonjourCapture: BonjourCapture?
  private let shutdownLock = NSLock()
  private var hasStopped = false

  init(options: CommandLineOptions) {
    self.options = options
  }

  func start() throws {
    do {
      let binding = try NetworkSupport.resolveTailscaleInterface()
      let selectedPeerName = try requirePeerName()
      let selectedPeer = try TailscaleClient().selectPeer(named: selectedPeerName)
      let device = try captureBonjourDevice()

      if let requestedPort = options.remotePort, requestedPort != device.port {
        throw CLIError.remotePortMismatch(
          discovered: device.port,
          requested: requestedPort
        )
      }

      let manager = try RelayManager(
        bindInterface: binding.networkInterface,
        remoteHost: device.hostName,
        localInterfaceAddress: binding.ipv4Address,
        localPortRange: device.port...device.port,
        accessPolicy: RelayAccessPolicy(
          allowedSourceAddresses: [selectedPeer.ipAddress]
        )
      )
      relayManager = manager

      let localPort = try startRelay(manager: manager, remotePort: device.port)
      print(
        "Remote forwarder selected peer: \(selectedPeer.hostname) (\(selectedPeer.ipAddress))"
      )
      print("Captured Bonjour endpoint: \(device.hostName):\(device.port)")
      print(
        "TCP and UDP forwarders ready on \(binding.ipv4Address):\(localPort) -> "
          + "Bonjour endpoint (source restricted to \(selectedPeer.ipAddress))."
      )
      print("Run the Mac mini relay with --peer \(localBonjourPeerHint()).")
    } catch {
      stop()
      throw error
    }
  }

  func stop() {
    shutdownLock.lock()
    guard !hasStopped else {
      shutdownLock.unlock()
      return
    }
    hasStopped = true
    shutdownLock.unlock()

    bonjourCapture?.stop()
    bonjourCapture = nil
    relayManager?.stop()
    relayManager = nil
  }

  private func requirePeerName() throws -> String {
    guard let peerName = options.peerName, !peerName.isEmpty else {
      throw CLIError.missingPeer
    }
    return peerName
  }

  private func captureBonjourDevice() throws -> BonjourDevice {
    let capture = BonjourCapture()
    bonjourCapture = capture
    let semaphore = DispatchSemaphore(value: 0)
    let result = LockedValue<BonjourDevice?>(nil)

    try capture.startZoneCapture { device in
      result.set(device)
      semaphore.signal()
    }

    guard semaphore.wait(timeout: .now() + options.timeout) == .success else {
      capture.stop()
      bonjourCapture = nil
      throw CLIError.discoveryTimedOut
    }

    capture.stop()
    bonjourCapture = nil

    guard let device = result.get() else {
      throw CLIError.discoveryTimedOut
    }
    return device
  }

  private func startRelay(manager: RelayManager, remotePort: UInt16) throws -> UInt16 {
    let semaphore = DispatchSemaphore(value: 0)
    let result = LockedValue<Result<UInt16, Error>?>(nil)
    manager.start(remotePort: remotePort) { value in
      result.set(value)
      semaphore.signal()
    }

    guard semaphore.wait(timeout: .now() + 30) == .success else {
      manager.stop()
      throw RelayError.startupTimedOut
    }

    guard let value = result.get() else {
      throw RelayError.startupTimedOut
    }
    return try value.get()
  }

  private func localBonjourPeerHint() -> String {
    options.peerName ?? "<mac-mini-peer>"
  }
}
