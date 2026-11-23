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

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .overview: "Overview"
    case .wirelessSetup: "Wireless Setup"
    case .agentOnboarding: "Agent & SSH"
    case .experimental: "Experimental"
    }
  }

  public var systemImage: String {
    switch self {
    case .overview: "antenna.radiowaves.left.and.right"
    case .wirelessSetup: "iphone.radiowaves.left.and.right"
    case .agentOnboarding: "terminal"
    case .experimental: "flask"
    }
  }
}

public enum AgentClientKind: String, CaseIterable, Identifiable, Sendable {
  case sshCLI = "SSH CLI"
  case claudeCode = "Claude Code"
  case codex = "Codex"

  public var id: String { rawValue }
}

public enum SSHDeployMode: String, CaseIterable, Identifiable, Sendable {
  case deployAndLaunch = "Deploy & Launch"
  case installOnly = "Install Only"

  public var id: String { rawValue }

  public var flagSuffix: String {
    switch self {
    case .deployAndLaunch: "--terminate-existing"
    case .installOnly: "--no-launch"
    }
  }

  public var commandContextTag: String {
    switch self {
    case .deployAndLaunch: "Run on Remote Machine (Install, Verify & Launch)"
    case .installOnly: "Run on Remote Machine (Install Only, Skip Launch)"
    }
  }
}

public struct AgentOnboardingDraft: Equatable {
  public var builderSSHHost: String
  public var builderAppPath: String
  public var selectedClient: AgentClientKind = .sshCLI
  public var sshDeployMode: SSHDeployMode = .deployAndLaunch

  public init(defaultHost: String) {
    self.builderSSHHost = defaultHost
    self.builderAppPath = "/Users/\(NSUserName())/Build/Products/Debug-iphoneos/MyApp.app"
  }
}

public struct ExperimentalDraft: Equatable {
  public var showCableBridge = false
  public var showUSBIP = false
  public var clientSSHHost = ""
  public var cablePort = "22078"
  public var selectedUSBIPRole: USBIPRole = .builder
  public var usbipCustomBinaryPath = ""
}

public enum WirelessSetupStep: Int, CaseIterable, Sendable {
  case pickDevice = 1
  case chooseVPN = 2
  case captureIdentity = 3
  case review = 4
  case completed = 5

  public var title: String {
    switch self {
    case .pickDevice: "Paired Device"
    case .chooseVPN: "Private VPN"
    case .captureIdentity: "Wireless ID"
    case .review: "Confirm"
    case .completed: "Saved"
    }
  }
}

public struct WirelessSetupDraft: Equatable {
  public var step: WirelessSetupStep = .pickDevice
  public var selectedDeviceID: String?
  public var selectedVPNProvider: VPNProvider = .tailscale
  public var manualVPNAddress = ""
  public var selectedPeerName: String?
  public var selectedPeerMatchedIP: String?
  public var selectedTailscaleNodeID: String?
  public var lockdownPortString = "62078"
  public var selectedBonjourID: String?
  public var confirmedDeviceID: String?
  public var confirmedBonjourID: String?
  public var savedProfile: ManagedDeviceProfile?
  public var savedNotes: [String] = []

  public var isHardwareConfirmedForSelection: Bool {
    guard let selectedDeviceID, let selectedBonjourID else { return false }
    return confirmedDeviceID == selectedDeviceID && confirmedBonjourID == selectedBonjourID
  }

  public mutating func selectDevice(_ id: String?) {
    if selectedDeviceID != id {
      selectedDeviceID = id
      confirmedDeviceID = nil
      confirmedBonjourID = nil
    }
  }

  public mutating func selectBonjour(_ id: String?) {
    if selectedBonjourID != id {
      selectedBonjourID = id
      confirmedDeviceID = nil
      confirmedBonjourID = nil
    }
  }

  public mutating func setHardwareConfirmed(_ confirmed: Bool) {
    if confirmed, let selectedDeviceID, let selectedBonjourID {
      confirmedDeviceID = selectedDeviceID
      confirmedBonjourID = selectedBonjourID
    } else {
      confirmedDeviceID = nil
      confirmedBonjourID = nil
    }
  }

  public mutating func applyDiscoveredPeer(_ peer: VPNPeer) {
    guard let ip = peer.preferredPrivateIP else { return }
    manualVPNAddress = ip
    selectedPeerName = peer.name
    selectedPeerMatchedIP = ip
    selectedTailscaleNodeID = peer.id
  }

  public mutating func updateManualAddress(_ next: String) {
    manualVPNAddress = next
    if next.trimmingCharacters(in: .whitespacesAndNewlines) != selectedPeerMatchedIP {
      selectedPeerName = nil
      selectedPeerMatchedIP = nil
      selectedTailscaleNodeID = nil
    }
  }

  public mutating func resetForNewSetup() {
    self = WirelessSetupDraft()
  }
}

@MainActor
public final class AppModel: ObservableObject {
  private static let cachedDefaultSSHHost = "\(NSUserName())@\(ProcessInfo.processInfo.hostName)"

  @Published public var selectedSection: SidebarDestination = .overview
  @Published public var config: DebagrConfig = DebagrConfig()
  @Published public var bridgeSnapshot = BridgeStateSnapshot(
    state: .unconfigured,
    lastTransitionReason: "Initializing bridge..."
  )
  @Published public var readiness: ReadinessReport?
  @Published public var lastReadinessCheckedAt: Date?
  @Published public var recentReceipts: [DeploymentReceipt] = []
  @Published public var isBridgePaused = false

  // Granular loading flags
  @Published public var isCheckingReadiness = false
  @Published public var isScanningDevices = false
  @Published public var isScanningVPN = false
  @Published public var isScanningBonjour = false
  @Published public var isSavingProfile = false
  @Published public var isRunningOnboardingTest = false
  @Published public var isScanningUSBIPPeers = false
  @Published public var isLoadingDiagnostics = false

  // Feedback surfaces
  @Published public var toastMessage: String?
  @Published public var errorBanner: String?
  @Published public var settingsErrorBanner: String?
  @Published public var launchAtLoginStatus: LaunchAtLoginStatus = .disabled

  // Persistent Drafts & Diagnostics
  @Published public var setupDraft = WirelessSetupDraft()
  @Published public var agentDraft = AgentOnboardingDraft(defaultHost: cachedDefaultSSHHost)
  @Published public var experimentalDraft = ExperimentalDraft()

  @Published public var setupDevices: [PhysicalDevice] = []
  @Published public var setupIneligibleDevices: [PhysicalDevice] = []
  @Published public var vpnEnvironment: VPNEnvironmentStatus?
  @Published public var localWirelessCandidates: [BonjourServiceRecord] = []

  @Published public var redactedDiagnosticsPreview: String?
  @Published public var redactedDiagnosticsError: String?

  @Published public var onboardingTestJSON: String?
  @Published public var onboardingTestReady: Bool?
  @Published public var onboardingTestError: String?

  // Experimental USB/IP State
  @Published public var usbipPrerequisites: USBIPToolPrerequisites?
  @Published public var usbipDiscoveredPeers: [DiscoveredUSBIPPeer] = []
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
  private var toastDismissTask: Task<Void, Never>?
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

  public var verdict: DeviceStatusVerdict {
    DeviceStatusVerdict.resolve(
      config: config,
      snapshot: bridgeSnapshot,
      readiness: readiness,
      isChecking: isCheckingReadiness
    )
  }

  public var binaryPathForAgents: String {
    Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? "debagr"
  }

  public var storagePermissionsOK: Bool {
    configStore.verifyPermissions()
      && receiptStore.verifyPermissions()
      && bridgeStateStore.verifyPermissions()
  }

  public func startBackgroundSupervision() {
    guard supervisionTask == nil else { return }

    eventTask = Task { [weak self] in
      guard let self else { return }
      for await event in self.systemMonitor.events() {
        if Task.isCancelled { break }
        let snap = await self.supervisor.handleSystemEvent(event)
        self.applyBridgeSnapshot(snap)
        self.reloadLocalStores()
      }
    }

    supervisionTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { break }
        let previousState = self.bridgeSnapshot.state
        let snap = await self.supervisor.reconcileOnce()
        self.applyBridgeSnapshot(snap)
        self.isBridgePaused = await self.supervisor.isPaused()
        self.reloadLocalStores()
        if previousState != snap.state,
          snap.state == .bridgingActive || snap.state == .nativeLocalStandby,
          self.config.managedDevice != nil
        {
          if let latest = try? await self.coordinator.checkReadiness() {
            self.readiness = latest
            self.lastReadinessCheckedAt = Date()
          }
        }
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

  public func showToast(_ message: String) {
    toastDismissTask?.cancel()
    toastMessage = message
    toastDismissTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(3.5))
      guard !Task.isCancelled else { return }
      self?.toastMessage = nil
    }
  }

  public func navigate(to destination: SidebarDestination) {
    selectedSection = destination
  }

  public func refreshReadiness(announce: Bool = true) async {
    guard !isCheckingReadiness else { return }
    isCheckingReadiness = true
    errorBanner = nil
    defer { isCheckingReadiness = false }
    do {
      let snap = await supervisor.reconcileOnce()
      applyBridgeSnapshot(snap)
      let report = try await coordinator.checkReadiness()
      readiness = report
      lastReadinessCheckedAt = Date()
      reloadLocalStores()

      if announce {
        let spoken =
          report.ready
          ? "Device is unlocked and ready for deployment."
          : (report.blockers.first?.message ?? "Readiness check found blockers.")
        NSAccessibility.post(
          element: NSApp as Any,
          notification: .announcementRequested,
          userInfo: [
            .announcement: spoken, .priority: NSAccessibilityPriorityLevel.medium.rawValue,
          ]
        )
        if report.ready {
          showToast("Ready to deploy to \(report.deviceName ?? "device").")
        }
      }
    } catch {
      readiness = nil
      lastReadinessCheckedAt = nil
      errorBanner = error.localizedDescription
    }
  }

  public func toggleBridgePaused() async {
    errorBanner = nil
    let pausedNow = await supervisor.isPaused()
    let snap = await supervisor.setPaused(!pausedNow)
    isBridgePaused = await supervisor.isPaused()
    applyBridgeSnapshot(snap)
    if isBridgePaused {
      readiness = nil
      lastReadinessCheckedAt = nil
    }
    showToast(isBridgePaused ? "Wireless bridge paused." : "Wireless bridge resumed.")
  }

  public func scanSetupDevices() async {
    isScanningDevices = true
    errorBanner = nil
    defer { isScanningDevices = false }
    do {
      let all = try await coordinator.listDevices(includeIneligible: true)
      setupDevices = all.filter(\.isEligibleForDebagr)
      setupIneligibleDevices = all.filter { !$0.isEligibleForDebagr }
      if let selected = setupDraft.selectedDeviceID,
        !setupDevices.contains(where: { ($0.udid ?? $0.coreDeviceID) == selected })
      {
        setupDraft.selectDevice(nil)
      }
    } catch {
      errorBanner = error.localizedDescription
    }
  }

  public func scanVPNPeers(provider: VPNProvider) async {
    isScanningVPN = true
    defer { isScanningVPN = false }
    vpnEnvironment = await vpnDiscovery.discoverPeers(provider: provider)
  }

  public func scanLocalWirelessIdentities() async {
    isScanningBonjour = true
    errorBanner = nil
    defer { isScanningBonjour = false }
    do {
      localWirelessCandidates = try await supervisor.discoverLocalWirelessCandidates(
        timeoutSeconds: 3.0
      )
      if let selected = setupDraft.selectedBonjourID,
        !localWirelessCandidates.contains(where: { $0.id == selected })
      {
        setupDraft.selectBonjour(nil)
      }
    } catch {
      errorBanner = error.localizedDescription
    }
  }

  public func verifyAndSaveSetupDraft(
    device: PhysicalDevice,
    bonjourRecord: BonjourServiceRecord
  ) async {
    guard let port = DebagrFormatters.parseTCPPort(setupDraft.lockdownPortString) else {
      errorBanner = "Invalid lockdown port."
      return
    }
    isSavingProfile = true
    errorBanner = nil
    defer { isSavingProfile = false }
    do {
      let result = try await supervisor.verifyAndBuildProfile(
        device: device,
        vpnProvider: setupDraft.selectedVPNProvider,
        vpnAddress: setupDraft.manualVPNAddress,
        peerName: setupDraft.selectedPeerName,
        tailscaleNodeID: setupDraft.selectedTailscaleNodeID,
        lockdownPort: port,
        bonjourRecord: bonjourRecord
      )
      _ = try configStore.update { cfg in
        cfg.managedDevice = result.profile
      }
      reloadLocalStores()
      let snap = await supervisor.reconcileOnce()
      applyBridgeSnapshot(snap)
      if let report = try? await coordinator.checkReadiness() {
        readiness = report
        lastReadinessCheckedAt = Date()
      } else {
        readiness = nil
        lastReadinessCheckedAt = nil
      }
      setupDraft.savedProfile = result.profile
      setupDraft.savedNotes = result.notes
      setupDraft.step = .completed
      showToast("Saved \(result.profile.displayName) wireless profile.")
    } catch {
      errorBanner = error.localizedDescription
    }
  }

  public func forgetManagedDevice() async {
    errorBanner = nil
    do {
      _ = try configStore.update { cfg in
        cfg.managedDevice = nil
      }
      readiness = nil
      lastReadinessCheckedAt = nil
      let snap = await supervisor.reconcileOnce()
      applyBridgeSnapshot(snap)
      reloadLocalStores()
      setupDraft.resetForNewSetup()
      selectedSection = .wirelessSetup
      showToast("Managed device removed from local Debagr config.")
    } catch {
      errorBanner = error.localizedDescription
    }
  }

  @discardableResult
  public func loadRedactedDiagnosticsPreview() async -> Bool {
    isLoadingDiagnostics = true
    redactedDiagnosticsPreview = nil
    redactedDiagnosticsError = nil
    defer { isLoadingDiagnostics = false }
    do {
      let report = try await coordinator.doctor(strictRedaction: true)
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(report)
      redactedDiagnosticsPreview = String(decoding: data, as: UTF8.self)
      return true
    } catch {
      redactedDiagnosticsError = error.localizedDescription
      errorBanner = error.localizedDescription
      return false
    }
  }

  @discardableResult
  public func copyRedactedDiagnostics() async -> Bool {
    let loaded = await loadRedactedDiagnosticsPreview()
    guard loaded, let json = redactedDiagnosticsPreview else {
      return false
    }
    copyToPasteboard(json)
    showToast("Copied redacted diagnostics JSON (pairing secrets stripped).")
    return true
  }

  public func runOnboardingReadinessTest() async {
    isRunningOnboardingTest = true
    onboardingTestJSON = nil
    onboardingTestReady = nil
    onboardingTestError = nil
    errorBanner = nil
    defer { isRunningOnboardingTest = false }
    do {
      let report = try await coordinator.checkReadiness()
      readiness = report
      lastReadinessCheckedAt = Date()
      onboardingTestReady = report.ready
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(report)
      onboardingTestJSON = String(decoding: data, as: UTF8.self)
    } catch {
      onboardingTestReady = false
      onboardingTestError = error.localizedDescription
    }
  }

  public func copyToPasteboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
  }

  public func updatePreferences(_ mutate: @Sendable (inout DebagrPreferences) -> Void) {
    do {
      let updated = try configStore.update { cfg in
        mutate(&cfg.preferences)
      }
      config = updated
      settingsErrorBanner = nil
    } catch {
      settingsErrorBanner = error.localizedDescription
      errorBanner = error.localizedDescription
    }
  }

  public func setLaunchAtLogin(_ enabled: Bool) {
    do {
      launchAtLoginStatus = try launchAtLoginManager.setEnabled(enabled)
      settingsErrorBanner = nil
      updatePreferences { prefs in
        prefs.launchAtLoginRequested = enabled
      }
    } catch {
      launchAtLoginStatus = launchAtLoginManager.currentStatus()
      settingsErrorBanner = error.localizedDescription
      errorBanner = error.localizedDescription
    }
  }

  public func fixStoragePermissions() {
    do {
      try FileSecurity.ensureSecureDirectory(FileSecurity.dataDirectoryURL())
      if FileManager.default.fileExists(atPath: configStore.fileURL.path) {
        try configStore.save(config)
      }
      if FileManager.default.fileExists(atPath: receiptStore.fileURL.path) {
        _ = chmod(receiptStore.fileURL.path, mode_t(FileSecurity.filePermissions))
      }
      if let snap = try bridgeStateStore.load() {
        try bridgeStateStore.save(snap)
      }
      settingsErrorBanner = nil
      objectWillChange.send()
      showToast("Restored 0700/0600 permissions on Debagr storage files.")
    } catch {
      settingsErrorBanner = error.localizedDescription
      errorBanner = error.localizedDescription
    }
  }

  public func revealInFinder(_ url: URL) {
    if FileManager.default.fileExists(atPath: url.path) {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
      NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
    }
  }

  public func resetAgentSSHHostToDefault() {
    agentDraft.builderSSHHost = Self.cachedDefaultSSHHost
  }

  // MARK: - Experimental Helpers

  public func checkUSBIPPrerequisites(customPath: String? = nil) async {
    usbipPrerequisites = await usbipCoordinator.checkPrerequisites(customBinaryPath: customPath)
  }

  public func discoverUSBIPPeersOnDemand() async {
    isScanningUSBIPPeers = true
    defer { isScanningUSBIPPeers = false }
    usbipDiscoveredPeers = await usbipCoordinator.discoverPeersOnDemand()
  }

  public func checkNewlyPairedDeviceForHandoff() async {
    isScanningDevices = true
    errorBanner = nil
    defer { isScanningDevices = false }
    do {
      let paired = try await coordinator.listDevices(includeIneligible: false)
      if let candidate = paired.first {
        usbipHandoff = WirelessHandoffPayload(pairedDevice: candidate)
        showToast("Found paired device '\(candidate.name)' ready for Wireless Setup.")
      } else {
        usbipHandoff = nil
        showToast("No paired physical iPhone or iPad found yet.")
      }
    } catch {
      errorBanner = error.localizedDescription
    }
  }

  public func handoffUSBIPToWirelessSetup(device: PhysicalDevice) {
    setupDraft.resetForNewSetup()
    setupDraft.selectDevice(device.udid ?? device.coreDeviceID)
    setupDevices = [device]
    selectedSection = .wirelessSetup
    showToast("Selected '\(device.name)' — choose its private VPN next.")
  }

  private func applyBridgeSnapshot(_ next: BridgeStateSnapshot) {
    bridgeSnapshot = next
    switch next.state {
    case .unconfigured, .paused, .deviceOffline, .vpnUnavailable, .error:
      readiness = nil
      lastReadinessCheckedAt = nil
    case .nativeLocalStandby, .bridgingActive, .probingVPN:
      break
    }
  }
}
