import AppKit
import SwiftUI

final class DeviceSetupModel: ObservableObject {
  enum Page { case guide, setup, saved }

  @Published var page = Page.setup
  @Published var provider = NetworkProvider.tailscale
  @Published var address = ""
  @Published var deviceID = ""
  @Published var serviceHost = ""
  @Published var peerIP = "" {
    didSet {
      if oldValue != peerIP { importedProfile = nil }
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
  var onRefresh: (() -> Void)?
  var onClose: (() -> Void)?
  var onImport: (() -> Void)?
  var onShowSkill: (() -> Void)?
  private let queue = DispatchQueue(label: "debagr.device-setup")
  private var discoveryGeneration = 0

  init(configured: ConfiguredDevice?) {
    if let configured {
      provider = NetworkProvider(rawValue: configured.profile.provider) ?? .tailscale
      address = provider.discoversPeers ? "" : configured.profile.peerIP
      deviceID = configured.deviceIdentifier
      peerIP = configured.profile.peerIP
    }
  }

  func updateDevices(_ inventory: [TargetDevice], services: [BonjourDevice], status: String) {
    devices = inventory.filter { $0.identity.source == .appleIdentifier }
    serviceHosts = Array(
      Set(
        services.filter {
          !$0.hostName.hasPrefix("debagr-") && !$0.txt.isEmpty
        }.map(\.hostName))
    ).sorted()
    discoveryStatus = status
    if deviceID.isEmpty, devices.count == 1 { deviceID = devices[0].identity.value }
    if !serviceHosts.contains(serviceHost) {
      serviceHost = serviceHosts.count == 1 ? serviceHosts[0] : ""
    }
  }

  var canSave: Bool {
    devices.contains { $0.identity.value == deviceID }
      && peers.contains { $0.ipAddress == peerIP }
      && (importedProfile != nil || serviceHosts.contains(serviceHost))
  }

  var deploymentPrompt: String {
    let target = deviceID.isEmpty ? "my target device" : "device \(deviceID)"
    return
      "Use Debagr on my build Mac to check \(target)'s readiness, then install and launch /absolute/path/MyApp.app. Confirm installation and launch separately. If blocked, explain the next action."
  }

  func loadPeers() {
    guard !isWorking else { return }
    discoveryGeneration += 1
    let generation = discoveryGeneration
    let provider = provider
    error = nil
    importedProfile = nil
    peers = []
    if !provider.discoversPeers {
      isLoadingPeers = false
      updateManualPeer()
      return
    }
    isLoadingPeers = true
    queue.async { [weak self] in
      let result = Result { try TailscaleClient().onlinePeers(provider: provider) }
      DispatchQueue.main.async {
        guard let self, self.discoveryGeneration == generation, self.provider == provider else {
          return
        }
        self.isLoadingPeers = false
        switch result {
        case .success(let peers):
          self.peers = peers
          if !peers.contains(where: { $0.ipAddress == self.peerIP }) {
            self.peerIP = peers.count == 1 ? peers[0].ipAddress : ""
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

  static func configuration(
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
      }
      DispatchQueue.main.async {
        guard let self else { return }
        self.isWorking = false
        switch result {
        case .success:
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
      contentRect: NSRect(x: 0, y: 0, width: 840, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = "Debagr Settings"
    window.contentMinSize = NSSize(width: 800, height: 640)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: DeviceSetupView(model: model))
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

private enum SettingsStyle {
  static let accent = Color(red: 0.09, green: 0.39, blue: 0.94)
  static let surface = Color(nsColor: .textBackgroundColor)
  static let border = Color(nsColor: .separatorColor).opacity(0.5)
}

private struct DeviceSetupView: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    VStack(spacing: 0) {
      NavigationSplitView {
        SettingsSidebar(model: model)
          .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 210)
      } detail: {
        VStack(spacing: 0) {
          switch model.page {
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
          if model.page == .setup { ConnectionActions(model: model) }
        }
        .background(SettingsStyle.surface)
      }
      .navigationSplitViewStyle(.balanced)
      Divider()
      HStack(spacing: 8) {
        Image(systemName: "info.circle")
        Text("Keep this Mac running. Device Wi-Fi is required; cellular-only is unsupported.")
        Spacer(minLength: 0)
      }
      .font(.system(size: 11)).foregroundStyle(.secondary)
      .padding(.horizontal, 16).padding(.vertical, 11)
      .background(SettingsStyle.surface)
    }
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

private struct SettingsSidebar: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      DebagrMark().padding(.horizontal, 20).padding(.top, 25)
      VStack(spacing: 6) {
        SettingsNavigationItem(
          title: "Device setup", symbol: "iphone",
          isSelected: model.page != .guide
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
      }
      .padding(.horizontal, 12).disabled(model.isWorking)
      Spacer(minLength: 0)
      VStack(alignment: .leading, spacing: 6) {
        Text(model.page == .guide ? "Built for your workflow" : "Technical preview")
          .font(.system(size: 11, weight: .medium))
        Text(
          model.page == .guide
            ? "Claude Code, Codex,\nor your terminal." : "One Mac.\nOne remote device."
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
        .foregroundStyle(isSelected ? SettingsStyle.accent : Color.primary)
        .background(
          isSelected ? SettingsStyle.accent.opacity(0.09) : Color.clear,
          in: RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain).accessibilityValue(isSelected ? "Selected" : "")
  }
}

private struct SettingsHeading: View {
  let eyebrow: String
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(eyebrow.uppercased())
        .font(.system(size: 10, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary)
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

private struct SettingsBadge: View {
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
      VStack(alignment: .leading, spacing: 20) {
        SettingsHeading(
          eyebrow: "A little setup. A lot of freedom.",
          title: "Your Mac stays home.\nYour next build comes with you.",
          subtitle: "Connect your paired device over a private VPN.")
        NetworkSelection(model: model)
        TargetSelection(model: model)
        NearbyConnection(model: model)
        Divider()
        ConnectionChecklist(model: model)
      }
      .frame(maxWidth: 660, alignment: .leading)
      .padding(32).frame(maxWidth: .infinity, alignment: .leading)
    }
    .disabled(model.isWorking)
    .onAppear { model.loadPeers() }
    .onChange(of: model.provider) { _ in model.loadPeers() }
    .onChange(of: model.address) { _ in model.updateManualPeer() }
  }
}

private struct NetworkSelection: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Private network").font(.system(size: 12, weight: .medium))
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
          Picker("VPN device", selection: $model.peerIP) {
            Text(model.isLoadingPeers ? "Finding devices…" : "Choose a VPN device…").tag("")
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
      Text(
        model.provider == .tailscale
          ? "Remote iPhone deployment verified over Tailscale. Choose the same target device in both lists."
          : "Connect both devices to this VPN first. This provider still needs full hardware validation."
      )
      .font(.system(size: 11)).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct TargetSelection: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Remote device").font(.system(size: 12, weight: .medium))
      ConnectionField(symbol: "rectangle.portrait") {
        Picker("Remote device", selection: $model.deviceID) {
          Text("Choose a paired device…").tag("")
          ForEach(model.devices) { device in
            Text("\(device.displayName) · \(device.kind.displayName)").tag(device.identity.value)
          }
        }
        .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
        if model.devices.contains(where: { $0.identity.value == model.deviceID }) {
          SettingsBadge(text: "Paired")
        }
      }
      Text(
        model.devices.isEmpty
          ? "No paired devices found. Connect by USB, grant trust, then refresh."
          : "One managed device · Pair over USB on this Mac first."
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
      Text("Nearby connection").font(.system(size: 12, weight: .medium))
      ConnectionField(symbol: "wifi") {
        Picker("Local device service", selection: $model.serviceHost) {
          Text("Choose a nearby service…").tag("")
          ForEach(model.serviceHosts, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
        .disabled(model.importedProfile != nil)
      }
      Text("Select the same device's local service once, before taking it to another network.")
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

private struct ConnectionChecklist: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    let selected = model.devices.contains { $0.identity.value == model.deviceID }
    VStack(alignment: .leading, spacing: 12) {
      Label {
        Text("This Mac is running Debagr")
      } icon: {
        Image(systemName: "checkmark.circle").foregroundStyle(.green)
      }
      Label {
        Text(
          selected ? "A paired target device is selected" : "Select a device paired with this Mac")
      } icon: {
        Image(systemName: selected ? "checkmark.circle" : "circle")
          .foregroundStyle(selected ? Color.green : Color.secondary)
      }
      Label("Connection readiness is verified after saving", systemImage: "circle.dotted")
        .foregroundStyle(.secondary)
    }
    .font(.system(size: 12))
  }
}

private struct ConnectionActions: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    HStack(spacing: 12) {
      if model.isWorking || model.isLoadingPeers {
        ProgressView().controlSize(.small)
      }
      Text(
        model.isWorking
          ? "Saving setup…"
          : model.isLoadingPeers
            ? "Finding devices…"
            : model.canSave ? "Selections complete" : "Choose your device and connection"
      )
      .font(.system(size: 11)).foregroundStyle(.secondary)
      Spacer(minLength: 0)
      Button {
        model.save()
      } label: {
        HStack {
          Text("Connect device")
          Image(systemName: "arrow.right").accessibilityHidden(true)
        }
      }
      .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
      .disabled(model.isWorking || !model.canSave)
    }
    .padding(.horizontal, 32).padding(.vertical, 18)
  }
}

private struct AgentToolsView: View {
  @ObservedObject var model: DeviceSetupModel
  @State private var copied = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        SettingsHeading(
          eyebrow: "From prompt to pocket",
          title: "Let your agent\nhandle the handoff.",
          subtitle: "The build and deployment run on your Mac.\nYou only need your device with you."
        )
        AgentStep(
          number: "1", title: "On your build Mac",
          detail:
            "Install Debagr and Xcode. Pair over USB, grant trust, enable Developer Mode, and connect your VPN."
        )
        VStack(alignment: .leading, spacing: 10) {
          AgentStep(
            number: "2", title: "Where your coding agent runs",
            detail: "Install the matching Debagr plugin. Give your agent access to the build Mac.")
          HStack(spacing: 8) {
            Link(
              destination: URL(
                string: "https://github.com/radeknovis/Debagr/blob/main/docs/PLUGINS.md#claude-code"
              )!
            ) {
              Label("Claude Code", systemImage: "terminal")
            }
            Link(
              destination: URL(
                string: "https://github.com/radeknovis/Debagr/blob/main/docs/PLUGINS.md#codex")!
            ) {
              Label("Codex", systemImage: "terminal")
            }
            SettingsBadge(text: "CLI also available")
          }
          .controlSize(.small).buttonStyle(.bordered).padding(.leading, 35)
          Button("Show bundled deployment skill…") { model.onShowSkill?() }
            .buttonStyle(.link).font(.system(size: 11)).padding(.leading, 35)
        }
        VStack(alignment: .leading, spacing: 10) {
          AgentStep(
            number: "3", title: "Ask for your next build",
            detail:
              "Example agent prompt · Supply your build Mac's SSH alias and replace the app path.")
          VStack(alignment: .leading, spacing: 12) {
            Text(model.deploymentPrompt)
              .font(.system(size: 11, design: .monospaced)).lineSpacing(6)
              .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(14)
              .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsStyle.border, lineWidth: 1))
            Button {
              let pasteboard = NSPasteboard.general
              pasteboard.clearContents()
              copied = pasteboard.setString(model.deploymentPrompt, forType: .string)
            } label: {
              Label(
                copied ? "Prompt copied" : "Copy deployment prompt",
                systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
          }
          .padding(.leading, 35)
        }
        Text("Current target devices: iPhone and iPad. Mac targets are not implemented.")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      .frame(maxWidth: 660, alignment: .leading)
      .padding(32).frame(maxWidth: .infinity, alignment: .leading)
    }
    .onChange(of: model.deploymentPrompt) { _ in copied = false }
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
    VStack(spacing: 18) {
      Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
      Text("Your device setup is saved").font(.title2.weight(.semibold))
      Text(
        "Debagr is checking the connection. Look in the menu bar for device readiness before deploying."
      )
      .multilineTextAlignment(.center).foregroundStyle(.secondary)
      Text(
        "Keep Debagr running on this Mac and the target device unlocked, on Wi-Fi, and connected to its VPN."
      )
      .font(.callout).multilineTextAlignment(.center)
      Button("Done") { model.onClose?() }.keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent).controlSize(.large)
    }
    .padding(48).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
