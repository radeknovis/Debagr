import Foundation

/// Publishes discovery locally; Apple connects directly to the device's tailnet address.
/// Reachability and an advertisement alone do not prove a usable CoreDevice tunnel.
final class DirectDeviceApplication: ApplicationLifecycle {
  private let options: CommandLineOptions
  private var proxy: BonjourProxy?

  init(options: CommandLineOptions) {
    self.options = options
  }

  static func captureProfile(options: CommandLineOptions) throws {
    guard let peerName = options.peerName, let host = options.bonjourHost else {
      throw CLIError.invalidDirectDeviceOptions
    }
    let peer = try TailscaleClient().selectPeer(named: peerName)
    let capture = BonjourCapture()
    defer { capture.stop() }
    let completed = DispatchSemaphore(value: 0)
    let result = LockedValue<BonjourDevice?>(nil)
    try capture.startZoneCapture(matchingHostName: host) { device in
      result.set(device)
      completed.signal()
    }
    guard completed.wait(timeout: .now() + options.timeout) == .success,
      let device = result.get(), !device.txt.isEmpty
    else { throw CLIError.discoveryTimedOut }

    try ProfileStore(url: options.profileURL).save(
      DeviceProfile(
        bonjourName: device.instanceName,
        bonjourTXT: device.txt,
        provider: "tailscale",
        peerIP: peer.ipAddress,
        remotePort: device.port,
        localPortRange: DeviceProfile.defaultLocalPortRange
      ))
    print(
      "Captured Target Device service on port \(device.port) for \(peer.ipAddress). TXT values are not logged."
    )
    print("Keep this profile private. Recapture if the device's service identity or port changes.")
  }

  static func makeProxy(profile: DeviceProfile, peer: SelectedTailscalePeer) throws -> BonjourProxy
  {
    try profile.validate()
    guard profile.peerIP == peer.ipAddress, !profile.bonjourTXT.isEmpty else {
      throw CLIError.invalidDirectDeviceOptions
    }
    return try BonjourProxy(
      interfaceName: "-1",  // DNSServiceInterfaceIndexLocalOnly: do not advertise to the LAN.
      instanceName: profile.bonjourName,
      localPort: profile.remotePort,
      localHost: "debagr-\(peer.ipAddress.replacingOccurrences(of: ".", with: "-")).local",
      localIP: peer.ipAddress,
      txt: profile.bonjourTXT
    )
  }

  func start() throws {
    guard let peerName = options.peerName,
      let profile = try ProfileStore(url: options.profileURL).load()
    else { throw CLIError.invalidDirectDeviceOptions }
    let peer = try TailscaleClient().selectPeer(named: peerName)
    let proxy = try Self.makeProxy(profile: profile, peer: peer)
    try proxy.start()
    self.proxy = proxy
    print("Direct-device discovery started for \(peer.ipAddress):\(profile.remotePort).")
    print(
      "Verify CoreDevice and deployment after disconnecting USB and moving the Target Device off the local network."
    )
    print("This process must remain running. No deployment success has been established.")
  }

  func stop() {
    proxy?.stop()
    proxy = nil
  }
}
