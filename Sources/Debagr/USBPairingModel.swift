import Combine
import Foundation

enum USBPairingStage: Int, CaseIterable, Identifiable {
  case setup, device, trust, wireless
  var id: Self { self }
  var title: String {
    switch self {
    case .setup: return "Client Mac"
    case .device: return "Forward USB"
    case .trust: return "Approve trust"
    case .wireless: return "Go wireless"
    }
  }
}

@MainActor
final class USBPairingModel: ObservableObject {
  @Published var host = ""
  @Published private(set) var stage = USBPairingStage.setup
  @Published private(set) var devices: [ForwardedUSBDevice] = []
  @Published var selectedID = ""
  @Published private(set) var services: [USBNearbyService] = []
  @Published var serviceHost = ""
  @Published var provider = NetworkProvider.tailscale
  @Published var address = ""
  @Published var confirmsService = false
  @Published private(set) var isBusy = false
  @Published private(set) var hasSession = false
  @Published private(set) var status =
    "Run this setup on your Builder. Plug the iPhone into the Client Mac."
  @Published private(set) var error: String?
  @Published private(set) var pairedDevice: TargetDevice?
  private let queue = DispatchQueue(label: "debagr.usb-pairing")
  private var session: USBPairingSession?
  private var generation = 0
  private var stopping = false
  private let makeSession: () -> USBPairingSession
  private let saveConfiguration: @Sendable (ConfiguredDevice) throws -> Void

  init(
    makeSession: @escaping () -> USBPairingSession = { USBPairingSession() },
    saveConfiguration: @escaping @Sendable (ConfiguredDevice) throws -> Void = {
      try ManagedDeviceStore().save($0)
    }
  ) {
    self.makeSession = makeSession
    self.saveConfiguration = saveConfiguration
  }

  var selectedDevice: ForwardedUSBDevice? { devices.first { $0.id == selectedID } }

  var canAdvance: Bool {
    guard !isBusy else { return false }
    switch stage {
    case .setup: return (try? USBSSHTunnel.validateHost(host)) != nil
    case .device: return selectedDevice?.isAvailable == true
    case .trust: return hasSession
    case .wireless:
      return hasSession && provider.allowsAddress(address) && confirmsService
        && services.contains { $0.host == serviceHost }
    }
  }

  var actionTitle: String {
    switch stage {
    case .setup: return "Connect Client Mac"
    case .device: return "Forward selected device"
    case .trust: return "Pair with this Builder"
    case .wireless: return "Save & test wireless"
    }
  }

  func advance(onConfigured: @escaping (ConfiguredDevice) -> Void) {
    guard canAdvance else { return }
    switch stage {
    case .setup:
      let session = makeSession()
      self.session = session
      hasSession = true
      let host = host
      perform(
        "Checking VirtualHere, SSH, and the Client Mac…",
        operation: {
          try session.prepare(host: host)
        },
        completion: { devices in
          self.devices = devices
          self.stage = .device
          self.status =
            "Choose the iPhone physically connected to the Client Mac. Refresh if it is still appearing."
        })
    case .device:
      guard let session, let selectedDevice else { return }
      perform(
        "Forwarding the selected USB device…",
        operation: {
          try session.attach(selectedDevice)
        },
        completion: { _ in
          self.stage = .trust
          self.status =
            "The USB request was accepted. Keep the iPhone unlocked, then pair it with this Builder."
        })
    case .trust:
      guard let session else { return }
      perform(
        "Approve Trust on your iPhone. Checking Apple pairing…",
        operation: {
          try session.pair()
        },
        completion: { device in
          self.pairedDevice = device
          self.stage = .wireless
          self.status =
            "Apple connectivity is confirmed over USB. Now prepare the direct wireless connection."
          self.refreshServices()
        })
    case .wireless:
      guard let session else { return }
      let provider = provider
      let address = address
      let host = serviceHost
      let saveConfiguration = saveConfiguration
      perform(
        "Capturing the wireless profile and releasing USB…",
        operation: {
          let configured = try session.finish(
            provider: provider, address: address, serviceHost: host)
          try saveConfiguration(configured)
          return configured
        },
        completion: { configuration in
          self.hasSession = false
          self.session = nil
          self.status = "USB forwarding ended. Checking the saved wireless connection."
          onConfigured(configuration)
        })
    }
  }

  func refreshDevices() {
    guard !isBusy, let session, stage == .device else { return }
    perform(
      "Refreshing USB devices…", operation: { try session.devices() },
      completion: {
        self.devices = $0
        if !self.devices.contains(where: { $0.id == self.selectedID }) { self.selectedID = "" }
        self.status =
          self.devices.isEmpty
          ? "No iPhone or iPad is available yet. Connect a data cable, unlock the phone, and refresh."
          : "Select a device to forward. Devices in use by another client cannot be claimed."
      })
  }

  func refreshServices() {
    guard !isBusy, let session else { return }
    confirmsService = false
    perform(
      "Finding the iPhone's wireless service near the Client Mac…",
      operation: {
        try session.services()
      },
      completion: {
        self.services = $0
        if !self.services.contains(where: { $0.host == self.serviceHost }) { self.serviceHost = "" }
        self.status =
          self.services.isEmpty
          ? "No wireless service found. Put the iPhone and Client Mac on the same Wi-Fi, enable Developer Mode, then refresh. USB stays connected."
          : "Choose the same iPhone's wireless service and private VPN address."
      })
  }

  func stop() {
    guard let session, !stopping else { return }
    stopping = true
    generation += 1
    let generation = generation
    session.cancel()
    isBusy = true
    status = "Releasing the USB session…"
    queue.async {
      let result = Result { try session.cleanupAfterCancellation() }
      DispatchQueue.main.async {
        guard self.generation == generation else { return }
        self.session = nil
        self.stopping = false
        self.hasSession = false
        self.isBusy = false
        self.stage = .setup
        self.devices = []
        self.services = []
        self.selectedID = ""
        self.pairedDevice = nil
        self.confirmsService = false
        self.status = "USB tunnel closed. Any completed Apple pairing is retained."
        if case .failure = result {
          self.error =
            "The tunnel is closed, but VirtualHere did not confirm all cleanup. Remove the unused 127.0.0.1 hub in VirtualHere before retrying."
        } else {
          self.error = nil
        }
      }
    }
  }

  func shutdown(completion: @escaping @MainActor @Sendable () -> Void) {
    generation += 1
    guard let session else {
      completion()
      return
    }
    session.cancel()
    queue.async {
      try? session.cleanupAfterCancellation()
      RunLoop.main.perform(inModes: [.common, .modalPanel]) {
        MainActor.assumeIsolated {
          self.session = nil
          self.hasSession = false
          self.isBusy = false
          completion()
        }
      }
    }
  }

  private func perform<Value: Sendable>(
    _ message: String, operation: @escaping @Sendable () throws -> Value,
    completion: @escaping @MainActor @Sendable (Value) -> Void
  ) {
    isBusy = true
    error = nil
    status = message
    let generation = generation
    queue.async {
      let result = Result { try operation() }
      DispatchQueue.main.async {
        guard self.generation == generation else { return }
        self.isBusy = false
        switch result {
        case .success(let value): completion(value)
        case .failure(let error): self.error = error.localizedDescription
        }
      }
    }
  }
}
