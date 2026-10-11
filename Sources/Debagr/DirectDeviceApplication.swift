import Foundation
import Network

/// Publishes a local proxy and relays directly to the device's tailnet address.
/// Reachability and an advertisement alone do not prove a usable CoreDevice tunnel.
final class DirectDeviceApplication: ApplicationLifecycle {
  private let options: CommandLineOptions
  private var proxy: BonjourProxy?
  private let watcher = TunnelPortWatcher()
  private let relayQueue = DispatchQueue(label: "debagr.direct-device-relays")
  private var pairs: [UInt16: RelayPair] = [:]
  private var stopped = false
  private var lease: RelayLease?
  private let configuredProfile: DeviceProfile?
  private let onTunnelPort: ((UInt16) -> Void)?

  init(options: CommandLineOptions) {
    self.options = options
    configuredProfile = nil
    onTunnelPort = nil
  }

  init(device: ConfiguredDevice, onTunnelPort: ((UInt16) -> Void)? = nil) {
    var options = try! CommandLineOptions.parse([])
    options.peerName = device.peerName
    options.interfaceName = device.interfaceName
    self.options = options
    configuredProfile = device.profile
    self.onTunnelPort = onTunnelPort
  }

  static func captureProfile(options: CommandLineOptions) throws {
    guard let peerName = options.peerName, let host = options.bonjourHost else {
      throw CLIError.invalidDirectDeviceOptions
    }
    let profile = try capturedProfile(peerName: peerName, host: host, timeout: options.timeout)
    try ProfileStore(url: options.profileURL).save(profile)
    print(
      "Captured Target Device service on port \(profile.remotePort) for \(profile.peerIP). TXT values are not logged."
    )
    print("Keep this profile private. Recapture if the device's service identity or port changes.")
  }

  static func capturedProfile(peerName: String, host: String, timeout: TimeInterval) throws
    -> DeviceProfile
  {
    let peer = try TailscaleClient().selectPeer(named: peerName)
    let capture = BonjourCapture()
    defer { capture.stop() }
    let completed = DispatchSemaphore(value: 0)
    let result = LockedValue<BonjourDevice?>(nil)
    try capture.startZoneCapture(matchingHostName: host) { device in
      result.set(device)
      completed.signal()
    }
    guard completed.wait(timeout: .now() + timeout) == .success,
      let device = result.get(), !device.txt.isEmpty
    else { throw CLIError.discoveryTimedOut }

    return DeviceProfile(
      bonjourName: device.instanceName,
      bonjourTXT: device.txt,
      provider: "tailscale",
      peerIP: peer.ipAddress,
      remotePort: device.port,
      localPortRange: DeviceProfile.defaultLocalPortRange
    )
  }

  static func makeProxy(
    profile: DeviceProfile, peer: SelectedTailscalePeer,
    interfaceName: String, localIP: String, localPort: UInt16
  ) throws -> BonjourProxy {
    try profile.validate()
    guard profile.peerIP == peer.ipAddress, !profile.bonjourTXT.isEmpty else {
      throw CLIError.invalidDirectDeviceOptions
    }
    return try BonjourProxy(
      interfaceName: interfaceName,
      instanceName: profile.bonjourName,
      localPort: localPort,
      localHost: "debagr-\(peer.ipAddress.replacingOccurrences(of: ".", with: "-")).local",
      localIP: localIP,
      txt: profile.bonjourTXT
    )
  }

  func start() throws {
    guard let peerName = options.peerName,
      let profile = try configuredProfile ?? ProfileStore(url: options.profileURL).load()
    else { throw CLIError.invalidDirectDeviceOptions }
    let peer = try TailscaleClient().selectPeer(named: peerName)
    let binding = try NetworkSupport.resolveInterface(named: options.interfaceName)
    // Validate the selected device before opening any listeners.
    let proxy = try Self.makeProxy(
      profile: profile, peer: peer, interfaceName: "0",
      localIP: binding.ipv4Address, localPort: profile.remotePort)
    do {
      lease = try RelayLease(port: profile.remotePort)
      try relayQueue.sync {
        try startRelay(port: profile.remotePort, binding: binding, peer: peer)
        for port in profile.tunnelPortRange[0]...profile.tunnelPortRange[1]
        where port != profile.remotePort {
          do {
            try startRelay(port: port, binding: binding, peer: peer)
          } catch {
            print("Tunnel relay unavailable on \(port): \(error.localizedDescription)")
          }
        }
      }
      try watcher.start { [weak self] port in
        self?.relayQueue.async { [weak self] in
          guard let self, !self.stopped else { return }
          do {
            try self.startRelay(port: port, binding: binding, peer: peer)
            let learned = profile.learningTunnelPort(port)
            for next in learned.tunnelPortRange[0]...learned.tunnelPortRange[1] where next != port {
              try? self.startRelay(port: next, binding: binding, peer: peer)
            }
            self.onTunnelPort?(port)
            print("Discovered tunnel relay ready on \(port).")
          } catch {
            print("Discovered tunnel relay failed on \(port): \(error.localizedDescription)")
          }
        }
      }
      try proxy.start()
      self.proxy = proxy
    } catch {
      stop()
      throw error
    }
    print(
      "Direct-device proxy ready on \(binding.ipv4Address):\(profile.remotePort), forwarding to \(peer.ipAddress)."
    )
    print(
      "Verify CoreDevice and deployment after disconnecting USB and moving the Target Device off the local network."
    )
    print("This process must remain running. No deployment success has been established.")
  }

  func stop() {
    watcher.stop()
    proxy?.stop()
    proxy = nil
    relayQueue.sync {
      stopped = true
      for pair in pairs.values {
        pair.stop()
      }
      pairs.removeAll()
      lease = nil
    }
  }

  private func startRelay(
    port: UInt16, binding: InterfaceBinding, peer: SelectedTailscalePeer
  ) throws {
    guard pairs[port] == nil else { return }
    let pair = try RelayPair(
      bindInterface: binding.networkInterface,
      remoteHost: NWEndpoint.Host(peer.ipAddress), remotePort: port, localPort: port,
      localInterfaceAddress: binding.ipv4Address,
      accessPolicy: RelayAccessPolicy(
        localInterfaceAddress: binding.ipv4Address, allowLANClients: false))
    let semaphore = DispatchSemaphore(value: 0)
    let result = LockedValue<Result<Void, Error>?>(nil)
    pair.start { value in
      result.set(value)
      semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 5) == .success, let value = result.get() else {
      pair.stop()
      throw RelayError.startupTimedOut
    }
    do {
      try value.get()
      pairs[port] = pair
    } catch {
      pair.stop()
      throw error
    }
  }
}
