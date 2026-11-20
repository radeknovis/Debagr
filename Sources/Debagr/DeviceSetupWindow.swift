import AppKit
import SwiftUI

@MainActor
final class DeviceSetupModel: ObservableObject {
  enum Page { case guide, setup, saved, preferences }

  @Published var developerToolsAvailable: Bool?
  @Published var confirmedSelection = false
  @Published var configured: ConfiguredDevice?
  @Published var page = Page.setup
  @Published var path = ConnectionPath.existing
  @Published var initialPairing: InitialPairingPresentation?
  @Published var step = ConnectionStep.device
  @Published var verification = ConnectionVerification.checking
  @Published var provider = NetworkProvider.tailscale {
    didSet {
      if oldValue != provider {
        importedProfile = nil
        confirmedSelection = false
      }
    }
  }
  @Published var address = ""
  @Published var deviceID = "" {
    didSet {
      if oldValue != deviceID {
        importedProfile = nil
        confirmedSelection = false
      }
    }
  }
  @Published var serviceHost = "" {
    didSet { if oldValue != serviceHost { confirmedSelection = false } }
  }
  @Published var peerIP = "" {
    didSet {
      if oldValue != peerIP {
        importedProfile = nil
        confirmedSelection = false
      }
    }
  }
  @Published var devices: [TargetDevice] = []
  @Published var serviceHosts: [String] = []
  @Published var peers: [SelectedNetworkPeer] = []
  @Published var importedProfile: DeviceProfile?
  @Published var isWorking = false
  @Published var isLoadingPeers = false
  @Published var error: String?
  @Published var discoveryStatus = "Looking for devices…"
  var onSaved: (() -> Void)?
  var onExistingPairing: (() -> Void)?
  var onInitialPairing: (() -> Void)?
  var onCheckConnection: (() -> Void)?
  var onRefresh: (() -> Void)?
  var onClose: (() -> Void)?
  var onImport: (() -> Void)?
  var onShowSkill: (() -> Void)?
  private let queue = DispatchQueue(label: "debagr.device-setup")
  private var discoveryGeneration = 0

  init(configured: ConfiguredDevice?) {
    self.configured = configured
    if let configured {
      provider = NetworkProvider(rawValue: configured.profile.provider) ?? .tailscale
      address = provider.discoversPeers ? "" : configured.profile.peerIP
      deviceID = configured.deviceIdentifier
      peerIP = configured.profile.peerIP
      importedProfile = configured.profile
      confirmedSelection = true
    }
  }

  func updateDevices(_ inventory: [TargetDevice], services: [BonjourDevice], status: String) {
    devices = inventory.filter { $0.identity.source == .appleIdentifier }
    if let configured,
      !devices.contains(where: { $0.identity.value == configured.deviceIdentifier })
    {
      devices.append(
        TargetDevice(
          identity: .apple(pairedMacNodeID: "local", identifier: configured.deviceIdentifier),
          displayName: configured.displayName, kind: configured.kind ?? .unknown, service: nil,
          status: .unavailable))
    }
    serviceHosts = Array(
      Set(
        services.filter {
          !$0.hostName.hasPrefix("debagr-") && !$0.txt.isEmpty
        }.map(\.hostName))
    ).sorted()
    discoveryStatus = status
    if deviceID.isEmpty, devices.count == 1 { deviceID = devices[0].identity.value }
    if serviceHost.isEmpty {
      serviceHost = serviceHosts.count == 1 ? serviceHosts[0] : ""
    }
  }

  var canSave: Bool {
    confirmedSelection && hasConnectionSelection
  }

  var hasConnectionSelection: Bool {
    path == .existing && hasSelectedDevice
      && peers.contains { $0.ipAddress == peerIP }
      && (importedProfile != nil || serviceHosts.contains(serviceHost))
  }

  var addressValidationMessage: String? {
    guard !provider.discoversPeers, !address.isEmpty,
      !provider.allowsAddress(address.trimmingCharacters(in: .whitespacesAndNewlines))
    else { return nil }
    return
      "Enter this device's private VPN IPv4 address, for example 10.20.0.2. Public and IPv6 addresses are unsupported."
  }

  func refreshDeveloperTools() {
    queue.async { [weak self] in
      let available = ProductSupport.developerToolsAvailable
      DispatchQueue.main.async { [weak self] in self?.developerToolsAvailable = available }
    }
  }

  var hasSelectedDevice: Bool { devices.contains { $0.identity.value == deviceID } }

  var selectedDeviceName: String {
    devices.first { $0.identity.value == deviceID }?.displayName ?? "Your iPhone or iPad"
  }

  var canContinue: Bool {
    path == .existing && !isWorking
      && (step == .device ? hasSelectedDevice : step == .network ? hasConnectionSelection : canSave)
  }

  func selectPath(_ path: ConnectionPath) {
    guard !isWorking else { return }
    guard path != self.path else { return }
    guard self.path != .usbIP || initialPairing?.canLeave != false else {
      error = "Stop the temporary USB/IP connection before switching paths."
      return
    }
    error = nil
    if path == .usbIP, let onInitialPairing {
      onInitialPairing()
    } else if path == .existing, let onExistingPairing {
      onExistingPairing()
    } else {
      self.path = path
    }
  }

  func advance() {
    guard canContinue else { return }
    switch step {
    case .device: step = .network
    case .network: step = .review
    case .review: save()
    }
  }

  func updateVerification(device: ConfiguredDevice?, result: Result<String, Error>) {
    guard page == .saved, let device, configured?.hasSameConnection(as: device) == true
    else { return }
    guard device.enabled else {
      verification = .attention("Choose Resume Wireless Connection in the Debagr menu.")
      return
    }
    switch result {
    case .success(let title): verification = .ready(title)
    case .failure(let error):
      let failure = AgentCLI.failure(error, operation: "status").object["error"] as? [String: Any]
      verification = .attention(failure?["recovery"] as? String ?? error.localizedDescription)
    }
  }

  func loadPeers() {
    guard !isWorking else { return }
    discoveryGeneration += 1
    let generation = discoveryGeneration
    let provider = provider
    error = nil
    peers = []
    if !provider.discoversPeers {
      isLoadingPeers = false
      updateManualPeer()
      return
    }
    isLoadingPeers = true
    queue.async { [weak self] in
      let result = Result { try TailscaleClient().onlinePeers(provider: provider) }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.discoveryGeneration == generation, self.provider == provider else {
          return
        }
        self.isLoadingPeers = false
        switch result {
        case .success(let peers):
          self.peers = peers.sorted {
            let left =
              $0.hostname.lowercased().contains("iphone")
              || $0.hostname.lowercased().contains("ipad")
            let right =
              $1.hostname.lowercased().contains("iphone")
              || $1.hostname.lowercased().contains("ipad")
            return left != right ? left : $0.hostname < $1.hostname
          }
          if let configured = self.configured, configured.profile.provider == provider.rawValue,
            !self.peers.contains(where: { $0.ipAddress == configured.profile.peerIP })
          {
            self.peers.append(
              SelectedNetworkPeer(
                hostname: configured.displayName,
                dnsName: configured.peerName, ipAddress: configured.profile.peerIP, online: false))
          }
          if !self.peers.contains(where: { $0.ipAddress == self.peerIP }) {
            let selectedName = self.devices.first { $0.identity.value == self.deviceID }?
              .displayName
            let matches = peers.filter {
              $0.hostname.localizedCaseInsensitiveCompare(selectedName ?? "") == .orderedSame
            }
            self.peerIP =
              matches.count == 1
              ? matches[0].ipAddress : (peers.count == 1 ? peers[0].ipAddress : "")
          }
          if peers.isEmpty {
            self.error =
              "No online devices found. Connect both devices to your private network, unlock the target device, and retry."
          }
        case .failure(let error): self.error = error.localizedDescription
        }
      }
    }
  }

  func updateManualPeer() {
    guard !provider.discoversPeers, !isWorking else { return }
    let ip = address.trimmingCharacters(in: .whitespacesAndNewlines)
    if provider.allowsAddress(ip), let peer = try? provider.resolvePeer(ip) {
      peers = [peer]
      peerIP = ip
    } else {
      peers = []
      peerIP = ""
    }
  }

  nonisolated static func configuration(
    device: TargetDevice, provider: NetworkProvider, peer: SelectedNetworkPeer,
    profile: DeviceProfile
  ) throws -> ConfiguredDevice {
    guard device.identity.source == .appleIdentifier,
      profile.provider == provider.rawValue, profile.peerIP == peer.ipAddress
    else { throw CLIError.invalidDirectDeviceOptions }
    let configured = ConfiguredDevice(
      deviceIdentifier: device.identity.value, displayName: device.displayName,
      peerName: peer.dnsName.isEmpty ? peer.ipAddress : peer.dnsName,
      profile: profile, kind: device.kind)
    try configured.validate()
    return configured
  }

  func removeDevice() {
    guard !isWorking else { return }
    do {
      try ManagedDeviceStore().remove()
      configured = nil
      importedProfile = nil
      deviceID = ""
      peerIP = ""
      onSaved?()
    } catch { self.error = error.localizedDescription }
  }

  func save() {
    guard !isWorking, canSave,
      let device = devices.first(where: { $0.identity.value == deviceID }),
      let peer = peers.first(where: { $0.ipAddress == peerIP })
    else { return }
    let provider = provider
    let host = serviceHost
    let imported = importedProfile
    error = nil
    isWorking = true
    queue.async { [weak self] in
      let result = Result {
        let profile =
          try imported
          ?? DirectDeviceApplication.capturedProfile(
            peerName: peer.dnsName.isEmpty ? peer.ipAddress : peer.dnsName,
            host: host, timeout: 8, provider: provider)
        let configured = try Self.configuration(
          device: device, provider: provider, peer: peer, profile: profile)
        try ManagedDeviceStore().save(configured)
        return configured
      }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isWorking = false
        switch result {
        case .success(let configured):
          self.configured = configured
          self.verification = .checking
          self.page = .saved
          self.onSaved?()
        case .failure(let error): self.error = error.localizedDescription
        }
      }
    }
  }
}

final class DeviceSetupWindowController: NSWindowController, NSWindowDelegate {
  let model: DeviceSetupModel

  init(configured: ConfiguredDevice?) {
    model = DeviceSetupModel(configured: configured)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 980, height: 860),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = "Debagr · Connections"
    window.contentMinSize = NSSize(width: 880, height: 740)
    window.isReleasedWhenClosed = false
    let hosting = NSHostingView(rootView: DeviceSetupView(model: model))
    hosting.sizingOptions = []
    window.contentView = hosting
    window.center()
    super.init(window: window)
    window.delegate = self
    model.onClose = { [weak self] in self?.close() }
    model.onImport = { [weak self] in self?.importProfile() }
  }

  required init?(coder: NSCoder) { return nil }

  func present(page: DeviceSetupModel.Page) {
    if !model.isWorking {
      model.page = page
      model.error = nil
    }
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool { !model.isWorking }

  private func importProfile() {
    guard let window, !model.isWorking else { return }
    let panel = NSOpenPanel()
    panel.message = "Choose the saved Debagr profile for this device and VPN."
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self, response == .OK, let url = panel.url else { return }
      do {
        guard let profile = try ProfileStore(url: url).load(),
          profile.provider == self.model.provider.rawValue, profile.peerIP == self.model.peerIP
        else { throw CLIError.invalidDirectDeviceOptions }
        self.model.importedProfile = profile
        self.model.error = nil
      } catch { self.model.error = error.localizedDescription }
    }
  }
}

enum SettingsStyle {
  static let accent = Color(red: 0.09, green: 0.39, blue: 0.94)
  static let surface = Color(nsColor: .textBackgroundColor)
  static let border = Color(nsColor: .separatorColor).opacity(0.5)
}

struct DeviceSetupView: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    VStack(spacing: 0) {
      NavigationSplitView {
        SettingsSidebar(model: model)
          .navigationSplitViewColumnWidth(min: 190, ideal: 190, max: 190)
      } detail: {
        VStack(spacing: 0) {
          switch model.page {
          case .preferences: DebagrPreferencesView()
          case .guide: AgentToolsView(model: model)
          case .setup: DeviceConnectionView(model: model)
          case .saved: SetupSavedView(model: model)
          }
          if let error = model.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(.callout).foregroundStyle(.red).textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(16).background(Color.red.opacity(0.06))
          }
          if model.page == .setup {
            ConnectionActionBar {
              if model.path == .usbIP, let presentation = model.initialPairing {
                InitialPairingActions(presentation: presentation)
              } else {
                ConnectionActions(model: model)
              }
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsStyle.surface)
      }
      .navigationSplitViewStyle(.balanced)
      Divider()
      HStack(spacing: 8) {
        Image(systemName: "info.circle")
        Text(
          model.path == .usbIP
            ? "Start USB sharing on the cable Mac, then attach the device on the Builder."
            : model.path == .usb
              ? "Builder: this Mac · Keep USB connected to the cable Mac · Both Macs need Tailscale."
              : "Builder: this Mac · Keep Debagr running · Wireless deployment requires device Wi-Fi + VPN."
        )
        Spacer(minLength: 0)
      }
      .font(.system(size: 11)).foregroundStyle(.secondary)
      .padding(.horizontal, 16).padding(.vertical, 11)
      .background(SettingsStyle.surface)
    }
    .onAppear { model.refreshDeveloperTools() }
    .tint(SettingsStyle.accent)
    .frame(minWidth: 800, minHeight: 640)
  }
}

private struct DebagrMark: View {
  var body: some View {
    HStack(spacing: 9) {
      Image(systemName: "antenna.radiowaves.left.and.right")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(SettingsStyle.surface)
        .frame(width: 29, height: 29)
        .background(Color.primary, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityHidden(true)
      Text("Debagr").font(.system(size: 15, weight: .semibold))
    }
  }
}

struct SettingsSidebar: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      DebagrMark().padding(.horizontal, 20).padding(.top, 25)
      VStack(spacing: 6) {
        SettingsNavigationItem(
          title: "Connection", symbol: "point.3.connected.trianglepath.dotted",
          isSelected: model.page == .setup || model.page == .saved
        ) {
          model.page = .setup
          model.error = nil
        }
        SettingsNavigationItem(
          title: "Agent tools", symbol: "terminal",
          isSelected: model.page == .guide
        ) {
          model.page = .guide
          model.error = nil
        }
        SettingsNavigationItem(
          title: "Preferences", symbol: "gearshape",
          isSelected: model.page == .preferences
        ) {
          model.page = .preferences
          model.error = nil
        }
      }
      .padding(.horizontal, 12).disabled(model.isWorking)
      Spacer(minLength: 0)
      VStack(alignment: .leading, spacing: 6) {
        Text(model.page == .guide ? "Built for your workflow" : "Technical preview")
          .font(.system(size: 11, weight: .medium))
        Text(
          model.page == .guide
            ? "Claude Code, Codex,\nor your terminal." : "Your device, wherever\nyou build."
        )
        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
      }
      .padding(.horizontal, 20).padding(.bottom, 24)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

private struct SettingsNavigationItem: View {
  let title: String
  let symbol: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 10)
        .foregroundStyle(Color.primary)
        .background(
          isSelected ? SettingsStyle.accent.opacity(0.09) : Color.clear,
          in: RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain).accessibilityValue(isSelected ? "Selected" : "")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

struct SettingsHeading: View {
  let eyebrow: String
  var experimental = false
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Text(eyebrow.uppercased())
          .font(.system(size: 10, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary)
        if experimental { ExperimentalBadge() }
      }
      Text(title).font(.system(size: 28, weight: .semibold)).tracking(-0.7)
        .fixedSize(horizontal: false, vertical: true)
      Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct ConnectionField<Content: View>: View {
  let symbol: String
  @ViewBuilder var content: Content

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(.secondary)
        .frame(width: 20).accessibilityHidden(true)
      content
    }
    .padding(12)
    .background(SettingsStyle.surface, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsStyle.border, lineWidth: 1))
  }
}

struct SettingsBadge: View {
  let text: String

  var body: some View {
    Text(text).font(.system(size: 10, weight: .medium))
      .padding(.horizontal, 7).padding(.vertical, 5)
      .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
  }
}

private struct DeviceConnectionView: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        SettingsHeading(
          eyebrow: "Connection setup", experimental: model.path != .existing,
          title: model.path == .usbIP
            ? "Pair this device with a remote Builder."
            : model.path == .usb
              ? "Use your iPhone through another Mac." : "Deploy to your iPhone over Wi-Fi.",
          subtitle: model.path == .usbIP
            ? "Use a temporary USB/IP connection for the Apple Trust prompt on your iPhone or iPad."
            : model.path == .usb
              ? "Forward the services of an already paired phone over its USB cable and your private VPN."
              : "This Mac builds and deploys. Your paired iPhone can be on another Wi-Fi network.")
        ConnectionPathPicker(selection: Binding(get: { model.path }, set: { model.selectPath($0) }))
        if model.path == .usb {
          Label(ConnectionPath.usbRequirements, systemImage: "exclamationmark.triangle")
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if model.path == .usbIP {
          Text(
            "Requires a compatible USB/IP tool and administrator approval on each Mac. The experimental importer requires access to a virtual USB controller on the Builder."
          )
          .font(.callout).foregroundStyle(.secondary)
          if let presentation = model.initialPairing {
            InitialPairingContent(presentation: presentation)
          }
        } else {
          ConnectionDiagram(path: model.path, deviceName: model.selectedDeviceName)
        }
        if model.path == .existing {
          ConnectionProgress(step: model.step)
          switch model.step {
          case .device:
            if let configured = model.configured {
              Text("Saved device: \(configured.displayName)").font(.headline)
              Text("\(configured.profile.provider) · \(configured.profile.peerIP)").foregroundStyle(
                .secondary)
              Button("Remove saved device", role: .destructive) { model.removeDevice() }
            }
            if model.developerToolsAvailable == false {
              Text("Install Xcode and select its developer tools before pairing or discovery.")
            }
            TargetSelection(model: model)
            PairingLocationGuide()
            Button("Refresh devices") { model.onRefresh?() }.buttonStyle(.link)
            Text(model.discoveryStatus).font(.caption).foregroundStyle(.secondary)
          case .network:
            NetworkSelection(model: model)
            NearbyConnection(model: model)
          case .review:
            ConnectionReview(model: model)
            Text(
              "Confirm that the paired device, nearby service and VPN selection all belong to the same physical device. Names are hints, not proof of identity."
            )
            .font(.caption).foregroundStyle(.secondary)
            Toggle(
              "These selections refer to the same physical device", isOn: $model.confirmedSelection)
          }
        } else if model.path == .usb {
          CableSharingSetupView()
        }
      }
      .frame(maxWidth: 660, alignment: .leading)
      .padding(20).frame(maxWidth: .infinity, alignment: .leading)
    }
    .disabled(model.isWorking)
    .id("\(model.path.rawValue)-\(model.step.rawValue)")
  }
}

private struct NetworkSelection: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Connect the iPhone and Builder to the same private VPN")
        .font(.system(size: 13, weight: .semibold))
      ConnectionField(symbol: "checkmark.shield") {
        Picker("Private network", selection: $model.provider) {
          ForEach(NetworkProvider.allCases, id: \.rawValue) { provider in
            Text(provider.displayName).tag(provider)
          }
        }
        .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
      }
      if model.provider.discoversPeers {
        ConnectionField(symbol: "network") {
          Picker("iPhone or iPad on your VPN", selection: $model.peerIP) {
            Text(model.isLoadingPeers ? "Finding devices…" : "Choose your iPhone or iPad…").tag("")
            ForEach(model.peers, id: \.ipAddress) { peer in
              Text("\(peer.hostname) · \(peer.ipAddress)").tag(peer.ipAddress)
            }
          }
          .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
          .disabled(model.isLoadingPeers || model.peers.isEmpty)
        }
      } else {
        ConnectionField(symbol: "network") {
          TextField("Device VPN IPv4 address", text: $model.address, prompt: Text("e.g. 10.20.0.2"))
            .textFieldStyle(.plain)
        }
      }
      if let validation = model.addressValidationMessage {
        Text(validation).font(.caption).foregroundStyle(.red).accessibilityLabel(validation)
      }
      Text(
        model.provider == .tailscale
          ? "Choose \(model.selectedDeviceName) on the VPN, not another Mac. Keep the device on Wi-Fi."
          : "Choose the target device's VPN address. This provider still needs full hardware validation."
      )
      .font(.system(size: 11)).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .onAppear { model.loadPeers() }
    .onChange(of: model.provider) { _ in model.loadPeers() }
    .onChange(of: model.address) { _ in model.updateManualPeer() }
  }
}

private struct TargetSelection: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Which device is paired with this Builder?")
        .font(.system(size: 13, weight: .semibold))
      ConnectionField(symbol: "rectangle.portrait") {
        Picker("Remote device", selection: $model.deviceID) {
          Text("Choose a paired device…").tag("")
          ForEach(model.devices) { device in
            Text("\(device.displayName) · \(device.kind.displayName)").tag(device.identity.value)
          }
        }
        .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
        if model.devices.contains(where: { $0.identity.value == model.deviceID }) {
          SettingsBadge(text: "Known to this Mac")
        }
      }
      Text(
        model.devices.isEmpty
          ? "No paired devices found. Connect by USB, grant trust, then refresh."
          : "Apple trust stays on this Mac. Debagr relays its connection when your device moves away."
      )
      .font(.system(size: 11)).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct NearbyConnection: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Remember this device's wireless service")
        .font(.system(size: 13, weight: .semibold))
      ConnectionField(symbol: "wifi") {
        Picker("Local device service", selection: $model.serviceHost) {
          Text("Choose a nearby service…").tag("")
          ForEach(model.serviceHosts, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
        .disabled(model.importedProfile != nil)
      }
      Text(
        "Capture once while nearby, or use a saved Debagr connection profile if already remote. A profile does not transfer Apple trust."
      )
      .font(.system(size: 11)).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 12) {
        Button("Use Saved Profile…") { model.onImport?() }.disabled(model.peerIP.isEmpty)
        if model.importedProfile != nil {
          Label("Profile loaded", systemImage: "checkmark.circle").foregroundStyle(.secondary)
          Button("Remove") { model.importedProfile = nil }
        }
        Spacer(minLength: 0)
        Button("Refresh") {
          model.onRefresh?()
          model.loadPeers()
        }
        .disabled(model.isLoadingPeers)
      }
      .buttonStyle(.link).font(.system(size: 11))
    }
  }
}

private struct ConnectionReview: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Ready to check the connection").font(.headline)
      LabeledContent("Builder", value: "This Mac · owns the Apple pairing")
      LabeledContent("Target device", value: model.selectedDeviceName)
      LabeledContent("Private network", value: model.provider.displayName)
      LabeledContent("Device address", value: model.peerIP)
      LabeledContent(
        "Wireless service",
        value: model.importedProfile == nil ? model.serviceHost : "Saved connection profile")
      Divider()
      Label("Unlock your device and keep Wi-Fi, VPN, and Developer Mode on.", systemImage: "iphone")
      Text(
        "Debagr will save this setup and check trusted connectivity and lock state. Installation and launch are confirmed separately when you deploy an app."
      )
      .foregroundStyle(.secondary)
      if !model.hasConnectionSelection {
        Label(
          "A selection is no longer available. Go back to choose the device or connection again.",
          systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.orange)
      }
    }
    .font(.callout).textSelection(.enabled)
  }
}

private struct ConnectionActions: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    HStack(spacing: 12) {
      if model.path == .usb {
        Text("Use the cable bridge CLI to start and stop sharing.").font(.caption).foregroundStyle(
          .secondary)
        Spacer(minLength: 0)
      } else {
        if model.step != .device {
          Button("Back") { model.step = model.step == .review ? .network : .device }
            .disabled(model.isWorking)
        }
        if model.isWorking {
          ProgressView().controlSize(.small)
        }
        Text(
          model.isWorking
            ? "Saving connection…" : "Step \(model.step.rawValue + 1) of 3"
        )
        .font(.system(size: 11)).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Button {
          model.advance()
        } label: {
          HStack {
            Text(model.step == .review ? "Save & check connection" : "Continue")
            Image(systemName: "arrow.right").accessibilityHidden(true)
          }
        }
        .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        .disabled(!model.canContinue)
      }
    }
  }
}

private struct AgentToolsView: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        SettingsHeading(
          eyebrow: "Debagr skill",
          title: "Give your agent\na way to your device.",
          subtitle: "The build and deployment run on your Mac.\nYou only need your device with you."
        )
        AgentStep(
          number: "1", title: "On your Builder",
          detail:
            "Install Debagr and Xcode. Pair over USB, grant trust, enable Developer Mode, and connect your VPN."
        )
        VStack(alignment: .leading, spacing: 10) {
          AgentStep(
            number: "2", title: "Where your coding agent runs",
            detail:
              "Install the Debagr skill through your agent’s plugin. It runs where your coding agent runs, with access to the Builder."
          )
          HStack(spacing: 8) {
            Link(
              destination: URL(
                string: "https://github.com/radeknovis/homebrew-debagr/releases"
              )!
            ) {
              Label("Claude Code", systemImage: "terminal")
            }
            Link(
              destination: URL(
                string: "https://github.com/radeknovis/homebrew-debagr/releases")!
            ) {
              Label("Codex", systemImage: "terminal")
            }
            SettingsBadge(text: "CLI also available")
          }
          .controlSize(.small).buttonStyle(.bordered).padding(.leading, 35)
          Button("Open Debagr skill…") { model.onShowSkill?() }
            .buttonStyle(.link).font(.system(size: 11)).padding(.leading, 35)
        }
        AgentStep(
          number: "3", title: "Ask your agent naturally",
          detail:
            "The Debagr skill teaches your agent how to find your device, check its connection, and install and launch a build. Tell it which Builder to use and what you want to run."
        )
        VStack(alignment: .leading, spacing: 8) {
          Text("Try a request like this").font(.headline)
          Text("Use Debagr on my Builder to install and launch /path/to/MyApp.app on my iPhone.")
            .font(.callout).textSelection(.enabled)
          Text("Use your Builder’s SSH alias and the signed app’s path on that Mac.")
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        Text("Current target devices: iPhone and iPad. Mac targets are not implemented.")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      .frame(maxWidth: 660, alignment: .leading)
      .padding(32).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct AgentStep: View {
  let number: String
  let title: String
  let detail: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(number).font(.system(size: 11, weight: .medium))
        .frame(width: 23, height: 23)
        .background(Color.primary.opacity(0.06), in: Circle())
      VStack(alignment: .leading, spacing: 7) {
        Text(title).font(.system(size: 13, weight: .semibold))
        Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct SetupSavedView: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        SettingsHeading(
          eyebrow: "Connection saved", title: model.verification.title,
          subtitle: model.verification.detail)
        ConnectionDiagram(path: .existing, deviceName: model.selectedDeviceName)
        if let configured = model.configured {
          VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Deploys from", value: "This Mac · Builder")
            LabeledContent("Device", value: configured.displayName)
            LabeledContent(
              "Private VPN",
              value: "\(model.provider.displayName) · \(configured.profile.peerIP)")
          }
          .font(.callout).textSelection(.enabled)
          .padding(16)
          .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }
        Label("Connection profile saved on this Mac", systemImage: "checkmark.circle.fill")
        if case .checking = model.verification {
          HStack {
            ProgressView().controlSize(.small)
            Text("Checking Apple connectivity and device lock state…")
          }
        } else {
          Label(model.verification.title, systemImage: model.verification.symbol)
        }
        Label("App installation · checked on your next deployment", systemImage: "circle.dotted")
        Label("App launch · confirmed after installation", systemImage: "circle.dotted")
        Text(
          "A local connection can also pass this check. Before relying on roaming, deploy once with the iPhone on another Wi-Fi network."
        )
        .font(.callout).foregroundStyle(.secondary)
        HStack {
          Button("Edit connection") {
            model.page = .setup
            model.step = .device
          }
          Spacer()
          if case .ready = model.verification {
            Button("Check again", action: checkAgain)
            Button("Agent tools") { model.page = .guide }
              .buttonStyle(.borderedProminent).controlSize(.large)
          } else {
            Button("Check again", action: checkAgain)
              .buttonStyle(.borderedProminent).controlSize(.large)
              .disabled(model.verification == .checking)
          }
        }
      }
      .padding(32).frame(maxWidth: 740, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func checkAgain() {
    model.verification = .checking
    model.onCheckConnection?()
  }
}
