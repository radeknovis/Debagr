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

final class MenuBarApplication: NSObject, NSApplicationDelegate {
  private static let initialDiscoveryWindow: TimeInterval = 5
  private static let didShowWelcomeKey = "didShowWelcome-v1"

  private let capture = BonjourCapture()
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

  func applicationDidFinishLaunching(_ notification: Notification) {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "iphone.gen3.radiowaves.left.and.right",
      accessibilityDescription: "Debagr"
    )
    statusItem.button?.toolTip = "Debagr Target Devices"

    let menu = NSMenu()
    let statusMenuItem = NSMenuItem(title: state.statusTitle, action: nil, keyEquivalent: "")
    statusMenuItem.isEnabled = false
    menu.addItem(statusMenuItem)
    menu.addItem(.separator())

    let refreshMenuItem = NSMenuItem(
      title: "Refresh Target Devices",
      action: #selector(refreshDevices),
      keyEquivalent: "r"
    )
    refreshMenuItem.target = self
    menu.addItem(refreshMenuItem)

    let gettingStartedMenuItem = NSMenuItem(
      title: "Setup & Troubleshooting…",
      action: #selector(showGettingStarted),
      keyEquivalent: ""
    )
    gettingStartedMenuItem.target = self
    menu.addItem(gettingStartedMenuItem)

    let systemCheckMenuItem = NSMenuItem(title: "System Check", action: nil, keyEquivalent: "")
    systemCheckMenuItem.submenu = systemCheckMenu()
    menu.addItem(systemCheckMenuItem)

    let diagnosticsMenuItem = NSMenuItem(
      title: "Copy Diagnostics",
      action: #selector(copyDiagnostics),
      keyEquivalent: ""
    )
    diagnosticsMenuItem.target = self
    menu.addItem(diagnosticsMenuItem)

    if ProductSupport.configuredURL(forInfoKey: "DebagrSupportURL") != nil {
      let supportMenuItem = NSMenuItem(
        title: "Support…",
        action: #selector(openSupport),
        keyEquivalent: ""
      )
      supportMenuItem.target = self
      menu.addItem(supportMenuItem)
    }

    menu.addItem(.separator())
    let launchAtLoginMenuItem = NSMenuItem(
      title: "Launch at Login",
      action: #selector(toggleLaunchAtLogin),
      keyEquivalent: ""
    )
    launchAtLoginMenuItem.target = self
    launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    menu.addItem(launchAtLoginMenuItem)

    let aboutMenuItem = NSMenuItem(
      title: "About Debagr",
      action: #selector(showAbout),
      keyEquivalent: ""
    )
    aboutMenuItem.target = self
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

    render()
    startDiscovery()
    showWelcomeIfNeeded()
  }

  func applicationWillTerminate(_ notification: Notification) {
    capture.stop()
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
          "A build-server agent for deploying signed apps to paired Apple development devices."
      ),
    ])
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  @objc private func showGettingStarted() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "Get started with Debagr"
    alert.informativeText = """
      1. Install Xcode and enable Developer Mode on each Target Device.
      2. Pair each iPhone or iPad to this Mac once over USB and trust the Mac.
      3. Keep the device connected by USB or available to this Mac over Wi-Fi.
      4. Enable Remote Login if another computer or agent will trigger deployments.

      Remote callers use SSH; Debagr installs and launches on this paired Mac through Apple's devicectl.
      """
    alert.addButton(withTitle: "Done")
    if ProductSupport.configuredURL(forInfoKey: "DebagrWebsiteURL") != nil {
      alert.addButton(withTitle: "Open Guide")
    }
    if alert.runModal() == .alertSecondButtonReturn,
      let url = ProductSupport.configuredURL(forInfoKey: "DebagrWebsiteURL")
    {
      NSWorkspace.shared.open(url)
    }
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
      + "--deploy-app '/path/to/App.app' --device '\(identifier)' --launch"
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(command, forType: .string)
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
      NSApplication.shared.activate(ignoringOtherApps: true)
      let alert = NSAlert(error: error)
      alert.messageText = "Launch at Login is unavailable"
      alert.runModal()
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
        ? "Tailscale available for remote SSH" : "Tailscale not detected (optional)",
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
}

func runMenuBarApplication() {
  let application = NSApplication.shared
  let delegate = MenuBarApplication()
  application.delegate = delegate
  application.run()
}
