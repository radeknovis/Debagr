import AppKit
import Foundation
import ServiceManagement

enum MenuBarViewState: Equatable {
  case discovering
  case empty
  case loaded([TargetDevice])
  case failed(String)

  var statusTitle: String {
    switch self {
    case .discovering:
      return "Looking for Target Devices…"
    case .empty:
      return "No Target Devices found"
    case .loaded(let devices):
      return "\(devices.count) Target Device\(devices.count == 1 ? "" : "s") found"
    case .failed:
      return "Device discovery unavailable"
    }
  }

  var accessibilityLabel: String {
    if case .failed(let details) = self {
      return "Debagr. \(statusTitle). \(details)"
    }
    return "Debagr. \(statusTitle)"
  }
}

final class MenuBarApplication: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private static let initialDiscoveryWindow: TimeInterval = 5
  private static let didShowWelcomeKey = "didShowWelcome-v1"

  private let capture = BonjourCapture()
  private var statusItem: NSStatusItem?
  private var statusMenu: NSMenu?
  private var deviceListMenu: NSMenu?
  private let connectionSummary = MenuConnectionSummaryView()
  private var menuConfiguredDevice: ConfiguredDevice?
  private var menuReadiness = MenuReadiness.checking
  private var menuReceipt: DeploymentReceipt?
  private var openConnectionItem: NSMenuItem?
  private var copyPromptItem: NSMenuItem?
  private var statusMenuItem: NSMenuItem?
  private var refreshMenuItem: NSMenuItem?
  private var launchAtLoginMenuItem: NSMenuItem?
  private var deviceMenuItems: [NSMenuItem] = []
  private var registry = TargetDeviceRegistry()
  private var coreDevices: [TargetDevice] = []
  private var bonjourServices: [BonjourDevice] = []
  private var coreDiscoveryFinished = false
  private var bonjourDiscoveryFinished = false
  private var discoveryErrors: [String] = []
  private var state = MenuBarViewState.discovering
  private var discoveryGeneration = 0
  private let managedRuntime = ManagedDeviceRuntime()
  private let managedQueue = DispatchQueue(label: "debagr.managed-device")
  private var managedTimer: Timer?
  private var managedBusy = false
  private var managedToggleItem: NSMenuItem?
  private var setupWindowController: DeviceSetupWindowController?
  private let peerDiscovery = DebagrPeerDiscovery()
  private let usbipSession = USBIPSessionController()
  private var initialPairingCoordinator: InitialPairingCoordinator?

  @objc private func showUSBIPSetup() {
    if let model = setupWindowController?.model, model.isWorking || model.usb.hasSession {
      setupWindowController?.present(page: .setup)
      return
    }
    if initialPairingCoordinator == nil {
      let controller = InitialPairingCoordinator(
        embedded: true, discovery: peerDiscovery, session: usbipSession)
      controller.onWirelessSetup = { [weak self] in self?.configureRemoteDevice() }
      controller.onVirtualHereSetup = { [weak self] in self?.showVirtualHereSetup() }
      initialPairingCoordinator = controller
    }
    presentSetup(page: .setup)
    if let controller = initialPairingCoordinator, let setup = setupWindowController,
      let window = setup.window
    {
      let model = setup.model
      model.initialPairing = controller.activate(in: window)
      model.usesVirtualHere = false
      model.path = .usb
    }
  }

  private func showVirtualHereSetup() {
    guard !usbipSession.isRunning, !usbipSession.busy,
      initialPairingCoordinator?.canOpenOtherSetup != false
    else {
      showUSBIPSetup()
      return
    }
    presentSetup(page: .setup)
    setupWindowController?.model.usesVirtualHere = true
    setupWindowController?.model.path = .usb
  }

  @objc private func showConnectionSetup() {
    if (try? peerDiscovery.localSelection)?.role == .client
      || (try? managedRuntime.store.load()) == nil
    {
      showUSBIPSetup()
    } else {
      configureRemoteDevice()
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    peerDiscovery.start()

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = MenuBarIconState.idle.image
    statusItem.button?.toolTip = "Debagr · Remote app deployment"

    let menu = makeMenu()

    statusItem.menu = menu
    self.statusItem = statusItem

    render()
    startDiscovery()
    showWelcomeIfNeeded()
    refreshManagedDevice()
    managedTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
      self?.refreshManagedDevice()
    }
  }

  func makeMenu() -> NSMenu {
    let menu = NSMenu()
    menu.minimumWidth = 320
    menu.autoenablesItems = false
    menu.delegate = self
    let summary = NSMenuItem()
    summary.view = connectionSummary
    menu.addItem(summary)
    menu.addItem(.separator())
    let statusMenuItem = NSMenuItem(title: state.statusTitle, action: nil, keyEquivalent: "")
    statusMenuItem.isEnabled = false

    let connect = NSMenuItem(
      title: "Set Up Remote Device…", action: #selector(openDebagr), keyEquivalent: "")
    connect.target = self
    connect.image = menuImage("cable.connector")
    menu.addItem(connect)
    openConnectionItem = connect
    let prompt = NSMenuItem(
      title: "Copy Deployment Prompt", action: #selector(copyDeploymentPrompt), keyEquivalent: "")
    prompt.target = self
    prompt.image = menuImage("doc.on.doc")
    prompt.isEnabled = false
    menu.addItem(prompt)
    copyPromptItem = prompt
    let toggle = NSMenuItem(
      title: "Connect Remote Device", action: #selector(toggleRemoteDevice), keyEquivalent: "")
    toggle.target = self
    toggle.image = menuImage("link")
    menu.addItem(toggle)
    managedToggleItem = toggle
    let skill = NSMenuItem(
      title: "Show AI Deployment Skill…", action: #selector(showDeploymentSkill), keyEquivalent: "")
    skill.target = self
    skill.image = menuImage("sparkles")
    menu.addItem(.separator())

    let devices = NSMenu()
    devices.autoenablesItems = false
    let deviceItem = NSMenuItem(title: "Devices", action: nil, keyEquivalent: "")
    deviceItem.image = menuImage("iphone")
    deviceItem.submenu = devices
    menu.addItem(deviceItem)
    deviceListMenu = devices
    devices.addItem(statusMenuItem)
    let refreshMenuItem = NSMenuItem(
      title: "Refresh Target Devices",
      action: #selector(refreshDevices),
      keyEquivalent: "r"
    )
    refreshMenuItem.target = self
    refreshMenuItem.image = menuImage("arrow.clockwise")
    devices.addItem(refreshMenuItem)

    menu.addItem(.separator())
    let gettingStartedMenuItem = NSMenuItem(
      title: "Agent Tools & Setup Guide…",
      action: #selector(showGettingStarted),
      keyEquivalent: ""
    )
    gettingStartedMenuItem.target = self
    gettingStartedMenuItem.image = menuImage("book.closed")
    gettingStartedMenuItem.title = "Agent Tools…"
    menu.addItem(gettingStartedMenuItem)
    let helpMenu = NSMenu()
    let helpItem = NSMenuItem(title: "Help & Diagnostics", action: nil, keyEquivalent: "")
    helpItem.image = menuImage("questionmark.circle")
    helpItem.submenu = helpMenu
    menu.addItem(helpItem)
    helpMenu.addItem(skill)

    let systemCheckMenuItem = NSMenuItem(title: "System Check", action: nil, keyEquivalent: "")
    systemCheckMenuItem.submenu = systemCheckMenu()
    systemCheckMenuItem.image = menuImage("checkmark.shield")
    helpMenu.addItem(systemCheckMenuItem)

    let diagnosticsMenuItem = NSMenuItem(
      title: "Copy Diagnostics",
      action: #selector(copyDiagnostics),
      keyEquivalent: ""
    )
    diagnosticsMenuItem.target = self
    diagnosticsMenuItem.image = menuImage("doc.on.clipboard")
    helpMenu.addItem(diagnosticsMenuItem)

    if ProductSupport.configuredURL(forInfoKey: "DebagrSupportURL") != nil {
      let supportMenuItem = NSMenuItem(
        title: "Support…",
        action: #selector(openSupport),
        keyEquivalent: ""
      )
      supportMenuItem.target = self
      supportMenuItem.image = menuImage("bubble.left")
      helpMenu.addItem(supportMenuItem)
    }

    menu.addItem(.separator())
    let launchAtLoginMenuItem = NSMenuItem(
      title: "Launch at Login",
      action: #selector(toggleLaunchAtLogin),
      keyEquivalent: ""
    )
    launchAtLoginMenuItem.target = self
    launchAtLoginMenuItem.image = menuImage("power")
    launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    menu.addItem(launchAtLoginMenuItem)

    let aboutMenuItem = NSMenuItem(
      title: "About Debagr",
      action: #selector(showAbout),
      keyEquivalent: ""
    )
    aboutMenuItem.target = self
    aboutMenuItem.image = menuImage("info.circle")
    menu.addItem(aboutMenuItem)
    menu.addItem(.separator())

    let quitMenuItem = NSMenuItem(
      title: "Quit Debagr",
      action: #selector(quit),
      keyEquivalent: "q"
    )
    quitMenuItem.target = self
    menu.addItem(quitMenuItem)

    self.statusMenu = menu
    self.statusMenuItem = statusMenuItem
    self.refreshMenuItem = refreshMenuItem
    self.launchAtLoginMenuItem = launchAtLoginMenuItem
    updateMenuSummary()
    return menu
  }

  func menuWillOpen(_ menu: NSMenu) {
    launchAtLoginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    updateMenuSummary()
  }

  private func updateMenuSummary() {
    let selection = try? peerDiscovery.localSelection
    let presentation = MenuConnectionPresentation(
      configured: menuConfiguredDevice, selection: selection,
      usbActive: usbipSession.isRunning, readiness: menuReadiness, receipt: menuReceipt)
    connectionSummary.update(presentation)
    statusItem?.button?.image = presentation.iconState.image
    openConnectionItem?.title = presentation.actionTitle
    managedToggleItem?.isHidden = menuConfiguredDevice == nil || selection?.role == .client
    copyPromptItem?.isEnabled = menuConfiguredDevice != nil && selection?.role != .client
    statusItem?.button?.toolTip = "Debagr · \(presentation.title) · \(presentation.status)"
    statusItem?.button?.setAccessibilityLabel(
      "Debagr. \(presentation.title). \(presentation.status)")
  }

  @objc private func copyDeploymentPrompt() {
    guard let configured = menuConfiguredDevice else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      DeviceSetupModel(configured: configured).deploymentPrompt, forType: .string)
  }

  private func menuImage(_ symbol: String) -> NSImage? {
    NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
  }

  func applicationWillTerminate(_ notification: Notification) {
    setupWindowController?.model.usb.shutdown()
    peerDiscovery.stop()
    capture.stop()
    managedTimer?.invalidate()
    managedQueue.sync { managedRuntime.stop() }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showConnectionSetup()
    return true
  }

  @objc private func refreshDevices() {
    startDiscovery()
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  @objc private func showAbout() {
    NSApplication.shared.orderFrontStandardAboutPanel(options: [
      .applicationVersion: ProductSupport.version,
      .credits: NSAttributedString(
        string:
          "Your Mac stays home. Your next build comes with you.\n\nInstall and launch signed apps on your device across separate Wi-Fi networks, through its paired Mac and private VPN."
      ),
    ])
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  @objc private func showGettingStarted() {
    presentSetup(page: .guide)
  }

  @objc private func copyDiagnostics() {
    let report = ProductSupport.diagnostics(devices: registry.orderedDevices)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(report, forType: .string)
    statusMenuItem?.title = "Diagnostics copied"
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      self?.render()
    }
  }

  @objc private func copyDeployCommand(_ sender: NSMenuItem) {
    guard let identifier = sender.representedObject as? String else { return }
    let command =
      "'/Applications/Debagr.app/Contents/MacOS/Debagr' "
      + "--deploy-app '/path/to/App.app' --device '\(identifier)' --launch --json"
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(command, forType: .string)
  }

  @objc private func openSupport() {
    guard let url = ProductSupport.configuredURL(forInfoKey: "DebagrSupportURL") else { return }
    NSWorkspace.shared.open(url)
  }

  @objc private func openDebagr() {
    presentSetup(page: setupWindowController?.model.page ?? .setup)
  }

  @objc private func toggleLaunchAtLogin() {
    do {
      try LaunchAtLogin.setEnabled(SMAppService.mainApp.status != .enabled)
      launchAtLoginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    } catch {
      presentSetupError(error)
    }
  }

  private func showWelcomeIfNeeded() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: Self.didShowWelcomeKey) else { return }
    defaults.set(true, forKey: Self.didShowWelcomeKey)
    DispatchQueue.main.async { [weak self] in
      self?.showConnectionSetup()
    }
  }

  private func startDiscovery() {
    discoveryGeneration += 1
    let generation = discoveryGeneration
    registry = TargetDeviceRegistry()
    coreDevices = []
    bonjourServices = []
    coreDiscoveryFinished = false
    bonjourDiscoveryFinished = false
    discoveryErrors = []
    state = .discovering
    render()

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      let result = Result {
        try CoreDeviceInventory.load(pairedMacNodeID: self.localPairedMacIdentifier)
      }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.discoveryGeneration == generation else { return }
        self.coreDiscoveryFinished = true
        switch result {
        case .success(let devices):
          self.coreDevices = devices
        case .failure(let error):
          self.discoveryErrors.append(error.localizedDescription)
        }
        self.rebuildRegistry()
      }
    }

    do {
      try capture.startZoneCaptureAll(
        onFailure: { [weak self] error in
          DispatchQueue.main.async { [weak self] in
            guard self?.discoveryGeneration == generation else { return }
            self?.bonjourDiscoveryFinished = true
            self?.discoveryErrors.append(error.localizedDescription)
            self?.rebuildRegistry()
          }
        },
        onDevices: { [weak self] services in
          DispatchQueue.main.async { [weak self] in
            guard self?.discoveryGeneration == generation else { return }
            self?.bonjourDiscoveryFinished = true
            self?.bonjourServices = services
            self?.rebuildRegistry()
          }
        })
    } catch {
      bonjourDiscoveryFinished = true
      discoveryErrors.append(error.localizedDescription)
      rebuildRegistry()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialDiscoveryWindow) {
      [weak self] in
      guard let self, self.discoveryGeneration == generation else {
        return
      }
      self.bonjourDiscoveryFinished = true
      self.rebuildRegistry()
    }
  }

  private func rebuildRegistry() {
    var nextRegistry = TargetDeviceRegistry()
    for device in coreDevices {
      nextRegistry.merge(device)
    }
    for service in bonjourServices {
      nextRegistry.merge(
        TargetDevice(
          identity: .provisional(
            pairedMacNodeID: localPairedMacIdentifier,
            service: service
          ),
          displayName: service.suggestedDisplayName,
          kind: .inferred(from: service),
          service: service,
          status: .visible
        )
      )
    }
    registry = nextRegistry
    let devices = registry.orderedDevices
    if !devices.isEmpty {
      state = .loaded(devices)
    } else if coreDiscoveryFinished, bonjourDiscoveryFinished {
      state = discoveryErrors.isEmpty ? .empty : .failed(discoveryErrors.joined(separator: " "))
    } else {
      state = .discovering
    }
    render()
  }

  private func render() {
    setupWindowController?.model.updateDevices(
      registry.orderedDevices, services: bonjourServices, status: state.statusTitle)
    statusMenuItem?.title = state.statusTitle
    statusMenuItem?.toolTip = failureDetails
    refreshMenuItem?.isEnabled = state != .discovering
    updateMenuSummary()

    guard let menu = deviceListMenu, let refreshMenuItem else { return }
    deviceMenuItems.forEach(menu.removeItem)
    deviceMenuItems.removeAll()

    guard let refreshIndex = menu.items.firstIndex(where: { $0 === refreshMenuItem }) else {
      return
    }

    for device in registry.orderedDevices.reversed() {
      let item = NSMenuItem(title: device.displayName, action: nil, keyEquivalent: "")
      item.image = NSImage(
        systemSymbolName: symbolName(for: device.kind),
        accessibilityDescription: nil
      )
      item.submenu = detailsMenu(for: device)
      menu.insertItem(item, at: refreshIndex)
      deviceMenuItems.append(item)
    }
  }

  private func detailsMenu(for device: TargetDevice) -> NSMenu {
    let menu = NSMenu()
    let identifier = device.identity.value.replacingOccurrences(of: "bonjour:", with: "")
    let details: [String]
    if let service = device.service {
      details = [
        "Kind: \(device.kind.displayName)",
        "Status: \(device.status.displayName)",
        "Host: \(service.hostName)",
        "Port: \(service.port)",
        "Identifier: \(identifier)",
      ]
    } else {
      details = [
        "Kind: \(device.kind.displayName)",
        "Status: \(device.status.displayName)",
        "Identifier: \(identifier)",
      ]
    }
    for detail in details {
      let item = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    }
    if device.identity.source == .appleIdentifier {
      menu.addItem(.separator())
      let deployItem = NSMenuItem(
        title: "Copy Deploy Command",
        action: #selector(copyDeployCommand(_:)),
        keyEquivalent: ""
      )
      deployItem.target = self
      deployItem.representedObject = identifier
      menu.addItem(deployItem)
    }
    return menu
  }

  private func systemCheckMenu() -> NSMenu {
    let menu = NSMenu()
    let checks = [
      ProductSupport.developerToolsAvailable
        ? "Developer tools available" : "Developer tools not detected",
      ProductSupport.tailscaleExecutablePath != nil
        ? "Tailscale / Headscale client installed"
        : "Tailscale / Headscale client not installed; other VPNs can be used",
    ]
    for check in checks {
      let item = NSMenuItem(title: check, action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    }
    return menu
  }

  private func symbolName(for kind: TargetDeviceKind) -> String {
    switch kind {
    case .iPhone:
      return "iphone"
    case .iPad:
      return "ipad"
    case .unknown:
      return "questionmark.square.dashed"
    }
  }

  private var failureDetails: String? {
    guard case .failed(let details) = state else { return nil }
    return details
  }

  private var localPairedMacIdentifier: String {
    "local:\(ProcessInfo.processInfo.hostName)"
  }

  private func refreshManagedDevice() {
    guard !managedBusy else { return }
    managedBusy = true
    managedQueue.async { [weak self] in
      guard let self else { return }
      let previousConfiguration = try? self.managedRuntime.store.load()
      let result = Result { try self.managedRuntime.refresh() }
      let configured = try? self.managedRuntime.store.load()
      let receipt = DeploymentReceipt.latest()
      DispatchQueue.main.async {
        self.managedBusy = false
        if previousConfiguration?.hasSameConnection(as: configured) == true,
          previousConfiguration?.enabled == configured?.enabled
        {
          self.setupWindowController?.model.updateVerification(device: configured, result: result)
        }
        self.menuConfiguredDevice = configured
        self.menuReceipt = receipt
        if configured != nil
          && (previousConfiguration?.hasSameConnection(as: configured) != true
            || previousConfiguration?.enabled != configured?.enabled)
        {
          self.menuReadiness = .checking
        } else {
          switch result {
          case .success: self.menuReadiness = .ready
          case .failure(let error):
            let failure =
              AgentCLI.failure(error, operation: "status").object["error"] as? [String: Any]
            self.menuReadiness = .attention(
              failure?["recovery"] as? String ?? "Open Connections to check the device.")
          }
        }
        self.managedToggleItem?.isEnabled = configured != nil
        self.managedToggleItem?.title =
          configured?.enabled == true ? "Pause Wireless Connection" : "Resume Wireless Connection"
        self.managedToggleItem?.image = self.menuImage(
          configured?.enabled == true ? "link.circle.fill" : "link")
        self.updateMenuSummary()

      }
    }
  }

  @objc private func toggleRemoteDevice() {
    do {
      let store = ManagedDeviceStore()
      try store.toggleEnabled()
      refreshManagedDevice()
    } catch { presentSetupError(error) }
  }

  @objc private func showDeploymentSkill() {
    guard let resources = Bundle.main.resourceURL else { return }
    let url = resources.appendingPathComponent("Skills/debagr-deploy/SKILL.md")
    if FileManager.default.fileExists(atPath: url.path) {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
      presentSetup(page: .guide)
      setupWindowController?.model.error =
        "Build the app bundle to include the AI skill. The source skill is in Skills/debagr-deploy."
    }
  }

  @objc private func configureRemoteDevice() {
    guard (try? peerDiscovery.localSelection)?.role != .client,
      !usbipSession.isRunning, !usbipSession.busy,
      initialPairingCoordinator?.canOpenOtherSetup != false
    else {
      showUSBIPSetup()
      return
    }
    presentSetup(page: .setup)
    setupWindowController?.model.path = .existing
  }

  private func presentSetup(page: DeviceSetupModel.Page) {
    if setupWindowController == nil {
      let controller = DeviceSetupWindowController(configured: try? managedRuntime.store.load())
      controller.model.onRefresh = { [weak self] in self?.startDiscovery() }
      controller.model.onSaved = { [weak self] in self?.refreshManagedDevice() }
      controller.model.onExistingPairing = { [weak self] in self?.configureRemoteDevice() }
      controller.model.onInitialPairing = { [weak self] in self?.showUSBIPSetup() }
      controller.model.onCheckConnection = { [weak self] in self?.refreshManagedDevice() }
      controller.model.onShowSkill = { [weak self] in self?.showDeploymentSkill() }
      setupWindowController = controller
    }
    setupWindowController?.model.updateDevices(
      registry.orderedDevices, services: bonjourServices, status: state.statusTitle)
    setupWindowController?.present(page: page)
  }

  private func presentSetupError(_ error: Error) {
    presentSetup(page: .guide)
    setupWindowController?.model.error = error.localizedDescription
  }

}

func runMenuBarApplication() {
  let application = NSApplication.shared
  let delegate = MenuBarApplication()
  application.delegate = delegate
  let signals = SignalHandler {
    DispatchQueue.main.async { application.terminate(nil) }
  }
  application.run()
  signals.stop()
}
