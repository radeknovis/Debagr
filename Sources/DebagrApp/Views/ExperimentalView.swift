import DebagrCore
import DebagrExperimental
import SwiftUI

public struct ExperimentalView: View {
  @ObservedObject var model: AppModel

  @State private var clientSSHHost = "dev@100.64.x.y"
  @State private var cablePort = "22078"
  @State private var selectedUSBIPRole: USBIPRole = .builder
  @State private var usbipCustomBinaryPath = ""
  @State private var manualUSBIPPeerIP = ""
  @State private var enteredSASCode = ""
  @State private var showApprovalSheet = false
  @State private var confirmedSecurityNotice = false

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        experimentalBanner
        cableServiceBridgeSection
        usbipPairingSection
      }
      .padding(24)
    }
    .sheet(isPresented: $showApprovalSheet) {
      usbipApprovalSheet
    }
  }

  private var experimentalBanner: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "flask.fill")
        .font(.title2)
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 4) {
        Text("Experimental Routes")
          .font(.headline)
          .foregroundStyle(.orange)
        Text(
          "The workflows below are clearly labeled experimental fallback helpers for edge cases. For everyday remote deployment, use the primary Wireless Setup workflow."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private var cableServiceBridgeSection: some View {
    GroupBox("Experimental: USB via Mac (Cable Service Bridge)") {
      VStack(alignment: .leading, spacing: 10) {
        Text(
          "Terminal-driven service bridge for an ALREADY-PAIRED device plugged via USB into a second Mac (even with Wi-Fi turned off). Forwards usbmuxd port 62078 strictly over 127.0.0.1 + SSH + private VPN — no raw USB sharing, no root privileges, and no SIP changes."
        )
        .font(.callout)
        .foregroundStyle(.secondary)

        HStack {
          TextField("Client Mac SSH target (user@vpn-ip)", text: $clientSSHHost)
            .textFieldStyle(.roundedBorder)
          TextField("Port", text: $cablePort)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
        }

        let portNum = UInt16(cablePort) ?? 22078
        let udid = model.config.managedDevice?.udid ?? "<device-udid>"
        let guide = CableBridgeGuide(
          clientHost: clientSSHHost,
          deviceUDID: udid,
          bonjourInstance: "<captured-bonjour-instance>",
          port: portNum
        )

        VStack(alignment: .leading, spacing: 6) {
          commandLine("1. On Client Mac (phone plugged in):", guide.clientCommand)
          commandLine("2. SSH tunnel from Builder Mac:", guide.sshTunnelCommand)
          commandLine("3. On Builder Mac:", guide.builderCommand)
        }

        HStack(spacing: 12) {
          Link(
            "Open Cable Bridge Guide",
            destination: URL(
              string: "https://github.com/debagr-dev/debagr/blob/main/docs/cable-bridge.md"
            )!
          )
          .font(.caption)

          Button("Copy Guide CLI Command") {
            model.copyToPasteboard(
              "debagr experimental cable-bridge guide --client-host \(clientSSHHost)"
            )
            model.statusBanner = "Copied cable-bridge guide CLI command."
          }
          .font(.caption)
        }
      }
      .padding(8)
    }
  }

  private var usbipPairingSection: some View {
    GroupBox("Experimental: Pair via USB/IP (Temporary Raw USB for Initial Pairing)") {
      VStack(alignment: .leading, spacing: 12) {
        Text(
          "Guided two-Mac helper for performing Apple's initial USB pairing when your device is not yet paired with the Builder Mac. Supervises separately installed third-party USB/IP tools only after explicit approval, then tears down immediately for normal wireless handoff."
        )
        .font(.callout)
        .foregroundStyle(.secondary)

        HStack {
          TextField("Optional custom usbip binary path", text: $usbipCustomBinaryPath)
            .textFieldStyle(.roundedBorder)
          Button("Check Prerequisites") {
            Task {
              await model.checkUSBIPPrerequisites(
                customPath: usbipCustomBinaryPath.isEmpty ? nil : usbipCustomBinaryPath
              )
            }
          }
        }

        if let prereq = model.usbipPrerequisites {
          VStack(alignment: .leading, spacing: 4) {
            Label(
              prereq.summary,
              systemImage: prereq.usbipAvailable
                ? "checkmark.circle.fill" : "exclamationmark.triangle"
            )
            .foregroundStyle(prereq.usbipAvailable ? .green : .orange)
            .font(.callout)
            Text(prereq.installNotice)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Divider()

        Picker("This Mac's Role", selection: $selectedUSBIPRole) {
          Text("Builder Mac (Xcode / Apple Trust)").tag(USBIPRole.builder)
          Text("Client Mac (Phone Attached via USB)").tag(USBIPRole.client)
        }
        .pickerStyle(.segmented)

        HStack {
          Button("Start Guided Session & Generate 6-Digit Code") {
            Task { await model.startUSBIPRole(role: selectedUSBIPRole) }
          }
          if let sas = model.usbipGeneratedSAS {
            Text("Session Code: \(sas)")
              .font(.headline.monospacedDigit())
              .padding(.horizontal, 10)
              .padding(.vertical, 4)
              .background(Color.accentColor.opacity(0.15))
              .clipShape(RoundedRectangle(cornerRadius: 6))
          }
        }

        HStack {
          Button("Discover On-Demand Peers") {
            Task { await model.discoverUSBIPPeersOnDemand() }
          }
          TextField("Or private VPN peer IP", text: $manualUSBIPPeerIP)
            .textFieldStyle(.roundedBorder)
          TextField("Peer 6-digit code", text: $enteredSASCode)
            .textFieldStyle(.roundedBorder)
            .frame(width: 140)
        }

        if !model.usbipDiscoveredPeers.isEmpty {
          ForEach(model.usbipDiscoveredPeers) { peer in
            Text("• Discovered peer: \(peer.name) (\(peer.host):\(peer.port))")
              .font(.caption)
          }
        }

        HStack {
          Button("Review Security Notice & Approve USB/IP Step...") {
            confirmedSecurityNotice = false
            showApprovalSheet = true
          }
          .disabled(model.usbipSessionID == nil || model.usbipPrerequisites?.usbipAvailable != true)

          Spacer()

          if let handoff = model.usbipHandoff {
            Button("Continue to Wireless Setup") {
              model.handoffUSBIPToWirelessSetup(device: handoff.pairedDevice)
            }
            .buttonStyle(.borderedProminent)
          }
        }
      }
      .padding(8)
    }
  }

  private var usbipApprovalSheet: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Explicit Security Approval Required", systemImage: "exclamationmark.shield.fill")
        .font(.title3.bold())
        .foregroundStyle(.orange)

      Text(
        "Debagr is about to supervise your separately installed third-party `usbip` binary to temporarily attach a USB device over the private VPN for initial Apple pairing only."
      )
      .font(.callout)

      Text(
        "• Debagr does NOT bundle USB/IP drivers or weaken macOS SIP.\n• Pairing coordination is authenticated with Curve25519 + your 6-digit SAS code.\n• Debagr tears down the USB/IP link immediately once Apple pairing finishes."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      Toggle(
        "I have reviewed the third-party `usbip` tool and explicitly approve running this temporary pairing session.",
        isOn: $confirmedSecurityNotice
      )

      HStack {
        Button("Cancel", role: .cancel) {
          showApprovalSheet = false
        }
        Spacer()
        Button("Confirm") {
          showApprovalSheet = false
          model.statusBanner =
            "Approval recorded for session \(model.usbipSessionID ?? ""). Complete attach/pair via CLI or active peer session."
        }
        .buttonStyle(.borderedProminent)
        .disabled(!confirmedSecurityNotice)
      }
    }
    .padding(22)
    .frame(width: 480)
  }

  private func commandLine(_ label: String, _ command: String) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.caption.bold())
        Text(command)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }
      Spacer()
      Button("Copy") {
        model.copyToPasteboard(command)
        model.statusBanner = "Copied experimental command."
      }
    }
    .padding(8)
    .background(Color.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}
