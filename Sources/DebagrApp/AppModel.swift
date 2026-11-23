import AppKit
import DebagrBridge
import DebagrCore
import DebagrExperimental
import Foundation

public enum SidebarDestination: String, CaseIterable, Identifiable, Hashable {
  case overview
  case wirelessSetup
  case agentOnboarding
  case experimental
  case preferences

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .overview: "Overview"
    case .wirelessSetup: "Wireless Setup"
    case .agentOnboarding: "Agent & SSH Setup"
    case .experimental: "Experimental"
    case .preferences: "Preferences"
    }
  }

  public var systemImage: String {
    switch self {
    case .overview: "antenna.radiowaves.left.and.right"
    case .wirelessSetup: "iphone.radiowaves.left.and.right"
    case .agentOnboarding: "terminal"
    case .experimental: "flask"
    case .preferences: "gearshape"
    }
  }
}

@MainActor
public final class AppModel: ObservableObject {
  @Published public var selectedSection: SidebarDestination = .overview
  @Published public var config: DebagrConfig = DebagrConfig()
  @Published public var bridgeSnapshot = BridgeStateSnapshot(
    state: .unconfigured,
    lastTransitionReason: "Starting..."
  )
  @Published public var readiness: ReadinessReport?
  @Published public var recentReceipts: [DeploymentReceipt] = []
  @Published public var isBridgePaused = false
  @Published public var isBusy = false
  @Published public var statusBanner: String?
  @Published public var errorBanner: String?
  @Published public var launchAtLoginStatus: LaunchAtLoginStatus = .disabled

  // Setup Wizard State
  @Published public var setupDevices: [PhysicalDevice] = []
  @Published public var setupIneligibleDevices: [PhysicalDevice] = []
  @Published public var vpnEnvironment: VPNEnvironmentStatus?
  @Published public var localWirelessCandidates: [BonjourServiceRecord] = []
  @Published public var pendingHandoffDevice: PhysicalDevice?

  // Experimental USB/IP State
  @Published public var usbipPrerequisites: USBIPToolPrerequisites?
  @Published public var usbipDiscoveredPeers: [DiscoveredUSBIPPeer] = []
  @Published public var usbipPhase: USBIPSessionPhase = .idle
  @Published public var usbipSessionID: String?
  @Published public var usbipGeneratedSAS: String?
  @Published public var usbipHandoff: WirelessHandoffPayload?

  public let configStore: FileConfigStore
  public let receiptStore: FileReceiptStore
  public let bridgeStateStore: FileBridgeStateStore
  public let supervisor: WirelessBridgeSupervisor
  public let coordinator: DeploymentCoordinator
  public let vpnDiscovery: SystemVPNPeerDiscovery
  public let usbipCoordinator: USBIPSessionCoordinator
  public let launchAtLoginManager = LaunchAtLoginManager()

  private var supervisionTask: Task<Void, Never>?
  private var eventTask: Task<Void, Never>?
  private let systemMonitor = MacOSNetworkAndSleepMonitor()

  public init() {
    let dir = FileSecurity.dataDirectoryURL()
    let cfg = FileConfigStore(directoryURL: dir)
    let receipts = FileReceiptStore(directoryURL: dir)
    let stateStore = FileBridgeStateStore(directoryURL: dir)
    let vpn = SystemVPNPeerDiscovery()
    let devicectl = SystemDeviceCtlClient()

    self.configStore = cfg
    self.receiptStore = receipts
    self.bridgeStateStore = stateStore
    self.vpnDiscovery = vpn

    let sup = WirelessBridgeSupervisor(
      configStore: cfg,
      bridgeStateStore: stateStore,
      devicectl: devicectl,
      vpnDiscovery: vpn
    )
    self.supervisor = sup
    self.coordinator = DeploymentCoordinator(
      devicectl: devicectl,
      configStore: cfg,
      receiptStore: receipts,
      bridgeStateStore: stateStore,
      vpnDiscovery: vpn,
      bridgeEnsurer: sup
    )
    self.usbipCoordinator = USBIPSessionCoordinator(devicectl: devicectl)

    if let loaded = try? cfg.load() {
      self.config = loaded
    }
    self.launchAtLoginStatus = launchAtLoginManager.currentStatus()
    self.recentReceipts = (try? receipts.listRecent(limit: 20)) ?? []

    if self.config.managedDevice == nil {
      self.selectedSection = .wirelessSetup
    }

    startBackgroundSupervision()
  }

  public var menuBarIconName: String {
    if config.managedDevice == nil {
      return "iphone.slash"
    }
    if readiness?.lockState.blocksForegroundLaunch == true {
      return "lock.iphone"
    }
    switch bridgeSnapshot.state {
    case .bridgingActive:
      return "antenna.radiowaves.left.and.right"
    case .nativeLocalStandby:
      return "cable.connector"
    case .paused:
      return "pause.circle"
    case .deviceOffline, .vpnUnavailable, .error:
      return "exclamationmark.triangle"
    case .unconfigured, .probingVPN:
      return "iphone.radiowaves.left.and.right"
    }
  }

  public var binaryPathForAgents: String {
    let current = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? "debagr"
    return current
  }

  public func startBackgroundSupervision() {
    guard supervisionTask == nil else { return }

    eventTask = Task { [weak self] in
      guard let self else { return }
      for await event in self.systemMonitor.events() {
        if Task.isCancelled { break }
        let snap = await self.supervisor.handleSystemEvent(event)
        self.bridgeSnapshot = snap
        self.reloadLocalStores()
      }
    }

    supervisionTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { break }
        let snap = await self.supervisor.reconcileOnce()
        self.bridgeSnapshot = snap
        self.isBridgePaused = await self.supervisor.isPaused()
        self.reloadLocalStores()
        let interval = max(5, self.config.preferences.healthCheckIntervalSeconds)
        try? await Task.sleep(for: .seconds(interval))
      }
    }
  }

  public func shutdownBridge() async {
    supervisionTask?.cancel()
    eventTask?.cancel()
    await supervisor.stop()
  }

  public func reloadLocalStores() {
    if let loaded = try? configStore.load() {
      config = loaded
    }
    recentReceipts = (try? receiptStore.listRecent(limit: 20)) ?? []
    launchAtLoginStatus = launchAtLoginManager.currentStatus()
  }

  public func refreshReadiness() async {
    isBusy = true
    errorBanner = nil
    defer { isBusy = false }
    do {
      bridgeSnapshot = await supervisor.reconcileOnce()
      readiness = try await coordinator.checkReadiness()
      reloadLocalStores()
      statusBanner =
        readiness?.ready == true
        ? "Device is unlocked and ready for deployment."
        : "Readiness check completed with blockers."
    } catch {
      errorBanner = error.localizedDescription
    }
  }

  public func toggleBridgePaused() async {
    isBusy = true
    defer { isBusy = false }
    let pausedNow = await supervisor.isPaused()
    bridgeSnapshot = await supervisor.setPaused(!pausedNow)
    isBridgePaused = await supervisor.isPaused()
    statusBanner = isBridgePaused ? "Wireless bridge paused." : "Wireless bridge resumed."
  }

  public func scanSetupDevices() async {
    isBusy = true
    errorBanner = nil
    defer { isBusy = false }
    do {
      let all = try await coordinator.listDevices(includeIneligible: true)
      setupDevices = all.filter(\.isEligibleForDebagr)
      setupIneligibleDevices = all.filter { !$0.isEligibleForDebagr }
    } catch {
      errorBanner = error.localizedDescription
    }
  }

  public func scanVPNPeers(provider: VPNProvider) async {
    isBusy = true
    defer { isBusy = false }
    vpnEnvironment = await vpnDiscovery.discoverPeers(provider: provider)
  }

  public func scanLocalWirelessIdentities() async {
    isBusy = true
    errorBanner = nil
    defer { isBusy = false }
    do {
      localWirelessCandidates = try await supervisor.discoverLocalWirelessCandidates(
        timeoutSeconds: 3.0
      )
      if localWirelessCandidates.isEmpty {
        statusBanner =
          "No local _apple-mobdev2._tcp ads found right now. Ensure Wi-Fi is on and the device is unlocked nearby."
      }
    } catch {
      errorBanner = error.localizedDescription
    }
  }

  public func verifyAndSaveProfile(
    device: PhysicalDevice,
    vpnProvider: VPNProvider,
    vpnAddress: String,
    peerName: String?,
    tailscaleNodeID: String?,
    lockdownPort: UInt16,
    bonjourRecord: BonjourServiceRecord
  ) async -> Bool {
    isBusy = true
    errorBanner = nil
    defer { isBusy = false }
    do {
      let result = try await supervisor.verifyAndBuildProfile(
        device: device,
        vpnProvider: vpnProvider,
        vpnAddress: vpnAddress,
        peerName: peerName,
        tailscaleNodeID: tailscaleNodeID,
        lockdownPort: lockdownPort,
        bonjourRecord: bonjourRecord
      )
      _ = try configStore.update { cfg in
        cfg.managedDevice = result.profile
      }
      pendingHandoffDevice = nil
      reloadLocalStores()
      bridgeSnapshot = await supervisor.reconcileOnce()
      readiness = try? await coordinator.checkReadiness()
      statusBanner = result.notes.joined(separator: " ")
      selectedSection = .overview
      return true
    } catch {
      errorBanner = error.localizedDescription
      return false
    }
  }

  public func forgetManagedDevice() async {
    isBusy = true
    defer { isBusy = false }
    do {
      _ = try configStore.update { cfg in
        cfg.managedDevice = nil
      }
      readiness = nil
      bridgeSnapshot = await supervisor.reconcileOnce()
      reloadLocalStores()
      statusBanner = "Managed device removed from local configuration."
      selectedSection = .wirelessSetup
    } catch {
      errorBanner = error.localizedDescription
    }
  }

  public func copyRedactedDiagnostics() async {
    isBusy = true
    defer { isBusy = false }
    do {
      let report = try await coordinator.doctor(strictRedaction: true)
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(report)
      copyToPasteboard(String(decoding: data, as: UTF8.self))
      statusBanner = "Copied redacted diagnostics JSON (pairing metadata stripped)."
    } catch {
      errorBanner = error.localizedDescription
    }
  }

  public func copyToPasteboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
  }

  public func updatePreferences(_ mutate: @Sendable (inout DebagrPreferences) -> Void) {
    do {
      let updated = try configStore.update { cfg in
        mutate(&cfg.preferences)
      }
      config = updated
    } catch {
      errorBanner = error.localizedDescription
    }
  }

  public func setLaunchAtLogin(_ enabled: Bool) {
    do {
      launchAtLoginStatus = try launchAtLoginManager.setEnabled(enabled)
      updatePreferences { prefs in
        prefs.launchAtLoginRequested = enabled
      }
    } catch {
      errorBanner = error.localizedDescription
    }
  }

  // MARK: - Experimental USB/IP Actions

  public func checkUSBIPPrerequisites(customPath: String? = nil) async {
    usbipPrerequisites = await usbipCoordinator.checkPrerequisites(customBinaryPath: customPath)
    usbipPhase = await usbipCoordinator.phase
  }

  public func discoverUSBIPPeersOnDemand() async {
    isBusy = true
    defer { isBusy = false }
    usbipDiscoveredPeers = await usbipCoordinator.discoverPeersOnDemand()
  }

  public func startUSBIPRole(role: USBIPRole) async {
    let (_, sas) = await usbipCoordinator.beginSession(role: role)
    usbipSessionID = await usbipCoordinator.sessionID
    usbipGeneratedSAS = sas
    usbipPhase = await usbipCoordinator.phase
  }

  public func handoffUSBIPToWirelessSetup(device: PhysicalDevice) {
    pendingHandoffDevice = device
    setupDevices = [device]
    selectedSection = .wirelessSetup
    statusBanner =
      "Apple pairing confirmed. Complete Wireless Setup to save VPN and Bonjour identity."
  }
}
