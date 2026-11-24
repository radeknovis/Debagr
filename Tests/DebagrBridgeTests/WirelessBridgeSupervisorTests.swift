import DebagrCore
import Foundation
import Testing

@testable import DebagrBridge

@Suite("WirelessBridgeSupervisor State Machine")
struct WirelessBridgeSupervisorTests {
  private func makeProfile(ip: String = "100.64.10.20") -> ManagedDeviceProfile {
    ManagedDeviceProfile(
      udid: "00008140-001E45990413C01C",
      coreDeviceID: "CORE-1",
      displayName: "Roaming iPhone",
      model: "iPhone 16 Pro",
      platform: .iOS,
      vpn: VPNEndpoint(
        provider: .tailscale,
        address: ip,
        peerName: "roaming-iphone",
        tailscaleNodeID: "node-123"
      ),
      wirelessIdentity: WirelessIdentity(
        bonjourInstanceName: "11:22:33:44:55:66@abcdef0123456789",
        txtRecords: ["v": "1"],
        confirmedHardwareUDID: "00008140-001E45990413C01C"
      )
    )
  }

  private func makeDevice(
    transport: TransportType = .localNetwork,
    tunnel: TunnelState = .disconnected
  ) -> PhysicalDevice {
    PhysicalDevice(
      coreDeviceID: "CORE-1",
      udid: "00008140-001E45990413C01C",
      name: "Roaming iPhone",
      model: "iPhone 16 Pro",
      platform: .iOS,
      osVersion: "27.3",
      reality: .physical,
      pairingState: .paired,
      transportType: transport,
      tunnelState: tunnel
    )
  }

  @Test(
    "Bridge transitions across unconfigured, active VPN bridge, native USB yield, sleep/wake, and IP update"
  )
  func supervisorTransitions() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("debagr-bridge-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let cfgStore = FileConfigStore(directoryURL: tempDir)
    let stateStore = FileBridgeStateStore(directoryURL: tempDir)
    let devicectl = BridgeMockDeviceCtl(devices: [
      makeDevice(transport: .localNetwork, tunnel: .disconnected)
    ])
    let dnssd = MockDNSSDController()
    let probe = MockTCPProbe(reachable: true)
    let vpn = BridgeMockVPNDiscovery(ip: "100.64.10.20")

    let supervisor = WirelessBridgeSupervisor(
      configStore: cfgStore,
      bridgeStateStore: stateStore,
      devicectl: devicectl,
      dnssd: dnssd,
      tcpProbe: probe,
      vpnDiscovery: vpn
    )

    // 1. Unconfigured
    let s1 = await supervisor.reconcileOnce()
    #expect(s1.state == .unconfigured)
    #expect(await dnssd.activeProxyCount == 0)

    // 2. Save profile -> remote over VPN reachable -> bridgingActive
    try cfgStore.save(DebagrConfig(managedDevice: makeProfile()))
    let s2 = await supervisor.reconcileOnce()
    #expect(s2.state == .bridgingActive)
    #expect(s2.activeProxyHost == "100.64.10.20")
    #expect(await dnssd.activeProxyCount == 1)

    // 3. Reconciling again keeps existing proxy without churn
    let startsBefore = await dnssd.startCount
    let s3 = await supervisor.reconcileOnce()
    #expect(s3.state == .bridgingActive)
    #expect(await dnssd.startCount == startsBefore)

    // 4. Device plugged into USB -> tears down proxy and enters nativeLocalStandby
    await devicectl.setDevices([makeDevice(transport: .wired, tunnel: .connected)])
    let s4 = await supervisor.reconcileOnce()
    #expect(s4.state == .nativeLocalStandby)
    #expect(s4.nativeTransport == .wired)
    #expect(await dnssd.activeProxyCount == 0)

    // 5. Device unplugged & away -> restores bridgingActive
    await devicectl.setDevices([makeDevice(transport: .localNetwork, tunnel: .disconnected)])
    let s5 = await supervisor.reconcileOnce()
    #expect(s5.state == .bridgingActive)
    #expect(await dnssd.activeProxyCount == 1)

    // 6. Sleep event tears down proxy; wake restores it
    let s6 = await supervisor.handleSystemEvent(.systemWillSleep)
    #expect(s6.state == .paused)
    #expect(await dnssd.activeProxyCount == 0)

    let s7 = await supervisor.handleSystemEvent(.systemDidWake)
    #expect(s7.state == .bridgingActive)
    #expect(await dnssd.activeProxyCount == 1)

    // 7. Tailscale peer IP rotation updates proxy registration automatically
    await vpn.setIP("100.64.99.88")
    let s8 = await supervisor.reconcileOnce()
    #expect(s8.state == .bridgingActive)
    #expect(s8.activeProxyHost == "100.64.99.88")
    #expect(await dnssd.activeProxyCount == 1)
    let savedConfig = try cfgStore.load()
    #expect(savedConfig.managedDevice?.vpn.address == "100.64.99.88")

    // 8. VPN probe goes offline -> tears down proxy and marks deviceOffline
    await probe.setReachable(false)
    let s9 = await supervisor.reconcileOnce()
    #expect(s9.state == .deviceOffline)
    #expect(await dnssd.activeProxyCount == 0)

    // 9. Network path drop -> vpnUnavailable; restore + probe -> bridgingActive
    let s10 = await supervisor.handleSystemEvent(.networkChanged(isSatisfied: false))
    #expect(s10.state == .vpnUnavailable)
    await probe.setReachable(true)
    let s11 = await supervisor.handleSystemEvent(.networkChanged(isSatisfied: true))
    #expect(s11.state == .bridgingActive)

    // 10. Ephemeral CLI/MCP supervisor checks live bridge-state.json without starting duplicate proxy
    //     and stop(persistState: false) leaves persisted .bridgingActive state intact.
    let ephemeral = WirelessBridgeSupervisor(
      configStore: cfgStore,
      bridgeStateStore: stateStore,
      devicectl: devicectl,
      dnssd: dnssd,
      tcpProbe: probe,
      vpnDiscovery: vpn
    )
    let startsBeforeEphemeral = await dnssd.startCount
    let ensured = await ephemeral.ensureReadyForDeployment()
    #expect(ensured.state == .bridgingActive)
    #expect(await dnssd.startCount == startsBeforeEphemeral)
    await ephemeral.stop(persistState: false)
    let persistedAfter = try stateStore.load()
    #expect(persistedAfter?.state == .bridgingActive)
  }

  @Test(
    "stop() tears down in-flight proxy registration and makes subsequent reconciles no-ops"
  )
  func stopCancelsInFlightProxyAndPreventsRestart() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("debagr-bridge-stop-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let cfgStore = FileConfigStore(directoryURL: tempDir)
    let stateStore = FileBridgeStateStore(directoryURL: tempDir)
    try cfgStore.save(DebagrConfig(managedDevice: makeProfile()))

    let devicectl = BridgeMockDeviceCtl(devices: [
      makeDevice(transport: .localNetwork, tunnel: .disconnected)
    ])
    let dnssd = GatedMockDNSSDController()
    let probe = MockTCPProbe(reachable: true)
    let vpn = BridgeMockVPNDiscovery(ip: "100.64.10.20")

    let supervisor = WirelessBridgeSupervisor(
      configStore: cfgStore,
      bridgeStateStore: stateStore,
      devicectl: devicectl,
      dnssd: dnssd,
      tcpProbe: probe,
      vpnDiscovery: vpn
    )

    let reconcileTask = Task {
      await supervisor.reconcileOnce()
    }

    await dnssd.waitUntilStartProxyEntered()
    await supervisor.stop()
    await dnssd.releaseStartProxy()

    let reconcileSnap = await reconcileTask.value
    #expect(reconcileSnap.state == .paused)
    #expect(reconcileSnap.lastTransitionReason == "Bridge stopped")
    #expect(await dnssd.activeProxyCount == 0)

    let persistedAfterStop = try stateStore.load()
    #expect(persistedAfterStop?.state == .paused)
    #expect(persistedAfterStop?.lastTransitionReason == "Bridge stopped")

    let startsAtStop = await dnssd.startCount
    let postStopReconcile = await supervisor.reconcileOnce()
    let postStopWake = await supervisor.handleSystemEvent(.systemDidWake)
    #expect(postStopReconcile.state == .paused)
    #expect(postStopWake.state == .paused)
    #expect(await dnssd.startCount == startsAtStop)
    #expect(await dnssd.activeProxyCount == 0)
  }
}

actor BridgeMockDeviceCtl: DeviceControlling {
  private var devices: [PhysicalDevice]

  init(devices: [PhysicalDevice]) {
    self.devices = devices
  }

  func setDevices(_ next: [PhysicalDevice]) {
    devices = next
  }

  func version() async throws -> String? { "651.31" }
  func listDevices(timeout: TimeInterval) async throws -> [PhysicalDevice] { devices }
  func deviceDetails(identifier: String, timeout: TimeInterval) async throws -> PhysicalDevice {
    devices[0]
  }
  func lockState(identifier: String, timeout: TimeInterval) async throws -> LockState { .unlocked }
  func listApps(identifier: String, bundleID: String?, timeout: TimeInterval) async throws
    -> [InstalledApp]
  { [] }
  func installApp(identifier: String, appPath: String, timeout: TimeInterval) async throws
    -> DeviceCtlInstallOutcome
  { DeviceCtlInstallOutcome(bundleIdentifier: nil, launchServicesIdentifier: nil) }
  func launchApp(
    identifier: String,
    bundleID: String,
    arguments: [String],
    environment: [String: String],
    terminateExisting: Bool,
    launchServicesIdentifier: String?,
    timeout: TimeInterval
  ) async throws -> DeviceCtlLaunchOutcome { DeviceCtlLaunchOutcome(pid: 1) }
  func pairDevice(identifier: String, timeout: TimeInterval) async throws {}
}

actor MockDNSSDController: DNSSDControlling {
  private(set) var activeProxies: [UUID: ProxyHandle] = [:]
  private(set) var startCount = 0

  var activeProxyCount: Int { activeProxies.count }

  func browseMobdevServices(timeoutSeconds: TimeInterval) async throws -> [BonjourServiceRecord] {
    []
  }

  func startProxy(_ spec: ProxyRegistrationSpec) async throws -> ProxyHandle {
    startCount += 1
    let handle = ProxyHandle(spec: spec)
    activeProxies[handle.id] = handle
    return handle
  }

  func stopProxy(_ handle: ProxyHandle) async {
    activeProxies.removeValue(forKey: handle.id)
  }

  func stopAllProxies() async {
    activeProxies.removeAll()
  }
}

actor GatedMockDNSSDController: DNSSDControlling {
  private(set) var activeProxies: [UUID: ProxyHandle] = [:]
  private(set) var startCount = 0
  private var entered = false
  private var enteredWaiter: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  var activeProxyCount: Int { activeProxies.count }

  func browseMobdevServices(timeoutSeconds: TimeInterval) async throws -> [BonjourServiceRecord] {
    []
  }

  func waitUntilStartProxyEntered() async {
    if entered { return }
    await withCheckedContinuation { continuation in
      enteredWaiter = continuation
    }
  }

  func releaseStartProxy() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }

  func startProxy(_ spec: ProxyRegistrationSpec) async throws -> ProxyHandle {
    startCount += 1
    entered = true
    enteredWaiter?.resume()
    enteredWaiter = nil
    await withCheckedContinuation { continuation in
      releaseContinuation = continuation
    }
    let handle = ProxyHandle(spec: spec)
    activeProxies[handle.id] = handle
    return handle
  }

  func stopProxy(_ handle: ProxyHandle) async {
    activeProxies.removeValue(forKey: handle.id)
  }

  func stopAllProxies() async {
    activeProxies.removeAll()
  }
}

actor MockTCPProbe: TCPProbing {
  private var reachable: Bool

  init(reachable: Bool) {
    self.reachable = reachable
  }

  func setReachable(_ next: Bool) {
    reachable = next
  }

  func probe(host: String, port: UInt16, timeoutSeconds: TimeInterval) async -> Bool {
    reachable
  }
}

actor BridgeMockVPNDiscovery: VPNPeerDiscovering {
  private var ip: String

  init(ip: String) {
    self.ip = ip
  }

  func setIP(_ next: String) {
    ip = next
  }

  func discoverPeers(provider: VPNProvider) async -> VPNEnvironmentStatus {
    let current = ip
    return VPNEnvironmentStatus(
      provider: provider,
      available: true,
      detail: "OK",
      peers: [
        VPNPeer(
          id: "node-123",
          name: "roaming-iphone",
          addresses: [current],
          os: "iOS",
          online: true,
          provider: provider
        )
      ]
    )
  }
}
