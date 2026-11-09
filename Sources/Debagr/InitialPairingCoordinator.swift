import AppKit
import Network
import SwiftUI

private final class ConnectionDocumentView: NSView {
  override var isFlipped: Bool { true }
}

private final class MacDiagramButton: NSButton {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    title = ""
    isBordered = false
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.borderWidth = 1
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityChildren([])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    layer?.borderColor = NSColor.separatorColor.cgColor
    layer?.opacity = isEnabled ? 1 : 0.5
  }

  override var isEnabled: Bool { didSet { needsDisplay = true } }
  override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
}

final class InitialPairingCoordinator: NSWindowController, NSTableViewDataSource,
  NSTableViewDelegate
{
  private let discovery: DebagrPeerDiscovery
  private let table = NSTableView()
  private let pairSummary = NSTextField(
    wrappingLabelWithString: "Choose the other Mac and where your device is plugged in.")
  private let builderPicker = MacDiagramButton()
  private let clientPicker = MacDiagramButton()
  private let clearButton = NSButton(title: "Unpair This Mac", target: nil, action: nil)
  private let diagnosticsContainer = NSStackView()
  private let technicalDetails = NSTextView()
  private var hasConnectionFeedback = false
  private var hasPairingFeedback = false
  private let status = NSTextField(
    wrappingLabelWithString: "Looking for Builders and Clients…")
  private var rows: [DiscoveredDebagrPeer] = []
  private var chosenRole: DebagrMachineRole = .builder
  private var selectedPeerID: String?
  private let connectionSection = NSStackView()
  private let pairingStatus = NSTextField(
    wrappingLabelWithString:
      "Choose this Mac's role and the other machine. Its opposite role will be assigned automatically."
  )
  private let session: USBIPSessionController
  private let startButton = NSButton(title: "Start Setup Connection", target: nil, action: nil)
  private let stopButton = NSButton(title: "Stop Setup Connection", target: nil, action: nil)
  private let checkButton = NSButton(title: "Check Device", target: nil, action: nil)
  private let connectedDevices: () throws -> [USBIPDevice]
  private let deviceCheck: ConnectionDeviceCheck
  private let peerVerifier: (DiscoveredDebagrPeer, @escaping (Result<Void, Error>) -> Void) -> Void
  private var checkingDevice = false
  private var checkedDeviceMessage: String?
  private let connectionStatus = NSTextField(
    wrappingLabelWithString:
      "Start on the Client to export a device, then on the Builder to import it.")
  private var preparing = false
  private var verifyingPeer = false
  private let flowGeneration = LockedValue(0)
  private var roleControls: [NSControl] = []
  private var syncingRoles = false
  private var remoteApplyingRoles = false
  private var lastSelection: MachineRoleSelection?
  private let roleCardBox = NSView()
  private var localDeviceNames: [String]?
  private var waitingForDevice = false
  private var localSIPStatus: SystemIntegrityStatus = .unknown
  private var builderSIPStatus: SystemIntegrityStatus = .unknown
  private let builderSIPAnnotation = NSButton(
    title: "Builder SIP: checking…", target: nil, action: nil)
  private let builderDevices = NSTextField(wrappingLabelWithString: "")
  private let clientDevices = NSTextField(wrappingLabelWithString: "")
  private let builderName = NSTextField(wrappingLabelWithString: "")
  private let clientName = NSTextField(wrappingLabelWithString: "")
  private let pairedBadge = NSStackView()
  private let connectionHeader = InitialPairingCoordinator.sectionTitle(
    "Temporary setup connection")
  private let connectionDot = NSImageView()
  private let connectionHeadline = NSTextField(labelWithString: "Not connected")
  private let startNote = NSTextField(wrappingLabelWithString: "")
  private let wirelessButton = NSButton(
    title: "Set up wireless deployment…", target: nil, action: nil)
  private let virtualHereButton = NSButton(
    title: "Use VirtualHere instead…", target: nil, action: nil)
  private let handoffNote = NSTextField(wrappingLabelWithString: "")
  private let presentation = InitialPairingPresentation()
  var onWirelessSetup: (() -> Void)? {
    didSet { updateConnectionControls(active: session.isRunning) }
  }
  var onVirtualHereSetup: (() -> Void)? {
    didSet { updateConnectionControls(active: session.isRunning) }
  }

  var canOpenOtherSetup: Bool {
    !session.isRunning && !session.busy && !preparing && !checkingDevice
      && !syncingRoles && !remoteApplyingRoles
  }

  var isLocalBuilder: Bool { ((try? discovery.localSelection)?.role ?? chosenRole) == .builder }

  private static func sectionTitle(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.setAccessibilityRole(.staticText)
    return label
  }

  init(
    embedded: Bool = false,
    discovery: DebagrPeerDiscovery, session: USBIPSessionController = USBIPSessionController(),
    deviceCheck: ConnectionDeviceCheck = ConnectionDeviceCheck(),
    connectedDevices: @escaping () throws -> [USBIPDevice] = USBIPDevice.connected,
    peerVerifier: ((DiscoveredDebagrPeer, @escaping (Result<Void, Error>) -> Void) -> Void)? = nil
  ) {
    self.discovery = discovery
    self.session = session
    self.deviceCheck = deviceCheck
    self.connectedDevices = connectedDevices
    localDeviceNames = (try? connectedDevices())?.filter(\.isAppleMobileDevice).map(\.inventoryName)
    self.peerVerifier = peerVerifier ?? discovery.verifyPeer
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 590),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "Debagr — Initial Device Pairing"
    window.minSize = NSSize(width: 720, height: 540)
    window.isReleasedWhenClosed = false
    super.init(window: window)
    let heading = NSTextField(labelWithString: "Initial device pairing")
    heading.font = .systemFont(ofSize: 22, weight: .semibold)
    let refresh = NSButton(title: "Refresh", target: self, action: #selector(scan))
    refresh.bezelStyle = .rounded
    refresh.toolTip = "Look for Debagr on other Macs again"
    let header = NSStackView(views: [heading, NSView(), refresh])
    header.orientation = .horizontal
    let subtitle = NSTextField(
      wrappingLabelWithString:
        "Usually once per device and Builder. Temporarily share USB to establish trust for remote development."
    )
    subtitle.textColor = .secondaryLabelColor
    pairSummary.font = .systemFont(ofSize: 13)
    pairSummary.textColor = .secondaryLabelColor
    pairSummary.setAccessibilityLabel("Selected Builder and Client")
    var endpoints: [NSButton] = []
    for (name, devices, kind, role, purpose, endpoint) in [
      (
        builderName, builderDevices, ConnectionDeviceIcon.Kind.server, "Builder",
        "Compiles your apps",
        builderPicker
      ),
      (
        clientName, clientDevices, ConnectionDeviceIcon.Kind.laptop, "Client",
        "Device plugged in here",
        clientPicker
      ),
    ] {
      let icon = NSHostingView(
        rootView: ConnectionDeviceIcon(kind: kind)
          .scaleEffect(0.55).frame(width: 44, height: 36).accessibilityHidden(true))
      icon.sizingOptions = []
      icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
      icon.heightAnchor.constraint(equalToConstant: 36).isActive = true
      let label = Self.sectionTitle(role)
      label.font = .systemFont(ofSize: 12, weight: .medium)
      label.textColor = .secondaryLabelColor
      name.font = .systemFont(ofSize: 16, weight: .semibold)
      name.lineBreakMode = .byWordWrapping
      name.maximumNumberOfLines = 3
      name.setAccessibilityLabel(role + " Mac")
      let detail = NSTextField(wrappingLabelWithString: purpose)
      detail.font = .systemFont(ofSize: 12)
      detail.textColor = .secondaryLabelColor
      let chevron = NSImageView(
        image: NSImage(
          systemSymbolName: "chevron.down", accessibilityDescription: nil) ?? NSImage())
      chevron.contentTintColor = .secondaryLabelColor
      let titleRow = NSStackView(views: [label, NSView(), chevron])
      titleRow.orientation = .horizontal
      let inventoryTitle = NSTextField(labelWithString: "Plugged-in devices")
      inventoryTitle.font = .systemFont(ofSize: 11, weight: .medium)
      inventoryTitle.textColor = .secondaryLabelColor
      devices.font = .systemFont(ofSize: 12)
      devices.maximumNumberOfLines = 5
      devices.setAccessibilityLabel(role + " plugged-in devices")
      let identity = NSStackView(views: [titleRow, name, detail, inventoryTitle, devices])
      identity.setCustomSpacing(14, after: detail)
      identity.orientation = .vertical
      identity.alignment = .leading
      identity.spacing = 5
      let contents = NSStackView(views: [icon, identity])
      contents.orientation = .horizontal
      contents.alignment = .top
      contents.spacing = 10
      contents.translatesAutoresizingMaskIntoConstraints = false
      endpoint.addSubview(contents)
      endpoint.target = self
      endpoint.action = #selector(showMacPicker(_:))
      endpoint.tag = role == "Builder" ? 0 : 1
      endpoint.setAccessibilityLabel("Choose " + role + " Mac")
      endpoint.setAccessibilityIdentifier(role.lowercased() + "MacPicker")
      endpoint.toolTip =
        "Choose the Mac that "
        + (role == "Builder" ? "builds your apps" : "has your device plugged in")
      NSLayoutConstraint.activate([
        contents.leadingAnchor.constraint(equalTo: endpoint.leadingAnchor, constant: 14),
        contents.trailingAnchor.constraint(equalTo: endpoint.trailingAnchor, constant: -14),
        contents.topAnchor.constraint(equalTo: endpoint.topAnchor, constant: 16),
        contents.bottomAnchor.constraint(equalTo: endpoint.bottomAnchor, constant: -16),
        identity.widthAnchor.constraint(equalTo: contents.widthAnchor, constant: -54),
        titleRow.widthAnchor.constraint(equalTo: identity.widthAnchor),
        endpoint.heightAnchor.constraint(greaterThanOrEqualToConstant: 112),
      ])
      for field in [name, detail, devices] {
        field.widthAnchor.constraint(equalTo: identity.widthAnchor).isActive = true
      }
      endpoints.append(endpoint)
    }
    let route = NSTextField(labelWithString: "↔")
    route.font = .systemFont(ofSize: 25, weight: .light)
    route.textColor = .tertiaryLabelColor
    route.setAccessibilityElement(false)
    builderSIPAnnotation.target = self
    builderSIPAnnotation.action = #selector(showBuilderSIPHelp)
    builderSIPAnnotation.bezelStyle = .recessed
    builderSIPAnnotation.controlSize = .small
    builderSIPAnnotation.font = .systemFont(ofSize: 11, weight: .medium)
    builderSIPAnnotation.alignment = .left
    builderSIPAnnotation.lineBreakMode = .byTruncatingTail
    builderSIPAnnotation.image = NSImage(
      systemSymbolName: "info.circle", accessibilityDescription: nil)
    builderSIPAnnotation.imagePosition = .imageRight
    builderSIPAnnotation.wantsLayer = true
    builderSIPAnnotation.layer?.cornerRadius = 5
    builderSIPAnnotation.setAccessibilityIdentifier("builderSIPAnnotation")
    builderSIPAnnotation.setAccessibilityLabel("Builder System Integrity Protection details")
    let builderColumn = NSStackView(views: [endpoints[0], builderSIPAnnotation])
    builderColumn.orientation = .vertical
    builderColumn.spacing = 6
    let clientColumn = NSStackView(views: [endpoints[1]])
    clientColumn.orientation = .vertical
    let routeBox = NSView()
    route.translatesAutoresizingMaskIntoConstraints = false
    routeBox.addSubview(route)
    let roleStage = NSStackView(views: [builderColumn, routeBox, clientColumn])
    endpoints[0].heightAnchor.constraint(equalTo: endpoints[1].heightAnchor).isActive = true
    roleStage.orientation = .horizontal
    roleStage.alignment = .top
    roleStage.spacing = 20
    roleStage.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      routeBox.widthAnchor.constraint(equalToConstant: 24),
      routeBox.heightAnchor.constraint(equalTo: endpoints[0].heightAnchor),
      route.centerXAnchor.constraint(equalTo: routeBox.centerXAnchor),
      route.centerYAnchor.constraint(equalTo: routeBox.centerYAnchor),
      endpoints[0].widthAnchor.constraint(equalTo: builderColumn.widthAnchor),
      endpoints[1].widthAnchor.constraint(equalTo: clientColumn.widthAnchor),
      builderSIPAnnotation.widthAnchor.constraint(equalTo: builderColumn.widthAnchor),
    ])
    for column in [builderColumn, clientColumn] {
      column.widthAnchor.constraint(equalTo: roleStage.widthAnchor, multiplier: 0.5, constant: -32)
        .isActive = true
    }
    for label in [
      pairingStatus, connectionStatus, connectionHeadline, startNote, builderName, clientName,
    ] {
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    roleCardBox.addSubview(roleStage)
    roleCardBox.setAccessibilityIdentifier("pairStage")
    NSLayoutConstraint.activate([
      roleStage.leadingAnchor.constraint(equalTo: roleCardBox.leadingAnchor),
      roleStage.trailingAnchor.constraint(equalTo: roleCardBox.trailingAnchor),
      roleStage.topAnchor.constraint(equalTo: roleCardBox.topAnchor, constant: 12),
      roleStage.bottomAnchor.constraint(equalTo: roleCardBox.bottomAnchor, constant: -12),
    ])
    if let selection = try? discovery.localSelection {
      chosenRole = selection.role
      selectedPeerID = selection.peerID
      lastSelection = selection
    }
    clearButton.target = self
    clearButton.action = #selector(clearRoles)
    roleControls = [clearButton, builderPicker, clientPicker]
    discovery.canChangeRoles = { [weak self] in
      guard let self else { return false }
      return !self.preparing && !self.session.busy && !self.session.isRunning
    }
    discovery.onRoleSyncApplying = { [weak self] applying in
      guard let self else { return }
      self.remoteApplyingRoles = applying
      self.updateConnectionControls(active: self.session.isRunning)
    }
    startButton.target = self
    startButton.action = #selector(startConnection)
    stopButton.target = self
    stopButton.action = #selector(stopConnection)
    checkButton.target = self
    checkButton.action = #selector(checkDevice)
    for button in [
      clearButton, startButton, stopButton,
      checkButton,
    ] {
      button.bezelStyle = .rounded
    }
    for button in [startButton, checkButton] {
      button.controlSize = .large
      button.bezelColor = .controlAccentColor
      button.contentTintColor = .white
    }
    stopButton.isEnabled = false
    let connectionActions = NSStackView(views: [startButton, checkButton, stopButton])
    connectionActions.orientation = .horizontal
    pairingStatus.font = .systemFont(ofSize: 13)
    connectionStatus.font = .systemFont(ofSize: 13)
    connectionStatus.textColor = .secondaryLabelColor
    session.onChange = { [weak self] message, active in
      guard let self else { return }
      if !self.session.diagnostics.isEmpty {
        self.technicalDetails.string = self.session.diagnostics
      }
      let selection = try? self.discovery.localSelection
      if !active, selection == nil { return }
      if !active && self.checkingDevice {
        self.flowGeneration.set(self.flowGeneration.get() + 1)
        self.checkingDevice = false
        self.checkedDeviceMessage = nil
      }
      if !self.preparing && !self.checkingDevice {
        self.hasConnectionFeedback = true
        if active && self.session.isRunning {
          self.connectionStatus.stringValue =
            selection?.role == .client
            ? "Temporary USB sharing is running. Start Setup Connection on \(selection?.peerName ?? "the Builder") next."
            : (self.checkedDeviceMessage
              ?? "Temporary USB import is running. Complete device pairing on this Builder and approve Trust on the device if asked, then Check Device.")
        } else {
          self.checkedDeviceMessage = nil
          self.connectionStatus.stringValue = message
        }
      }
      self.updateConnectionControls(active: active)
    }
    for (id, title, width) in [
      ("name", "Mac", 160.0), ("machineRole", "Role", 90.0),
      ("roles", "Processes", 160.0), ("address", "Address", 150.0), ("source", "Found via", 120.0),
    ] {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
      column.title = title
      column.width = width
      table.addTableColumn(column)
    }
    table.delegate = self
    table.dataSource = self
    table.rowHeight = 30
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    table.setAccessibilityLabel("Discovered Macs and technical details")
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.borderType = .bezelBorder
    scroll.heightAnchor.constraint(equalToConstant: 125).isActive = true
    technicalDetails.isEditable = false
    technicalDetails.isSelectable = true
    technicalDetails.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    let logScroll = NSScrollView()
    logScroll.documentView = technicalDetails
    logScroll.hasVerticalScroller = true
    logScroll.borderType = .bezelBorder
    logScroll.heightAnchor.constraint(equalToConstant: 85).isActive = true
    let copy = NSButton(title: "Copy Diagnostics", target: self, action: #selector(copyDiagnostics))
    let diagnosticActions = NSStackView(views: [copy, clearButton])
    diagnosticActions.orientation = .horizontal
    diagnosticsContainer.orientation = .vertical
    diagnosticsContainer.alignment = .leading
    diagnosticsContainer.spacing = 8
    for view in [scroll, logScroll, diagnosticActions] {
      diagnosticsContainer.addArrangedSubview(view)
    }
    diagnosticsContainer.isHidden = true
    let disclosure = NSButton(
      title: "Show Diagnostics", target: self, action: #selector(toggleDiagnostics(_:)))
    disclosure.setButtonType(.onOff)
    disclosure.bezelStyle = .recessed
    disclosure.setAccessibilityLabel("Show or hide diagnostics")
    status.font = .systemFont(ofSize: 12)
    status.textColor = .secondaryLabelColor
    startNote.font = .systemFont(ofSize: 12)
    startNote.textColor = .secondaryLabelColor
    let pairHeader = NSStackView(views: [
      Self.sectionTitle("Your Macs"), NSView(), pairedBadge,
    ])
    pairHeader.orientation = .horizontal
    let pairedIcon = NSImageView(
      image: NSImage(
        systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) ?? NSImage())
    pairedIcon.contentTintColor = .systemGreen
    let pairedLabel = NSTextField(labelWithString: "Macs linked")
    pairedLabel.textColor = .secondaryLabelColor
    pairedBadge.setViews([pairedIcon, pairedLabel], in: .leading)
    pairedBadge.spacing = 4
    pairedBadge.setAccessibilityElement(true)
    pairedBadge.setAccessibilityLabel("Both Macs linked; device pairing is a separate step")
    connectionDot.image = NSImage(
      systemSymbolName: "circle.fill", accessibilityDescription: nil)
    connectionDot.symbolConfiguration = .init(pointSize: 10, weight: .regular)
    connectionHeadline.font = .systemFont(ofSize: 14, weight: .semibold)
    connectionHeadline.setAccessibilityLabel("Connection state")
    let connectionState = NSStackView(views: [connectionDot, connectionHeadline])
    connectionState.orientation = .horizontal
    connectionState.spacing = 6
    let pairSection = NSStackView(views: [pairHeader, roleCardBox])
    pairSection.orientation = .vertical
    pairSection.alignment = .leading
    pairSection.spacing = 16
    for view in [pairHeader, roleCardBox] {
      view.widthAnchor.constraint(equalTo: pairSection.widthAnchor).isActive = true
    }
    connectionSection.setViews(
      [
        connectionHeader, connectionState, connectionStatus, connectionActions, startNote,
      ], in: .leading)
    connectionSection.orientation = .vertical
    connectionSection.alignment = .leading
    connectionSection.spacing = 12
    connectionSection.setAccessibilityIdentifier("connectionActions")
    for view in [connectionStatus, startNote, connectionHeadline] {
      view.widthAnchor.constraint(lessThanOrEqualTo: connectionSection.widthAnchor).isActive = true
    }
    connectionHeadline.maximumNumberOfLines = 2
    connectionHeadline.lineBreakMode = .byWordWrapping
    let divider = NSBox()
    divider.boxType = .separator
    let workflow = NSStackView(views: [pairingStatus, divider, connectionSection])
    workflow.orientation = .vertical
    workflow.alignment = .leading
    workflow.spacing = 12
    workflow.setAccessibilityIdentifier("connectionWorkflow")
    for view in [pairingStatus, divider, connectionSection] {
      view.widthAnchor.constraint(equalTo: workflow.widthAnchor).isActive = true
    }
    let workspace = NSStackView(views: [pairSection, workflow])
    workspace.orientation = .vertical
    workspace.alignment = .leading
    workspace.spacing = 20
    for view in [pairSection, workflow] {
      view.widthAnchor.constraint(equalTo: workspace.widthAnchor).isActive = true
    }
    wirelessButton.target = self
    wirelessButton.action = #selector(openWirelessSetup)
    virtualHereButton.target = self
    virtualHereButton.action = #selector(openVirtualHereSetup)
    for button in [wirelessButton, virtualHereButton] { button.bezelStyle = .rounded }
    handoffNote.font = .systemFont(ofSize: 12)
    handoffNote.textColor = .secondaryLabelColor
    let destinations = NSStackView(views: [wirelessButton, virtualHereButton])
    destinations.orientation = .horizontal
    destinations.spacing = 12
    let stack = NSStackView(views: [
      header, subtitle, workspace, handoffNote, destinations, status, disclosure,
      diagnosticsContainer,
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.setCustomSpacing(28, after: subtitle)
    stack.setCustomSpacing(24, after: workspace)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let mainScroll = NSScrollView()
    mainScroll.translatesAutoresizingMaskIntoConstraints = false
    mainScroll.hasVerticalScroller = true
    mainScroll.drawsBackground = false
    let document = ConnectionDocumentView()
    document.translatesAutoresizingMaskIntoConstraints = false
    mainScroll.documentView = document
    document.addSubview(stack)
    window.contentView!.addSubview(mainScroll)
    NSLayoutConstraint.activate([
      mainScroll.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
      mainScroll.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
      mainScroll.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
      mainScroll.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
      document.widthAnchor.constraint(equalTo: mainScroll.contentView.widthAnchor),
      stack.leadingAnchor.constraint(
        equalTo: document.leadingAnchor, constant: embedded ? 20 : 24),
      stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24),
    ])
    for view in [header, subtitle, workspace, status, diagnosticsContainer] {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    scroll.widthAnchor.constraint(equalTo: diagnosticsContainer.widthAnchor).isActive = true
    logScroll.widthAnchor.constraint(equalTo: diagnosticsContainer.widthAnchor).isActive = true
    if embedded {
      for view in [header, subtitle] {
        stack.removeArrangedSubview(view)
        view.removeFromSuperview()
      }
      destinations.removeArrangedSubview(wirelessButton)
      wirelessButton.removeFromSuperview()
      stack.removeArrangedSubview(handoffNote)
      handoffNote.removeFromSuperview()
      connectionSection.removeArrangedSubview(connectionActions)
      connectionActions.removeFromSuperview()
      stack.removeFromSuperview()
      presentation.content = stack
    }
    discovery.onChange = { [weak self] rows, message in
      guard let self else { return }
      self.rows = rows
      if let local = rows.first(where: { $0.peer.nodeID == self.discovery.localNodeID }) {
        self.localDeviceNames = local.peer.connectedDeviceNames
        self.localSIPStatus = local.peer.sipStatus ?? .unknown
      }
      self.updatePeerChoices()
      self.table.reloadData()
      if !message.isEmpty { self.status.stringValue = message }
      self.updateConnectionControls(active: self.session.isRunning)
    }
    updateConnectionControls(active: session.isRunning)
    window.center()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func activate(in sharedWindow: NSWindow) -> InitialPairingPresentation {
    if window !== sharedWindow {
      window?.orderOut(nil)
      window = sharedWindow
    }
    scan()
    session.poll()
    return presentation
  }

  private var selectedPeer: DiscoveredDebagrPeer? {
    rows.first { $0.peer.nodeID == selectedPeerID }
  }

  private func updateConnectionControls(active: Bool) {
    let selection = try? discovery.localSelection
    session.setFeedbackContext(selection.map { "\($0.role.rawValue):\($0.peerID)" })
    let remote = selection.flatMap { saved in rows.first { $0.peer.nodeID == saved.peerID } }
    let confirmed =
      selection?.isConfirmed(with: remote?.peer, localNodeID: discovery.localNodeID) == true
    let locked = active || preparing || session.busy || syncingRoles || remoteApplyingRoles
    let setup = selection == nil
    wirelessButton.isEnabled = canOpenOtherSetup && isLocalBuilder && onWirelessSetup != nil
    virtualHereButton.isEnabled = canOpenOtherSetup && isLocalBuilder && onVirtualHereSetup != nil
    handoffNote.stringValue =
      !isLocalBuilder
      ? "After temporary sharing stops, continue wireless setup on the Builder."
      : !canOpenOtherSetup
        ? "Stop the setup connection before switching to wireless or another USB method."
        : "Already trusted this Builder? Set up Wi-Fi + VPN for everyday deployment. VirtualHere is an optional USB alternative."
    if waitingForDevice, currentClientDeviceNames?.isEmpty == false {
      waitingForDevice = false
      hasConnectionFeedback = false
    }
    let needsDevice =
      waitingForDevice
      || (selection != nil && currentClientDeviceNames?.isEmpty == true
        && !(selection?.role == .builder && remote?.peer.roles.contains("server") == true))
    connectionSection.isHidden = setup
    startButton.isHidden = setup || active || preparing
    startButton.isEnabled = confirmed && !locked
    startButton.title =
      needsDevice
      ? "Start Setup Connection"
      : selection.map {
        session.backendPath(for: $0.role) == nil
          ? "Set Up USB Support…" : "Start Setup Connection"
      } ?? "Start Setup Connection"
    stopButton.isHidden = !active && !preparing && !session.busy
    stopButton.title =
      session.busy
      ? "Cancel Approval"
      : verifyingPeer ? "Cancel Check" : (preparing ? "Cancel Waiting" : "Stop Setup Connection")
    stopButton.isEnabled = active || preparing || session.busy
    checkButton.isHidden = selection?.role != .builder || !session.isRunning || setup
    checkButton.isEnabled =
      !checkingDevice && !session.busy && !syncingRoles && !remoteApplyingRoles
    checkButton.title = checkingDevice ? "Checking Device…" : "Check Device"
    checkButton.keyEquivalent = !checkButton.isHidden && checkButton.isEnabled ? "\r" : ""
    clearButton.isHidden = selection == nil || locked
    for control in roleControls { control.isEnabled = !locked }
    startButton.keyEquivalent = !setup && startButton.isEnabled ? "\r" : ""
    let otherName = selectedPeer?.peer.name ?? selection?.peerName
    let thisName = Host.current().localizedName ?? "This Mac"
    let localName = "\(thisName) (this Mac)"
    builderName.stringValue = chosenRole == .builder ? localName : (otherName ?? "Choose a Mac")
    clientName.stringValue = chosenRole == .client ? localName : (otherName ?? "Choose a Mac")
    pairSummary.stringValue =
      "Builder: \(builderName.stringValue)\nClient: \(clientName.stringValue)"
    let otherDevices = selectedPeer.flatMap {
      $0.hasRecentInventory ? $0.peer.connectedDeviceNames : nil
    }
    setDeviceSummary(
      builderDevices, names: chosenRole == .builder ? localDeviceNames : otherDevices,
      hasMac: chosenRole == .builder || otherName != nil)
    setDeviceSummary(
      clientDevices, names: chosenRole == .client ? localDeviceNames : otherDevices,
      hasMac: chosenRole == .client || otherName != nil)
    builderPicker.setAccessibilityValue(builderName.stringValue + ". " + builderDevices.stringValue)
    clientPicker.setAccessibilityValue(clientName.stringValue + ". " + clientDevices.stringValue)
    let remoteSIP = selectedPeer.flatMap { $0.hasRecentInventory ? $0.peer.sipStatus : nil }
    builderSIPStatus = chosenRole == .builder ? localSIPStatus : (remoteSIP ?? .unknown)
    builderSIPAnnotation.title = builderSIPStatus.annotation
    builderSIPAnnotation.toolTip =
      builderSIPStatus.explanation + " Click for requirements and Recovery instructions."
    builderSIPAnnotation.setAccessibilityValue(builderSIPStatus.explanation)
    let sipTint: NSColor =
      builderSIPStatus == .disabled
      ? .systemGreen
      : builderSIPStatus == .unknown ? .secondaryLabelColor : .systemOrange
    builderSIPAnnotation.contentTintColor = sipTint
    builderSIPAnnotation.layer?.backgroundColor = sipTint.withAlphaComponent(0.10).cgColor
    pairedBadge.isHidden = !confirmed
    connectionHeader.textColor = confirmed ? .labelColor : .tertiaryLabelColor
    let deviceReady =
      checkedDeviceMessage?.hasPrefix(ConnectionDeviceCheck.readyPrefix) == true
    presentation.step = deviceReady ? .review : confirmed ? .network : .device
    let headline: (String, NSColor)
    if preparing {
      headline =
        verifyingPeer
        ? ("Checking the other Mac…", .systemOrange)
        : (selection?.role == .builder
          ? ("Waiting for the Client to share its device…", .systemOrange)
          : ("Getting ready…", .systemOrange))
    } else if session.busy {
      headline = ("Waiting for administrator approval…", .systemOrange)
    } else if session.isRunning {
      if selection?.role == .client {
        headline = ("Temporary USB sharing running", .systemBlue)
      } else if checkingDevice {
        headline = ("Checking the device…", .systemOrange)
      } else if deviceReady {
        headline = ("Device ready", .systemGreen)
      } else if checkedDeviceMessage != nil {
        headline = ("Device not ready yet", .systemOrange)
      } else {
        headline = ("Temporary USB import · check device", .systemBlue)
      }
    } else if active {
      headline = ("Updating the connection…", .systemOrange)
    } else if needsDevice {
      headline = ("No device connected", .systemOrange)
    } else {
      headline = ("Not connected", .tertiaryLabelColor)
    }
    connectionHeadline.stringValue = headline.0
    connectionDot.contentTintColor = headline.1
    startNote.isHidden = startButton.isHidden
    startNote.stringValue =
      needsDevice
      ? "Plug the device into the Client for this initial pairing step."
      : selection?.role == .client
        ? "Administrator approval starts temporary USB sharing for initial pairing. Starting or stopping it can ask again."
        : "Administrator approval starts a temporary USB import for initial pairing. Starting or stopping it can ask again."
    if !syncingRoles && !hasPairingFeedback {
      pairingStatus.font = .systemFont(ofSize: 13)
      if setup {
        pairingStatus.stringValue =
          "Click either Mac to choose from the available computers. Both roles update automatically."
      } else if !confirmed, let selection {
        pairingStatus.stringValue =
          remote == nil
          ? "\(selection.peerName) is not currently reachable. Open Debagr there, check the private network, then Refresh."
          : "These Macs have not confirmed matching roles. Click a Mac to reconnect them."
      } else {
        pairingStatus.stringValue =
          active || preparing
          ? "Stop the connection before choosing different Macs."
          : "Click either Mac to change the pair. Both roles update automatically."
      }
    }
    if !hasConnectionFeedback && !active && !preparing {
      connectionStatus.stringValue =
        needsDevice
        ? missingDeviceInstruction
        : confirmed
          ? (selection?.role == .client
            ? "For initial pairing, plug in and unlock your device, then Start Setup Connection here."
            : "For initial pairing, start the setup connection on the Client, then Start Setup Connection here.")
          : "Pairing must be confirmed by both Macs before a connection can start."
    }
    presentation.canLeave = canOpenOtherSetup
    presentation.status = setup ? pairingStatus.stringValue : connectionStatus.stringValue
    presentation.actions = [("start", startButton), ("check", checkButton), ("stop", stopButton)]
      .filter { !$0.1.isHidden }
      .map { id, button in
        PairingFlowAction(
          id: id, title: button.title, enabled: button.isEnabled,
          primary: id != "stop", perform: { [weak button] in button?.performClick(nil) })
      }
    presentation.revision += 1
  }

  private var currentClientDeviceNames: [String]? {
    if chosenRole == .client { return localDeviceNames }
    guard let peer = selectedPeer, peer.hasRecentInventory else { return nil }
    return peer.peer.connectedDeviceNames
  }

  @objc private func openWirelessSetup() {
    guard canOpenOtherSetup, isLocalBuilder else { return }
    onWirelessSetup?()
  }

  @objc private func openVirtualHereSetup() {
    guard canOpenOtherSetup, isLocalBuilder else { return }
    onVirtualHereSetup?()
  }

  private var missingDeviceInstruction: String {
    let client = chosenRole == .client ? "this Mac" : (selectedPeer?.peer.name ?? "the Client Mac")
    return
      "Plug in and unlock an iPhone or iPad on \(client), then Start Setup Connection on that Mac."
  }

  private func setDeviceSummary(_ label: NSTextField, names: [String]?, hasMac: Bool) {
    guard let names else {
      label.stringValue =
        hasMac ? "Device list unavailable — Refresh" : "Choose a Mac to see devices"
      label.textColor = .secondaryLabelColor
      return
    }
    label.stringValue =
      names.isEmpty
      ? "No device connected"
      : names.prefix(4).map { "• " + $0 }.joined(separator: "\n")
        + (names.count > 4 ? "\n+ \(names.count - 4) more" : "")
    label.toolTip =
      names.isEmpty ? "Connect an iPhone or iPad using USB" : names.joined(separator: "\n")
    label.textColor = names.isEmpty ? .secondaryLabelColor : .labelColor
  }

  private func readClientDevices() throws -> [USBIPDevice] {
    let devices = try connectedDevices().filter(\.isAppleMobileDevice)
    localDeviceNames = devices.map(\.inventoryName)
    return devices
  }

  private func showMissingDevice() {
    resetConnectionFeedback()
    waitingForDevice = true
    hasConnectionFeedback = true
    connectionStatus.stringValue = missingDeviceInstruction
    updateConnectionControls(active: false)
  }

  @objc private func showBuilderSIPHelp() {
    let alert = NSAlert()
    alert.messageText = builderSIPStatus.annotation
    alert.informativeText =
      builderSIPStatus.explanation + "\n\n" + SystemIntegrityStatus.setupExplanation
    alert.addButton(withTitle: "Done")
    alert.addButton(withTitle: "Apple Instructions")
    alert.addButton(withTitle: "Backend Requirements")
    let response = alert.runModal()
    let address: String?
    switch response {
    case .alertSecondButtonReturn:
      address =
        "https://developer.apple.com/documentation/security/disabling-and-enabling-system-integrity-protection"
    case .alertThirdButtonReturn:
      address = "https://github.com/karstx/usbip-macos#permissions"
    default: address = nil
    }
    if let address, let url = URL(string: address) { NSWorkspace.shared.open(url) }
  }

  @objc private func showMacPicker(_ sender: NSButton) {
    guard sender.isEnabled else { return }
    machineMenu(for: sender.tag == 0 ? .builder : .client)
      .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
  }

  func machineMenu(for role: DebagrMachineRole) -> NSMenu {
    let menu = NSMenu(title: "Choose \(role.rawValue.capitalized)")
    let choices =
      [(discovery.localNodeID, "\(Host.current().localizedName ?? "This Mac") (this Mac)")]
      + rows.filter { $0.peer.nodeID != discovery.localNodeID && $0.peer.roles.contains("app") }
      .map { ($0.peer.nodeID, $0.peer.name) }
    for (id, name) in choices {
      let item = NSMenuItem(title: name, action: #selector(chooseMachine(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = ["role": role.rawValue, "nodeID": id]
      let selectedID = role == chosenRole ? discovery.localNodeID : selectedPeerID
      item.state = id == selectedID ? .on : .off
      if let peer = rows.first(where: { $0.peer.nodeID == id })?.peer,
        let pairedID = peer.pairedNodeID, pairedID != discovery.localNodeID
      {
        item.title += " (paired with another Mac)"
        item.isEnabled = false
      }
      menu.addItem(item)
      let names: [String]?
      if id == discovery.localNodeID {
        names = localDeviceNames
      } else if let peer = rows.first(where: { $0.peer.nodeID == id }), peer.hasRecentInventory {
        names = peer.peer.connectedDeviceNames
      } else {
        names = nil
      }
      let summary =
        names.map { names in
          if names.isEmpty { return "No device connected" }
          let preview = names.prefix(3).joined(separator: ", ")
          return String(preview.prefix(90)) + (names.count > 3 || preview.count > 90 ? "…" : "")
        } ?? "Device list unavailable"
      let devices = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
      devices.indentationLevel = 1
      devices.isEnabled = false
      menu.addItem(devices)
    }
    menu.autoenablesItems = false
    if choices.count == 1 {
      let empty = NSMenuItem(
        title: "No other Macs found — open Debagr there, then Refresh", action: nil,
        keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(.separator())
      menu.addItem(empty)
    }
    return menu
  }

  @objc private func chooseMachine(_ sender: NSMenuItem) {
    guard !syncingRoles, !remoteApplyingRoles, !session.isRunning, !preparing, !session.busy,
      let choice = sender.representedObject as? [String: String],
      let role = choice["role"].flatMap(DebagrMachineRole.init(rawValue:)),
      let id = choice["nodeID"]
    else { return }
    if id == discovery.localNodeID {
      chosenRole = role
      if selectedPeerID == nil {
        let available = rows.filter {
          $0.peer.nodeID != discovery.localNodeID && $0.peer.roles.contains("app")
            && ($0.peer.pairedNodeID == nil || $0.peer.pairedNodeID == discovery.localNodeID)
        }
        if available.count == 1 { selectedPeerID = available[0].peer.nodeID }
      }
    } else {
      guard rows.contains(where: { $0.peer.nodeID == id && $0.peer.roles.contains("app") }) else {
        return
      }
      selectedPeerID = id
      chosenRole = role.opposite
    }
    hasPairingFeedback = false
    updateConnectionControls(active: session.isRunning)
    guard selectedPeer != nil else { return }
    saveRoles()
  }

  @objc private func toggleDiagnostics(_ sender: NSButton) {
    diagnosticsContainer.isHidden = sender.state != .on
    sender.title = sender.state == .on ? "Hide Diagnostics" : "Show Diagnostics"

  }

  @objc private func copyDiagnostics() {
    let lines = rows.map {
      "\($0.peer.name): \($0.peer.roleDescription), \($0.address), \($0.source)"
    }
    let text =
      ([pairSummary.stringValue, pairingStatus.stringValue, connectionStatus.stringValue]
      + lines + [technicalDetails.string]).joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private func showConnectionFailure(_ error: Error) {
    let detail = error.localizedDescription
    technicalDetails.string = detail
    hasConnectionFeedback = true
    connectionStatus.stringValue =
      detail.count <= 240
      ? detail
      : "The connection could not start. Open Diagnostics for the error, then try again."
    updateConnectionControls(active: session.isRunning)
  }

  private func selectItem(title: String, choices: [String]) -> Int? {
    guard !choices.isEmpty else { return nil }
    let alert = NSAlert()
    alert.messageText = title
    let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 26))
    picker.addItems(withTitles: choices)
    alert.accessoryView = picker
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn ? picker.indexOfSelectedItem : nil
  }

  private func address(title: String, suggestion: String) throws -> String? {
    if NetworkSupport.isAllowedPrivateVPNIPv4(suggestion) { return suggestion }
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = "Enter the Mac's private VPN IPv4 address."
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
    alert.accessoryView = field
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    guard NetworkSupport.isAllowedPrivateVPNIPv4(field.stringValue) else {
      throw USBIPError.invalid("A private IPv4 address is required.")
    }
    return field.stringValue
  }

  @objc private func startConnection() {
    guard !syncingRoles, !remoteApplyingRoles else { return }
    do {
      guard let selection = try discovery.localSelection,
        let remote = rows.first(where: { $0.peer.nodeID == selection.peerID }),
        selection.isConfirmed(with: remote.peer, localNodeID: discovery.localNodeID)
      else {
        throw USBIPError.invalid(
          "Click the Builder or Client Mac in the diagram to connect the two computers first.")
      }
      guard !session.isRunning, !preparing, !session.busy else { return }
      if selection.role == .client, try readClientDevices().isEmpty {
        showMissingDevice()
        return
      }
      if selection.role == .builder, remote.hasRecentInventory,
        remote.peer.connectedDeviceNames?.isEmpty == true, !remote.peer.roles.contains("server")
      {
        showMissingDevice()
        return
      }
      resetConnectionFeedback()
      preparing = true
      hasConnectionFeedback = true
      updateConnectionControls(active: false)
      guard
        let host = try address(
          title: "Address of \(remote.peer.name)",
          suggestion: remote.address.components(separatedBy: ":").first ?? "")
      else {
        preparing = false
        connectionStatus.stringValue = "Connection setup cancelled. No USB process was started."
        updateConnectionControls(active: false)
        return
      }
      let target = DiscoveredDebagrPeer(
        peer: remote.peer, address: host, source: remote.source,
        endpoint: .hostPort(host: NWEndpoint.Host(host), port: DebagrPeerDiscovery.port))
      verifyingPeer = true
      let generation = flowGeneration.get() + 1
      flowGeneration.set(generation)
      connectionStatus.stringValue = "Checking \(remote.peer.name)…"
      updateConnectionControls(active: false)
      peerVerifier(target) { [weak self] result in
        guard let self, self.flowGeneration.get() == generation else { return }
        self.verifyingPeer = false
        switch result {
        case .success:
          self.beginConnection(selection: selection, remote: target)
        case .failure(let error):
          self.preparing = false
          self.technicalDetails.string = error.localizedDescription
          self.connectionStatus.stringValue =
            "Could not verify \(remote.peer.name). Refresh the Mac list and retry. Details are in Diagnostics."
          self.updateConnectionControls(active: false)
        }
      }
    } catch {
      preparing = false
      verifyingPeer = false
      showConnectionFailure(error)
    }
  }

  private func beginConnection(selection: MachineRoleSelection, remote: DiscoveredDebagrPeer) {
    var handedOff = false
    var failed = false
    defer {
      if !handedOff {
        preparing = false
        if !failed {
          connectionStatus.stringValue =
            "Connection setup cancelled. Start Setup Connection when you are ready."
        }
        updateConnectionControls(active: session.isRunning)
      }
    }
    do {
      guard try discovery.localSelection == selection else {
        throw USBIPError.invalid("The selected pair changed. Refresh and start again.")
      }
      let devices = selection.role == .client ? try readClientDevices() : []
      if selection.role == .client, devices.isEmpty {
        waitingForDevice = true
        throw USBIPError.invalid(missingDeviceInstruction)
      }
      var tool = session.backendPath(for: selection.role)
      if tool == nil {
        let explanation = NSAlert()
        explanation.messageText = "Set Up USB Support"
        explanation.informativeText =
          session.hasMissingSavedBackend(for: selection.role)
          ? "Your previously chosen USB support tool is no longer available. Choose its new location or a replacement trusted \(selection.role.backend) executable."
          : "This Mac needs a separately installed USB support tool before it can connect. Choose your trusted \(selection.role.backend) executable. This choice will be remembered for next time. Administrator approval comes later, when the connection starts."
        explanation.addButton(withTitle: "Choose USB Support…")
        explanation.addButton(withTitle: "Cancel")
        guard explanation.runModal() == .alertFirstButtonReturn else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the installed \(selection.role.backend) executable"
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try session.rememberBackend(url.path, for: selection.role)
        tool = url.path
      }
      let host = remote.address
      if selection.role == .client {
        checkedDeviceMessage = nil
        guard
          let index = selectItem(
            title: "Choose the device to share with \(remote.peer.name)",
            choices: devices.map { "\($0.name) — \($0.serial)" })
        else { return }
        let automatic = (try? NetworkSupport.resolveTailscaleInterface().ipv4Address) ?? ""
        guard let listen = try address(title: "This Client Mac's address", suggestion: automatic)
        else { return }
        preparing = false
        try session.start(arguments: [
          "serve", "--tool", tool!, "--listen", listen, "--peer", host, "--serial",
          devices[index].serial,
        ])
        handedOff = true
        updateConnectionControls(active: session.isRunning)
      } else {
        handedOff = true
        preparing = true
        hasConnectionFeedback = true
        let generation = flowGeneration.get() + 1
        flowGeneration.set(generation)
        updateConnectionControls(active: false)
        connectionStatus.stringValue =
          "Waiting for the Client's USB export. Start Setup Connection on the Client if it is not already running…"
        let backend = tool!
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
          let deadline = Date().addingTimeInterval(60)
          var lastError: Error = USBIPError.invalid("No devices exported by the Client.")
          var devices: [USBIPRemoteDevice] = []
          while Date() < deadline, self?.flowGeneration.get() == generation {
            do {
              devices = try USBIPRemoteInventory.list(host: host).filter { $0.vendorID == 0x05ac }
            } catch { lastError = error }
            if !devices.isEmpty { break }
            Thread.sleep(forTimeInterval: 1)
          }
          let found = devices
          let failure = lastError
          DispatchQueue.main.async { [weak self] in
            guard let self, self.flowGeneration.get() == generation else { return }
            guard !found.isEmpty else {
              self.preparing = false
              self.technicalDetails.string = failure.localizedDescription
              self.connectionStatus.stringValue =
                "No shared device found. On the Client, plug in and unlock the device and click Start Setup Connection. Then retry here."
              self.updateConnectionControls(active: false)
              return
            }
            self.technicalDetails.string = found.map {
              "Device \($0.busID): \(String(format: "%04x:%04x", $0.vendorID, $0.productID))"
            }.joined(separator: "\n")
            guard
              let index = found.count == 1
                ? 0
                : self.selectItem(
                  title: "Choose the Client device to import",
                  choices: found.enumerated().map { index, _ in
                    "Apple device \(index + 1) shared by \(remote.peer.name)"
                  })
            else {
              self.preparing = false
              self.connectionStatus.stringValue =
                "Device selection cancelled. The Client is still sharing its device."
              self.updateConnectionControls(active: false)
              return
            }
            do {
              self.preparing = false
              try self.session.start(arguments: [
                "attach", "--tool", backend, "--remote", host, "--busid", found[index].busID,
              ])
            } catch { self.showConnectionFailure(error) }
          }
        }
      }
    } catch {
      failed = true
      showConnectionFailure(error)
    }
  }

  @objc private func stopConnection() {
    if session.busy {
      session.cancelApproval()
      return
    }
    checkedDeviceMessage = nil
    if checkingDevice {
      flowGeneration.set(flowGeneration.get() + 1)
      checkingDevice = false
    }
    if preparing {
      flowGeneration.set(flowGeneration.get() + 1)
      preparing = false
      connectionStatus.stringValue =
        verifyingPeer
        ? "Mac check cancelled. No USB process was started."
        : "Waiting cancelled. No USB import was started."
      verifyingPeer = false
      updateConnectionControls(active: false)
    } else {
      session.stop()
    }
  }

  @objc private func scan() {
    if !syncingRoles { hasPairingFeedback = false }
    status.stringValue = "Looking for your other Mac…"
    discovery.refresh()
  }

  private func updatePeerChoices() {
    let saved = try? discovery.localSelection
    if saved != lastSelection {
      if !syncingRoles { hasPairingFeedback = false }
      if !session.isRunning && !preparing { resetConnectionFeedback() }
      lastSelection = saved
      if let saved {
        chosenRole = saved.role
        selectedPeerID = saved.peerID
      } else if !syncingRoles {
        selectedPeerID = nil
      }
    }
  }

  @objc private func saveRoles() {
    guard !syncingRoles, !remoteApplyingRoles, !session.isRunning, !preparing, !session.busy,
      let peer = selectedPeer
    else { return }
    let role = chosenRole
    syncingRoles = true
    hasPairingFeedback = true
    updateConnectionControls(active: false)
    pairingStatus.stringValue = "Connecting to \(peer.peer.name) to set both roles…"
    discovery.assignRoles(
      role: role, peer: peer,
      progress: { [weak self] in
        self?.pairingStatus.font = .systemFont(ofSize: 13)
        self?.pairingStatus.stringValue = $0
        self?.window?.contentView?.layoutSubtreeIfNeeded()
        if let field = self?.pairingStatus { field.scrollToVisible(field.bounds) }
      },
      completion: { [weak self] result in
        guard let self else { return }
        self.syncingRoles = false
        self.updateConnectionControls(active: self.session.isRunning)
        switch result {
        case .success:
          self.hasPairingFeedback = false
          self.hasConnectionFeedback = false
          self.resetConnectionFeedback()
          self.updatePeerChoices()
          self.updateConnectionControls(active: self.session.isRunning)
          self.pairingStatus.font = .systemFont(ofSize: 13)
          self.pairingStatus.stringValue =
            "Both Macs confirmed their roles. You can change them from either Mac."
        case .failure(let error):
          self.pairingStatus.font = .systemFont(ofSize: 13)
          if let saved = try? self.discovery.localSelection {
            self.chosenRole = saved.role
            self.selectedPeerID = saved.peerID
          }
          self.updateConnectionControls(active: self.session.isRunning)
          self.pairingStatus.stringValue = error.localizedDescription
        }
      })
  }

  @objc private func clearRoles() {
    hasPairingFeedback = false
    hasConnectionFeedback = false
    resetConnectionFeedback()
    discovery.clearSelection()
    chosenRole = .builder
    selectedPeerID = nil
    pairingStatus.stringValue = "Selection cleared on this Mac."
  }

  private func resetConnectionFeedback() {
    waitingForDevice = false
    flowGeneration.set(flowGeneration.get() + 1)
    checkingDevice = false
    checkedDeviceMessage = nil
    hasConnectionFeedback = false
    technicalDetails.string = ""
    session.resetFeedback()
  }

  @objc private func checkDevice() {
    guard let selection = try? discovery.localSelection, selection.role == .builder,
      session.isRunning, !checkingDevice, !session.busy
    else { return }
    checkingDevice = true
    hasConnectionFeedback = true
    let generation = flowGeneration.get() + 1
    flowGeneration.set(generation)
    connectionStatus.stringValue = "Looking for your device through CoreDevice…"
    updateConnectionControls(active: true)
    let checker = deviceCheck
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = Result { try checker.devices() }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.flowGeneration.get() == generation else { return }
        do {
          let devices = try result.get()
          guard !devices.isEmpty else {
            throw USBIPError.invalid(
              "No device is visible to the Builder. Confirm that \(selection.peerName) is sharing the device and approve Trust on the device if asked."
            )
          }
          guard
            let index = devices.count == 1
              ? 0
              : self.selectItem(
                title: "Which device should Debagr check?",
                choices: devices.map {
                  "\($0.displayName) (…\($0.identity.value.suffix(6)))"
                })
          else {
            self.checkingDevice = false
            self.connectionStatus.stringValue =
              "Device check cancelled. The USB import is still running."
            self.updateConnectionControls(active: self.session.isRunning)
            return
          }
          let device = devices[index]
          self.connectionStatus.stringValue = "Checking \(device.displayName) through CoreDevice…"
          DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let checked = Result { try checker.check(device) }
            DispatchQueue.main.async { [weak self] in
              guard let self, self.flowGeneration.get() == generation else { return }
              self.checkingDevice = false
              guard self.session.isRunning else {
                self.checkedDeviceMessage = nil
                self.connectionStatus.stringValue =
                  "USB import stopped. Start Setup Connection again before checking the device."
                self.updateConnectionControls(active: false)
                return
              }
              self.technicalDetails.string =
                "CoreDevice check: \(device.displayName), \(device.identity.value). This does not identify the transport path or prove installation/launch."
              switch checked {
              case .success(let message):
                self.checkedDeviceMessage = message
                self.connectionStatus.stringValue = message
              case .failure(let error):
                self.checkedDeviceMessage = ConnectionDeviceCheck.recovery(for: error)
                self.technicalDetails.string += "\n" + error.localizedDescription
                self.connectionStatus.stringValue = self.checkedDeviceMessage!
              }
              self.updateConnectionControls(active: self.session.isRunning)
            }
          }
        } catch {
          self.checkingDevice = false
          self.technicalDetails.string = error.localizedDescription
          self.checkedDeviceMessage =
            error is USBIPError
            ? error.localizedDescription : ConnectionDeviceCheck.recovery(for: error)
          self.connectionStatus.stringValue = self.checkedDeviceMessage!
          self.updateConnectionControls(active: self.session.isRunning)
        }
      }
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let entry = rows[row]
    let text: String
    switch tableColumn?.identifier.rawValue {
    case "name": text = entry.peer.name
    case "machineRole": text = entry.peer.machineRole?.rawValue.capitalized ?? "Not selected"
    case "roles": text = entry.peer.roleDescription
    case "address": text = entry.address
    default: text = entry.source
    }
    let label = NSTextField(labelWithString: text)
    label.lineBreakMode = .byTruncatingTail
    label.toolTip = text
    return label
  }
}
