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
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 740),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = "Debagr — Remote Device"
    window.contentMinSize = NSSize(width: 640, height: 580)
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

private struct DeviceSetupView: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    VStack(spacing: 0) {
      SetupHeader(page: model.page)
      Divider()
      switch model.page {
      case .guide: SetupGuideView()
      case .setup: SetupConnectionForm(model: model)
      case .saved: SetupSavedView()
      }
      if let error = model.error {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.callout).foregroundStyle(.red).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding().background(Color.red.opacity(0.06))
      }
      Divider()
      SetupFooter(model: model)
    }
    .frame(minWidth: 640, minHeight: 580)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

private struct SetupHeader: View {
  let page: DeviceSetupModel.Page

  var body: some View {
    HStack(spacing: 16) {
      Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
        .resizable().scaledToFit().frame(width: 56, height: 56).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        Text(page == .guide ? "Your next build comes with you." : "Set Up Remote Device")
          .font(.title2.weight(.semibold))
        Text("Keep your build Mac at home. Reach your device on another network.")
          .font(.callout).foregroundStyle(.secondary)
        if page == .saved {
          Text("Setup saved").font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(24)
  }
}

private struct SetupGuideView: View {
  var body: some View {
    Form {
      Section("Prepare your build Mac") {
        Label(
          "Install Xcode and pair your device over USB. Enable Developer Mode and grant trust.",
          systemImage: "desktopcomputer")
        Label(
          "Connect both devices through your private VPN. Keep the target nearby for initial setup.",
          systemImage: "network")
      }
      Section("Deploy from another network") {
        Text(
          "Set up the remote device once, then leave Debagr running on this Mac. Enable Launch at Login from the menu if desired."
        )
        Text(
          "Give Claude Code or Codex the deployment skill and this Mac's SSH alias. The agent builds and deploys through this Mac."
        )
      }
      Section("Current requirements") {
        Text(
          "Targets: iPhone and iPad. Mac targets are not implemented. Keep the target unlocked, on Wi-Fi, and connected to its VPN. Cellular-only operation is unsupported."
        )
        Text(
          "If setup fails, check USB trust, Developer Mode, local-network permission, and your VPN's device access rules."
        )
        .foregroundStyle(.secondary)
        if let url = ProductSupport.configuredURL(forInfoKey: "DebagrWebsiteURL") {
          Link("Open full guide", destination: url)
        }
      }
    }
    .formStyle(.grouped)
  }
}

private struct SetupConnectionForm: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    Form {
      SetupNetworkSection(model: model)
      SetupDeviceSections(model: model)
      HStack {
        Text(model.discoveryStatus).foregroundStyle(.secondary)
        Spacer()
        Button("Refresh Devices") {
          model.onRefresh?()
          model.loadPeers()
        }
        .disabled(model.isLoadingPeers)
      }
      .font(.callout)
    }
    .formStyle(.grouped).disabled(model.isWorking)
    .onAppear { model.loadPeers() }
    .onChange(of: model.provider) { _ in model.loadPeers() }
    .onChange(of: model.address) { _ in model.updateManualPeer() }
  }
}

private struct SetupNetworkSection: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    Section {
      Picker("VPN provider", selection: $model.provider) {
        ForEach(NetworkProvider.allCases, id: \.rawValue) { provider in
          Text(provider.displayName).tag(provider)
        }
      }
      if model.provider.discoversPeers {
        Picker("VPN device", selection: $model.peerIP) {
          Text(model.isLoadingPeers ? "Finding devices…" : "Choose a device…").tag("")
          ForEach(model.peers, id: \.ipAddress) { peer in
            Text("\(peer.hostname) · \(peer.ipAddress)").tag(peer.ipAddress)
          }
        }
        .disabled(model.isLoadingPeers || model.peers.isEmpty)
        Text(
          "Online devices load automatically from the Tailscale client. Headscale uses that client connected to your own server."
        )
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      } else {
        TextField("Device VPN IPv4 address", text: $model.address, prompt: Text("e.g. 10.20.0.2"))
          .textFieldStyle(.roundedBorder)
        Text(
          "Copy the target device's private IPv4 address from your VPN app or administrator. Public addresses and IPv6 are unsupported."
        )
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Text("Connect your chosen VPN on both devices first. Debagr uses the existing connection.")
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    } header: {
      Text("Private network")
    }
  }
}

private struct SetupDeviceSections: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    Section {
      Picker("Paired device", selection: $model.deviceID) {
        Text("Choose a device…").tag("")
        ForEach(model.devices) { device in
          Text("\(device.displayName) · \(device.kind.displayName)").tag(device.identity.value)
        }
      }
      Text(
        model.devices.isEmpty
          ? "No paired devices found. Connect your device over USB, grant trust, and refresh."
          : "Choose the same physical device as the VPN address above. This build Mac must already be paired with it."
      )
      .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    } header: {
      Text("Target device")
    }
    Section("Nearby connection") {
      Picker("Local device service", selection: $model.serviceHost) {
        Text("Choose a nearby service…").tag("")
        ForEach(model.serviceHosts, id: \.self) { Text($0).tag($0) }
      }
      .disabled(model.importedProfile != nil)
      Text(
        model.serviceHosts.isEmpty
          ? "Keep the device unlocked on the same Wi-Fi as this Mac, or import a saved profile."
          : "Select the same device's nearby service. Debagr captures it for use when the device moves to another network."
      )
      .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("Use Saved Profile…") { model.onImport?() }
          .disabled(model.peerIP.isEmpty)
        if model.importedProfile != nil {
          Label("Profile loaded", systemImage: "checkmark.circle").foregroundStyle(.secondary)
          Button("Remove") { model.importedProfile = nil }
        }
      }
    }
  }
}

private struct SetupSavedView: View {
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
    }
    .padding(48).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct SetupFooter: View {
  @ObservedObject var model: DeviceSetupModel

  var body: some View {
    HStack(spacing: 12) {
      if model.page == .setup {
        Button("Setup Guide") {
          model.error = nil
          model.page = .guide
        }
        .disabled(model.isWorking)
      }
      if model.isWorking || model.isLoadingPeers {
        ProgressView().controlSize(.small)
        Text(model.isWorking ? "Saving setup…" : "Finding network devices…")
          .font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      Button(model.page == .saved ? "Close" : "Cancel") { model.onClose?() }
        .keyboardShortcut(.cancelAction).disabled(model.isWorking)
      Button(
        model.page == .guide ? "Set Up a Device" : model.page == .saved ? "Done" : "Save & Connect"
      ) {
        switch model.page {
        case .guide: model.page = .setup
        case .setup: model.save()
        case .saved: model.onClose?()
        }
      }
      .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
      .disabled(model.isWorking || (model.page == .setup && !model.canSave))
    }
    .padding(16)
  }
}
