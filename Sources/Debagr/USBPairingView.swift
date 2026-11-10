import AppKit
import SwiftUI

struct USBPairingView: View {
  @ObservedObject var model: USBPairingModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 8) {
        ForEach(USBPairingStage.allCases) { stage in
          VStack(spacing: 6) {
            Text("0\(stage.rawValue + 1)").font(.caption.monospaced())
            Text(stage.title).font(.system(size: 11, weight: .medium))
          }
          .frame(maxWidth: .infinity).padding(.vertical, 10)
          .foregroundStyle(stage == model.stage ? SettingsStyle.accent : .secondary)
          .background(
            stage == model.stage ? SettingsStyle.accent.opacity(0.08) : Color.primary.opacity(0.03),
            in: RoundedRectangle(cornerRadius: 8)
          )
          .accessibilityLabel(
            "Step \(stage.rawValue + 1): \(stage.title)\(stage == model.stage ? ", current step" : "")"
          )
        }
      }
      Group {
        switch model.stage {
        case .setup: prerequisites
        case .device: deviceSelection
        case .trust: trustInstructions
        case .wireless: wirelessConnection
        }
      }
      .disabled(model.isBusy)
      if let error = model.error {
        Label(error, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red).font(.callout).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var prerequisites: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Where is the iPhone plugged in?").font(.headline)
      TextField(
        "Client Mac SSH alias", text: $model.host, prompt: Text("e.g. nearby-mac or me@macbook")
      )
      .textFieldStyle(.roundedBorder)
      Text(
        "This Mac receives the USB device and owns its new Apple pairing. SSH must already work with a trusted host key and a key or SSH agent."
      )
      .font(.callout).foregroundStyle(.secondary)
      DisclosureGroup("One-time VirtualHere setup") {
        VStack(alignment: .leading, spacing: 10) {
          Text(
            "Builder: install and open VirtualHere Client, complete its driver setup, and disable Auto-Use. Keep it running during pairing."
          )
          Text(
            "Client Mac: install this Debagr build and VirtualHere Server. Stop the server, set NetworkInterface=127.0.0.1 in its config.ini, then restart it on port 7575. The interface setting requires a VirtualHere server license."
          )
          Text(
            "Plug the unlocked iPhone into the Client Mac with a USB data cable. Both Macs need SSH connectivity, normally over your private VPN."
          )
          HStack {
            Link(
              "VirtualHere Client ↗",
              destination: URL(string: "https://www.virtualhere.com/usb_client_software")!)
            Link(
              "Server setup ↗",
              destination: URL(string: "https://www.virtualhere.com/configuration_faq")!)
          }
          Button("Open VirtualHere Client") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/VirtualHereUniversal.app"))
          }
        }
        .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
      }
      .font(.callout)
    }
  }

  private var deviceSelection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Select the physical iPhone to forward").font(.headline)
      Picker("USB device", selection: $model.selectedID) {
        Text("Choose a device…").tag("")
        ForEach(model.devices) { device in
          Text(
            "\(device.name) · …\(device.serial.suffix(6))\(device.isAvailable ? "" : " · In use")"
          )
          .tag(device.id)
        }
      }
      .disabled(model.devices.isEmpty)
      Text(
        "Only iPhones and iPads from \(model.host)'s SSH tunnel are listed. Claiming a device gives this Builder access to it until you stop the session."
      )
      .font(.callout).foregroundStyle(.secondary)
      Button("Refresh USB devices", action: model.refreshDevices).buttonStyle(.link)
    }
  }

  private var trustInstructions: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Approve the Builder on your iPhone", systemImage: "iphone")
        .font(.headline)
      Text(
        "Choose Pair with this Builder below. When Apple asks, tap Trust on your iPhone and enter your passcode there. Keep the device unlocked."
      )
      Text(
        "Enable Developer Mode in Settings → Privacy & Security if needed. If its restart interrupts USB, stop this session, reconnect, and select the same iPhone again; any completed pairing is retained."
      )
      .foregroundStyle(.secondary)
      Text(
        "A forwarding request alone is not pairing. Debagr checks USB identity and Apple connectivity before continuing."
      )
      .foregroundStyle(.secondary)
    }
    .font(.callout)
  }

  private var wirelessConnection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Keep the pairing. Release the USB bridge.").font(.headline)
      Picker("Private network", selection: $model.provider) {
        ForEach(NetworkProvider.allCases, id: \.rawValue) { Text($0.displayName).tag($0) }
      }
      TextField(
        "iPhone VPN IPv4 address", text: $model.address,
        prompt: Text(model.provider == .tailscale ? "100.x.x.x" : "e.g. 10.20.0.2")
      )
      .textFieldStyle(.roundedBorder)
      Picker("iPhone wireless service", selection: $model.serviceHost) {
        Text("Choose the same iPhone…").tag("")
        ForEach(model.services) { Text("\($0.name) · \($0.host)").tag($0.host) }
      }
      Button("Refresh nearby services", action: model.refreshServices).buttonStyle(.link)
      Toggle(
        "This service and VPN address belong to the iPhone I just paired",
        isOn: $model.confirmsService
      )
      .toggleStyle(.checkbox).font(.callout)
      Text(
        "Keep the iPhone and Client Mac on the same Wi-Fi for this capture. Saving stops USB forwarding before checking the wireless connection. Installation and launch are tested on your next deployment."
      )
      .font(.callout).foregroundStyle(.secondary)
    }
    .onChange(of: model.provider) { _ in model.confirmsService = false }
    .onChange(of: model.address) { _ in model.confirmsService = false }
    .onChange(of: model.serviceHost) { _ in model.confirmsService = false }
  }
}

struct USBPairingActions: View {
  @ObservedObject var model: USBPairingModel
  let onConfigured: (ConfiguredDevice) -> Void

  var body: some View {
    HStack(spacing: 12) {
      if model.hasSession { Button("Stop USB session", action: model.stop) }
      if model.isBusy { ProgressView().controlSize(.small) }
      Text(model.status).font(.caption).foregroundStyle(.secondary)
        .lineLimit(3).help(model.status)
      Spacer(minLength: 0)
      Button(model.actionTitle) { model.advance(onConfigured: onConfigured) }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .keyboardShortcut(.defaultAction).disabled(!model.canAdvance)
    }
  }
}
