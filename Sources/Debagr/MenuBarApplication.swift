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
  private var toolsAvailable: Bool?
  private var checksMenu: NSMenu?
  private var terminating = false
  private var statusItem: NSStatusItem?
  private var statusMenu: NSMenu?
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
  private var managedRefreshPending = false
  private var managedStatusItem: NSMenuItem?
  private var managedToggleItem: NSMenuItem?
  private var lastDeploymentItem: NSMenuItem?
  private var setupWindowController: DeviceSetupWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let mainMenu = NSMenu()
    let appMenu = NSMenu()
    let appItem = NSMenuItem()
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)
    appMenu.addItem(
      withTitle: "Quit Debagr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let edit = NSMenu()
    for (title, action, key) in [
      ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
      ("Select All", "selectAll:", "a"),
    ] {
      edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
    }
    let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    editItem.submenu = edit
    mainMenu.addItem(editItem)
    let windowMenu = NSMenu()
    windowMenu.addItem(
      withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
    windowItem.submenu = windowMenu
    mainMenu.addItem(windowItem)
    application.mainMenu = mainMenu

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "antenna.radiowaves.left.and.right",
      accessibilityDescription: "Debagr"
    )
    statusItem.button?.toolTip = "Debagr · Remote app deployment"

    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.delegate = self
    menu.minimumWidth = 300
    menu.addItem(brandHeader())
    menu.addItem(.separator())
    let statusMenuItem = NSMenuItem(title: state.statusTitle, action: nil, keyEquivalent: "")
    statusMenuItem.isEnabled = false

    menu.addItem(sectionHeader("Remote deployment"))
    let managedStatus = NSMenuItem(
      title: "Remote deployment: checking…", action: nil, keyEquivalent: "")
    managedStatus.isEnabled = false
    menu.addItem(managedStatus)
    managedStatusItem = managedStatus
    let configure = NSMenuItem(
      title: "Set Up Remote Device…", action: #selector(configureRemoteDevice), keyEquivalent: ""
    )
    configure.target = self
    configure.image = menuImage("slider.horizontal.3")
    menu.addItem(configure)
    let toggle = NSMenuItem(
      title: "Connect Remote Device", action: #selector(toggleRemoteDevice), keyEquivalent: "")
    toggle.target = self
    toggle.image = menuImage("link")
    menu.addItem(toggle)
    managedToggleItem = toggle
    let history = NSMenuItem(title: "No deployment recorded", action: nil, keyEquivalent: "")
    history.isEnabled = false
    menu.addItem(history)
    lastDeploymentItem = history
    let skill = NSMenuItem(
      title: "Show AI Deployment Skill…", action: #selector(showDeploymentSkill), keyEquivalent: "")
    skill.target = self
    skill.image = menuImage("sparkles")
    menu.addItem(skill)
    menu.addItem(.separator())

    menu.addItem(sectionHeader("Devices"))
    menu.addItem(statusMenuItem)
    let refreshMenuItem = NSMenuItem(
      title: "Refresh Target Devices",
      action: #selector(refreshDevices),
      keyEquivalent: "r"
    )
    refreshMenuItem.target = self
    refreshMenuItem.image = menuImage("arrow.clockwise")
    menu.addItem(refreshMenuItem)

    menu.addItem(.separator())
    let helpMenu = NSMenu()
    let helpItem = NSMenuItem(title: "Help & Diagnostics", action: nil, keyEquivalent: "")
    helpItem.image = menuImage("questionmark.circle")
    helpItem.submenu = helpMenu
    menu.addItem(helpItem)
    let gettingStartedMenuItem = NSMenuItem(
      title: "Agent Tools & Setup Guide…",
      action: #selector(showGettingStarted),
      keyEquivalent: ""
    )
    gettingStartedMenuItem.target = self
    gettingStartedMenuItem.image = menuImage("book.closed")
    helpMenu.addItem(gettingStartedMenuItem)

    let systemCheckMenuItem = NSMenuItem(title: "System Check", action: nil, keyEquivalent: "")
    let checks = systemCheckMenu()
    checks.delegate = self
    checksMenu = checks
    systemCheckMenuItem.submenu = checks
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

    statusItem.menu = menu
    self.statusItem = statusItem
    self.statusMenu = menu
    self.statusMenuItem = statusMenuItem
    self.refreshMenuItem = refreshMenuItem
    self.launchAtLoginMenuItem = launchAtLoginMenuItem

    refreshSystemCheck()
    render()
    startDiscovery()
    showWelcomeIfNeeded()
    refreshManagedDevice()
    managedTimer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
      self?.refreshManagedDevice()
    }
    if let managedTimer { RunLoop.main.add(managedTimer, forMode: .common) }
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
  }

  @objc private func didWake() {
    refreshManagedDevice()
    startDiscovery()
  }

  func menuWillOpen(_ menu: NSMenu) {
    refreshSystemCheck()
    launchAtLoginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    refreshManagedDevice()
  }

  private func brandHeader() -> NSMenuItem {
    let icon = NSImageView(image: NSImage(named: NSImage.applicationIconName) ?? NSImage())
    icon.imageScaling = .scaleProportionallyUpOrDown
    icon.setAccessibilityLabel("Debagr")
    let title = NSTextField(labelWithString: "Debagr")
    title.font = .systemFont(ofSize: 16, weight: .semibold)
    let subtitle = NSTextField(labelWithString: "Your Mac stays home. Your build comes with you.")
    subtitle.font = .systemFont(ofSize: 11)
    subtitle.textColor = .secondaryLabelColor
    let version = NSTextField(labelWithString: "Version \(ProductSupport.version)")
    version.font = .systemFont(ofSize: 10)
    version.textColor = .secondaryLabelColor
    let labels = NSStackView(views: [title, subtitle, version])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 3
    let content = NSStackView(views: [icon, labels])
    content.alignment = .centerY
    content.spacing = 12
    content.translatesAutoresizingMaskIntoConstraints = false
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 88))
    view.addSubview(content)
    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 40),
      icon.heightAnchor.constraint(equalToConstant: 40),
      content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      content.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
    let item = NSMenuItem()
    item.view = view
    return item
  }

  private func sectionHeader(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.attributedTitle = NSAttributedString(
      string: title,
      attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)])
    item.isEnabled = false
    return item
  }

  private func menuImage(_ symbol: String) -> NSImage? {
    NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
  }

  func applicationWillTerminate(_ notification: Notification) {
    capture.stop()
    managedTimer?.invalidate()
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminating else { return .terminateLater }
    terminating = true
    DeviceDeployer.cancelPendingCommands()
    managedTimer?.invalidate()
    managedQueue.async {
      self.managedRuntime.stop()
      // AppKit's nested deferred-quit loop must be able to deliver this completion.
      RunLoop.main.perform(inModes: [.common, .modalPanel]) {
        MainActor.assumeIsolated { sender.reply(toApplicationShouldTerminate: true) }
      }
    }
    return .terminateLater
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag { showGettingStarted() }
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
    let devices = registry.orderedDevices
    let managedTitle = managedStatusItem?.title ?? "unknown"
    let discovery = failureDetails
    DispatchQueue.global(qos: .utility).async { [self] in
      var report = ProductSupport.diagnostics(devices: devices)
      report += "\nRemote deployment: \(managedTitle)"
      if let discovery { report += "\nDiscovery: \(discovery)" }
      if let receipt = DeploymentReceipt.latest() {
        report +=
          "\nLast deployment: \(receipt.launched ? "installed and launched" : "installed") at \(receipt.completedAt.formatted())"
      }
      DispatchQueue.main.async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        self.statusMenuItem?.title = "Diagnostics copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
          self?.render()
        }
      }
    }
  }

  @objc private func copyDeployCommand(_ sender: NSMenuItem) {
    guard let identifier = sender.representedObject as? String else { return }
    let command = ProductSupport.deployCommand(deviceIdentifier: identifier)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(command, forType: .string)
    sender.title = "Deploy command copied"
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { sender.title = "Copy Deploy Command" }
  }

  @objc private func openSupport() {
    guard let url = ProductSupport.configuredURL(forInfoKey: "DebagrSupportURL") else { return }
    NSWorkspace.shared.open(url)
  }

  @objc private func toggleLaunchAtLogin() {
    do {
      if SMAppService.mainApp.status == .enabled {
        try SMAppService.mainApp.unregister()
      } else {
        try SMAppService.mainApp.register()
      }
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
      self?.showGettingStarted()
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
      registry.orderedDevices, services: bonjourServices,
      status: failureDetails ?? state.statusTitle)
    statusMenuItem?.title = state.statusTitle
    statusMenuItem?.toolTip = failureDetails
    refreshMenuItem?.isEnabled = state != .discovering
    statusItem?.button?.setAccessibilityLabel(state.accessibilityLabel)

    guard let menu = statusMenu, let refreshMenuItem else { return }
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
    menu.autoenablesItems = false
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

  private func refreshSystemCheck() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let available = ProductSupport.developerToolsAvailable
      DispatchQueue.main.async {
        guard let self else { return }
        self.toolsAvailable = available
        let items = self.systemCheckMenu().items
        self.checksMenu?.removeAllItems()
        for item in items {
          item.menu?.removeItem(item)
          self.checksMenu?.addItem(item)
        }
        self.setupWindowController?.model.developerToolsAvailable = available
      }
    }
  }

  private func systemCheckMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    let checks = [
      toolsAvailable.map { $0 ? "Developer tools available" : "Developer tools not detected" }
        ?? "Checking developer tools…",
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
    guard !terminating else { return }
    guard !managedBusy else {
      managedRefreshPending = true
      return
    }
    managedBusy = true
    managedQueue.async { [weak self] in
      guard let self else { return }
      let result = Result { try self.managedRuntime.refresh() }
      let configured = try? self.managedRuntime.store.load()
      let receipt = DeploymentReceipt.latest()
      DispatchQueue.main.async {
        self.managedBusy = false
        switch result {
        case .success(let title):
          self.managedStatusItem?.title = title
          self.managedStatusItem?.toolTip = nil
        case .failure(let error):
          switch error {
          case DeviceDeploymentError.deviceLocked:
            self.managedStatusItem?.title = "\(configured?.displayName ?? "Device") is locked"
          case is ProfileError, is CLIError, is DecodingError:
            self.managedStatusItem?.title = "Saved setup is invalid — set up again"
          case is ManagedDeviceError:
            self.managedStatusItem?.title = "Another Debagr relay is running"
          case is NetworkSupportError:
            self.managedStatusItem?.title = "This Mac needs Wi-Fi or Ethernet"
          default:
            self.managedStatusItem?.title = error.localizedDescription
          }
          self.managedStatusItem?.toolTip =
            "\(error.localizedDescription)\nKeep the device unlocked on Wi-Fi with its VPN connected. Check saved setup in Settings; grant USB trust again if needed."
        }
        self.setupWindowController?.model.connectionStatus =
          self.managedStatusItem?.title ?? "Checking connection…"
        self.statusItem?.button?.image = NSImage(
          systemSymbolName: (try? result.get())?.contains("Ready") == true
            ? "checkmark.circle" : "antenna.radiowaves.left.and.right",
          accessibilityDescription: self.managedStatusItem?.title)
        if self.managedRefreshPending {
          self.managedRefreshPending = false
          self.refreshManagedDevice()
        }
        self.managedToggleItem?.isEnabled = configured != nil && !self.managedBusy
        self.managedToggleItem?.title =
          configured?.enabled == true ? "Disconnect Remote Device" : "Connect Remote Device"
        self.managedToggleItem?.image = self.menuImage(
          configured?.enabled == true ? "link.circle.fill" : "link")
        if let receipt {
          self.lastDeploymentItem?.title =
            "Last deployment: \(receipt.launched ? "installed and launched" : "installed")"
          self.lastDeploymentItem?.toolTip =
            "\(receipt.bundleIdentifier)\n\(receipt.deviceIdentifier)\n\(receipt.completedAt.formatted())"
        }
      }
    }
  }

  @objc private func toggleRemoteDevice() {
    do {
      let store = ManagedDeviceStore()
      try store.toggleEnabled()
      managedStatusItem?.title = "Updating connection…"
      managedToggleItem?.isEnabled = false
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
    presentSetup(page: .setup)
  }

  private func presentSetup(page: DeviceSetupModel.Page) {
    if setupWindowController == nil {
      let controller = DeviceSetupWindowController(configured: try? managedRuntime.store.load())
      controller.model.onRefresh = { [weak self] in self?.startDiscovery() }
      controller.model.onSaved = { [weak self] in self?.refreshManagedDevice() }
      controller.model.onShowSkill = { [weak self] in self?.showDeploymentSkill() }
      setupWindowController = controller
    }
    setupWindowController?.model.updateDevices(
      registry.orderedDevices, services: bonjourServices,
      status: failureDetails ?? state.statusTitle)
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
    RunLoop.main.perform(inModes: [.common, .modalPanel]) {
      MainActor.assumeIsolated { application.terminate(nil) }
    }
  }
  application.run()
  signals.stop()
}
