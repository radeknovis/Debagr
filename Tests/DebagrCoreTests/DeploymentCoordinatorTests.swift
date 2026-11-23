import Foundation
import Testing

@testable import DebagrCore

@Suite("DeploymentCoordinator & Error Recovery")
struct DeploymentCoordinatorTests {
  private func makeTempStore() throws -> (
    URL, FileConfigStore, FileReceiptStore, FileBridgeStateStore
  ) {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("debagr-coord-test-\(UUID().uuidString)", isDirectory: true)
    let cfg = FileConfigStore(directoryURL: dir)
    let profile = ManagedDeviceProfile(
      udid: "00008140-001E45990413C01C",
      coreDeviceID: "CORE-1",
      displayName: "Pocket iPhone",
      model: "iPhone 16 Pro",
      platform: .iOS,
      vpn: VPNEndpoint(provider: .tailscale, address: "100.64.5.9"),
      wirelessIdentity: WirelessIdentity(
        bonjourInstanceName: "de:ad:be:ef:00:01@feedfacecafebeef",
        txtRecords: ["token": "super-secret-txt"],
        confirmedHardwareUDID: "00008140-001E45990413C01C"
      )
    )
    try cfg.save(DebagrConfig(managedDevice: profile))
    return (
      dir,
      cfg,
      FileReceiptStore(directoryURL: dir),
      FileBridgeStateStore(directoryURL: dir)
    )
  }

  private func sampleDevice(
    pairingState: PairingState = .paired,
    tunnelState: TunnelState = .connected
  ) -> PhysicalDevice {
    PhysicalDevice(
      coreDeviceID: "CORE-1",
      udid: "00008140-001E45990413C01C",
      name: "Pocket iPhone",
      model: "iPhone 16 Pro",
      platform: .iOS,
      osVersion: "27.3",
      reality: .physical,
      pairingState: pairingState,
      transportType: .localNetwork,
      tunnelState: tunnelState,
      isDeveloperModeEnabled: true
    )
  }

  private func sampleBundle() -> ValidatedAppBundle {
    ValidatedAppBundle(
      path: "/tmp/Demo.app",
      bundleIdentifier: "com.example.demo",
      displayName: "Demo",
      shortVersion: "1.0",
      buildVersion: "10",
      platformName: "iphoneos",
      signingAuthority: "Apple Development"
    )
  }

  @Test("Happy path deploy installs, verifies, launches, and records receipt")
  func deployHappyPath() async throws {
    let (dir, cfg, receipts, bridgeStore) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let devicectl = MockDeviceCtl(
      devices: [sampleDevice()],
      lockStateValue: .unlocked,
      appsAfterInstall: [InstalledApp(bundleIdentifier: "com.example.demo", name: "Demo")],
      installOutcome: DeviceCtlInstallOutcome(
        bundleIdentifier: "com.example.demo",
        launchServicesIdentifier: "LS-123"
      ),
      launchOutcome: DeviceCtlLaunchOutcome(pid: 9876)
    )

    let coordinator = DeploymentCoordinator(
      devicectl: devicectl,
      appValidator: MockBundleValidator(bundle: sampleBundle()),
      configStore: cfg,
      receiptStore: receipts,
      bridgeStateStore: bridgeStore,
      vpnDiscovery: MockVPNDiscovery(),
      runner: MockNoopRunner()
    )

    let result = try await coordinator.deploy(appPath: "/tmp/Demo.app")
    #expect(result.installed)
    #expect(result.verifiedInstalled)
    #expect(result.launched)
    #expect(result.pid == 9876)
    #expect(result.launchServicesIdentifier == "LS-123")

    let savedReceipts = try receipts.listRecent(limit: 5)
    #expect(savedReceipts.count == 1)
    #expect(savedReceipts[0].outcome == .succeeded)
    #expect(savedReceipts[0].pid == 9876)
  }

  @Test("Locked device fails fast with DEVICE_LOCKED before install when launch requested")
  func deployFailsFastWhenLocked() async throws {
    let (dir, cfg, receipts, bridgeStore) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let devicectl = MockDeviceCtl(devices: [sampleDevice()], lockStateValue: .locked)
    let coordinator = DeploymentCoordinator(
      devicectl: devicectl,
      appValidator: MockBundleValidator(bundle: sampleBundle()),
      configStore: cfg,
      receiptStore: receipts,
      bridgeStateStore: bridgeStore,
      vpnDiscovery: MockVPNDiscovery(),
      runner: MockNoopRunner()
    )

    do {
      _ = try await coordinator.deploy(appPath: "/tmp/Demo.app")
      Issue.record("Expected DEVICE_LOCKED")
    } catch let err as DebagrError {
      #expect(err.payload.code == .deviceLocked)
      #expect(err.payload.recoverable)
      #expect(!err.payload.nextSteps.isEmpty)
    }

    let installCalls = await devicectl.installCallCount
    #expect(installCalls == 0)
  }

  @Test(
    "Launch failure after verified install yields INSTALL_SUCCEEDED_LAUNCH_FAILED with partialSuccess state"
  )
  func deployPartialSuccessLaunchFailed() async throws {
    let (dir, cfg, receipts, bridgeStore) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let devicectl = MockDeviceCtl(
      devices: [sampleDevice()],
      lockStateValue: .unlocked,
      appsAfterInstall: [InstalledApp(bundleIdentifier: "com.example.demo")],
      installOutcome: DeviceCtlInstallOutcome(
        bundleIdentifier: "com.example.demo",
        launchServicesIdentifier: "LS-ABC"
      ),
      launchError: DebagrError(
        code: .launchFailed,
        category: "launch",
        message: "Developer profile not trusted on device"
      )
    )

    let coordinator = DeploymentCoordinator(
      devicectl: devicectl,
      appValidator: MockBundleValidator(bundle: sampleBundle()),
      configStore: cfg,
      receiptStore: receipts,
      bridgeStateStore: bridgeStore,
      vpnDiscovery: MockVPNDiscovery(),
      runner: MockNoopRunner()
    )

    do {
      _ = try await coordinator.deploy(appPath: "/tmp/Demo.app")
      Issue.record("Expected INSTALL_SUCCEEDED_LAUNCH_FAILED")
    } catch let err as DebagrError {
      #expect(err.payload.code == .installSucceededLaunchFailed)
      let partial = try #require(err.payload.partialSuccess)
      #expect(partial.installed)
      #expect(partial.verifiedInstalled)
      #expect(!partial.launched)
      #expect(partial.launchServicesIdentifier == "LS-ABC")
    }

    let savedReceipts = try receipts.listRecent(limit: 5)
    #expect(savedReceipts.first?.outcome == .partialSuccessLaunchFailed)
  }

  @Test("Install timeout runs post-timeout verification and reports OPERATION_TIMEOUT_UNCERTAIN")
  func deployInstallTimeoutUncertain() async throws {
    let (dir, cfg, receipts, bridgeStore) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let devicectl = MockDeviceCtl(
      devices: [sampleDevice()],
      lockStateValue: .unlocked,
      appsAfterInstall: [InstalledApp(bundleIdentifier: "com.example.demo")],
      installError: DebagrError(
        code: .operationTimeoutUncertain,
        category: "timeout",
        message: "Timed out"
      )
    )

    let coordinator = DeploymentCoordinator(
      devicectl: devicectl,
      appValidator: MockBundleValidator(bundle: sampleBundle()),
      configStore: cfg,
      receiptStore: receipts,
      bridgeStateStore: bridgeStore,
      vpnDiscovery: MockVPNDiscovery(),
      runner: MockNoopRunner()
    )

    do {
      _ = try await coordinator.deploy(appPath: "/tmp/Demo.app", timeoutSeconds: 30)
      Issue.record("Expected OPERATION_TIMEOUT_UNCERTAIN")
    } catch let err as DebagrError {
      #expect(err.payload.code == .operationTimeoutUncertain)
      #expect(err.payload.partialSuccess?.installed == true)
      #expect(err.payload.partialSuccess?.verifiedInstalled == true)
    }
  }

  @Test("Doctor redacted output never contains Bonjour wireless identity or raw pairing tokens")
  func doctorRedactsSensitiveMetadata() async throws {
    let (dir, cfg, receipts, bridgeStore) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    try bridgeStore.save(
      BridgeStateSnapshot(
        state: .bridgingActive,
        activeProxyHost: "100.64.5.9",
        activeProxyPort: 62078,
        vpnReachable: true,
        lastTransitionReason: "Proxy registered for de:ad:be:ef:00:01@feedfacecafebeef"
      )
    )

    let coordinator = DeploymentCoordinator(
      devicectl: MockDeviceCtl(devices: [sampleDevice()], lockStateValue: .unlocked),
      appValidator: MockBundleValidator(bundle: sampleBundle()),
      configStore: cfg,
      receiptStore: receipts,
      bridgeStateStore: bridgeStore,
      vpnDiscovery: MockVPNDiscovery(),
      runner: MockNoopRunner()
    )

    let report = try await coordinator.doctor(strictRedaction: true)
    let encoded = try String(decoding: JSONEncoder().encode(report), as: UTF8.self)
    #expect(!encoded.contains("de:ad:be:ef:00:01@feedfacecafebeef"))
    #expect(!encoded.contains("super-secret-txt"))
    #expect(!encoded.contains("00008140-001E45990413C01C"))
    #expect(!encoded.contains("100.64.5.9"))
    #expect(report.storagePermissionsOK)
  }
}

actor MockDeviceCtl: DeviceControlling {
  let devices: [PhysicalDevice]
  let lockStateValue: LockState
  let appsAfterInstall: [InstalledApp]
  let installOutcome: DeviceCtlInstallOutcome
  let installError: DebagrError?
  let launchOutcome: DeviceCtlLaunchOutcome
  let launchError: DebagrError?
  private(set) var installCallCount = 0

  init(
    devices: [PhysicalDevice],
    lockStateValue: LockState = .unlocked,
    appsAfterInstall: [InstalledApp] = [],
    installOutcome: DeviceCtlInstallOutcome = DeviceCtlInstallOutcome(
      bundleIdentifier: nil,
      launchServicesIdentifier: nil
    ),
    installError: DebagrError? = nil,
    launchOutcome: DeviceCtlLaunchOutcome = DeviceCtlLaunchOutcome(pid: 100),
    launchError: DebagrError? = nil
  ) {
    self.devices = devices
    self.lockStateValue = lockStateValue
    self.appsAfterInstall = appsAfterInstall
    self.installOutcome = installOutcome
    self.installError = installError
    self.launchOutcome = launchOutcome
    self.launchError = launchError
  }

  func version() async throws -> String? { "651.31" }
  func listDevices(timeout: TimeInterval) async throws -> [PhysicalDevice] { devices }
  func deviceDetails(identifier: String, timeout: TimeInterval) async throws -> PhysicalDevice {
    devices[0]
  }
  func lockState(identifier: String, timeout: TimeInterval) async throws -> LockState {
    lockStateValue
  }
  func listApps(identifier: String, bundleID: String?, timeout: TimeInterval) async throws
    -> [InstalledApp]
  {
    appsAfterInstall
  }
  func installApp(identifier: String, appPath: String, timeout: TimeInterval) async throws
    -> DeviceCtlInstallOutcome
  {
    installCallCount += 1
    if let installError { throw installError }
    return installOutcome
  }
  func launchApp(
    identifier: String,
    bundleID: String,
    arguments: [String],
    environment: [String: String],
    terminateExisting: Bool,
    launchServicesIdentifier: String?,
    timeout: TimeInterval
  ) async throws -> DeviceCtlLaunchOutcome {
    if let launchError { throw launchError }
    return launchOutcome
  }
  func pairDevice(identifier: String, timeout: TimeInterval) async throws {}
}

struct MockBundleValidator: AppBundleValidating {
  let bundle: ValidatedAppBundle
  func validate(appPath: String) async throws -> ValidatedAppBundle { bundle }
}

struct MockVPNDiscovery: VPNPeerDiscovering {
  func discoverPeers(provider: VPNProvider) async -> VPNEnvironmentStatus {
    VPNEnvironmentStatus(provider: provider, available: true, detail: "Mock VPN ok", peers: [])
  }
}

struct MockNoopRunner: CommandRunning {
  func run(
    executable: String,
    arguments: [String],
    environment: [String: String]?,
    timeoutSeconds: TimeInterval
  ) async throws -> CommandResult {
    CommandResult(
      exitCode: 0, stdout: Data("Xcode 27.2\n".utf8), stderr: Data(), timedOut: false, durationMs: 1
    )
  }
}
