import DebagrBridge
import DebagrCore
import SwiftUI

public struct WirelessSetupWizardView: View {
  @ObservedObject var model: AppModel

  @State private var step = 1
  @State private var selectedDeviceID: String?
  @State private var selectedVPNProvider: VPNProvider = .tailscale
  @State private var manualVPNAddress = ""
  @State private var selectedPeerName: String?
  @State private var selectedTailscaleNodeID: String?
  @State private var lockdownPortString = "62078"
  @State private var selectedBonjourID: String?
  @State private var hardwareConfirmed = false

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Wireless Setup — Use Existing Pairing")
            .font(.title2.bold())
          Text(
            "Configure your already-paired iPhone or iPad while nearby so Debagr can bridge it over a private VPN when roaming."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }

        stepIndicator

        switch step {
        case 1: stepPickDevice
        case 2: stepChooseVPN
        case 3: stepCaptureWirelessIdentity
        default: stepReviewAndSave
        }
      }
      .padding(24)
    }
    .onAppear {
      if let handoff = model.pendingHandoffDevice {
        selectedDeviceID = handoff.udid
      }
      Task { await model.scanSetupDevices() }
    }
  }

  private var stepIndicator: some View {
    HStack(spacing: 8) {
      ForEach(1...4, id: \.self) { idx in
        HStack(spacing: 6) {
          Text("\(idx)")
            .font(.caption.bold())
            .frame(width: 22, height: 22)
            .background(step >= idx ? Color.accentColor : Color.secondary.opacity(0.2))
            .foregroundStyle(step >= idx ? .white : .secondary)
            .clipShape(Circle())
          Text(stepTitle(idx))
            .font(.caption.weight(step == idx ? .semibold : .regular))
            .foregroundStyle(step == idx ? .primary : .secondary)
        }
        if idx < 4 {
          Divider().frame(height: 14)
        }
      }
    }
  }

  private func stepTitle(_ index: Int) -> String {
    switch index {
    case 1: "Paired Device"
    case 2: "Private VPN"
    case 3: "Wireless Identity"
    default: "Confirm & Save"
    }
  }

  private var selectedDevice: PhysicalDevice? {
    model.setupDevices.first(where: { ($0.udid ?? $0.coreDeviceID) == selectedDeviceID })
  }

  private var selectedBonjourRecord: BonjourServiceRecord? {
    model.localWirelessCandidates.first(where: { $0.id == selectedBonjourID })
  }

  private var stepPickDevice: some View {
    GroupBox("Step 1: Pick Paired Physical iPhone or iPad") {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Only paired physical iPhones and iPads on this Builder Mac are eligible.")
            .font(.callout)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Refresh Devices") {
            Task { await model.scanSetupDevices() }
          }
          .disabled(model.isBusy)
        }

        if model.setupDevices.isEmpty {
          Text(
            "No eligible paired physical iPhone or iPad found. Pair your device with this Mac once via USB and trust this computer (or check Experimental > Pair via USB/IP)."
          )
          .font(.callout)
          .foregroundStyle(.orange)
          .padding(.vertical, 8)
        } else {
          ForEach(model.setupDevices) { dev in
            let id = dev.udid ?? dev.coreDeviceID
            Button {
              selectedDeviceID = id
            } label: {
              HStack {
                Image(
                  systemName: selectedDeviceID == id ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(selectedDeviceID == id ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                  Text(dev.name).font(.headline)
                  Text(
                    "\(dev.model ?? dev.platform.rawValue) • \(dev.osVersion ?? "") • UDID \(Redactor.redactUDID(dev.udid))"
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                }
                Spacer()
                Text(dev.transportType.rawValue)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
              .padding(10)
              .background(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(
                    selectedDeviceID == id ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: 1.5
                  )
              )
            }
            .buttonStyle(.plain)
          }
        }

        if !model.setupIneligibleDevices.isEmpty {
          DisclosureGroup("Ignored Devices (\(model.setupIneligibleDevices.count))") {
            VStack(alignment: .leading, spacing: 4) {
              ForEach(model.setupIneligibleDevices) { dev in
                Text("• \(dev.name): \(dev.ineligibilityReason ?? "Ineligible")")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .padding(.top, 4)
          }
          .font(.caption)
        }

        HStack {
          Spacer()
          Button("Next: Choose VPN") { step = 2 }
            .buttonStyle(.borderedProminent)
            .disabled(selectedDevice == nil)
        }
      }
      .padding(8)
    }
  }

  private var stepChooseVPN: some View {
    GroupBox("Step 2: Choose Private VPN Endpoint") {
      VStack(alignment: .leading, spacing: 14) {
        Picker("VPN Provider", selection: $selectedVPNProvider) {
          ForEach(VPNProvider.allCases) { provider in
            Text(provider.displayName).tag(provider)
          }
        }
        .pickerStyle(.segmented)

        Text(selectedVPNProvider.setupHint)
          .font(.caption)
          .foregroundStyle(.secondary)

        if selectedVPNProvider.supportsAutomaticDiscovery {
          HStack {
            Button("Discover VPN Peers") {
              Task { await model.scanVPNPeers(provider: selectedVPNProvider) }
            }
            .disabled(model.isBusy)

            if let env = model.vpnEnvironment {
              Text(env.detail)
                .font(.caption)
                .foregroundStyle(env.available ? Color.secondary : Color.orange)
            }
          }

          if let peers = model.vpnEnvironment?.peers, !peers.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              ForEach(peers) { peer in
                Button {
                  if let ip = peer.preferredPrivateIP {
                    manualVPNAddress = ip
                    selectedPeerName = peer.name
                    selectedTailscaleNodeID = peer.id
                  }
                } label: {
                  HStack {
                    Image(
                      systemName: manualVPNAddress == peer.preferredPrivateIP
                        ? "checkmark.circle.fill" : "circle"
                    )
                    Text(peer.name).font(.callout.bold())
                    Text("(\(peer.os))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(peer.preferredPrivateIP ?? "")
                      .font(.caption.monospaced())
                  }
                  .padding(8)
                  .background(Color.secondary.opacity(0.08))
                  .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Device Private VPN IP (RFC 1918, 100.64.0.0/10, or IPv6 ULA)")
              .font(.caption)
              .foregroundStyle(.secondary)
            TextField("e.g. 100.64.12.34 or 10.8.0.5", text: $manualVPNAddress)
              .textFieldStyle(.roundedBorder)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Lockdown Port")
              .font(.caption)
              .foregroundStyle(.secondary)
            TextField("62078", text: $lockdownPortString)
              .textFieldStyle(.roundedBorder)
              .frame(width: 90)
          }
        }

        let ipCheck = IPValidation.classify(manualVPNAddress)
        if !manualVPNAddress.isEmpty, case .invalidOrDisallowed(let reason) = ipCheck {
          Text(reason)
            .font(.caption)
            .foregroundStyle(.red)
        }

        HStack {
          Button("Back") { step = 1 }
          Spacer()
          Button("Next: Wireless Identity") {
            step = 3
            Task { await model.scanLocalWirelessIdentities() }
          }
          .buttonStyle(.borderedProminent)
          .disabled(!ipCheck.isValidPrivateVPN || UInt16(lockdownPortString) == nil)
        }
      }
      .padding(8)
    }
  }

  private var stepCaptureWirelessIdentity: some View {
    GroupBox("Step 3: Associate Local Wireless Pairing Identity") {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(
            "Keep your paired device unlocked on the same Wi-Fi as this Builder Mac to capture its local _apple-mobdev2._tcp advertisement."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          Spacer()
          Button("Scan Local Bonjour") {
            Task { await model.scanLocalWirelessIdentities() }
          }
          .disabled(model.isBusy)
        }

        if model.localWirelessCandidates.isEmpty {
          Text(
            "No local _apple-mobdev2._tcp advertisements detected yet. Click “Scan Local Bonjour” with the device awake nearby."
          )
          .font(.caption)
          .foregroundStyle(.orange)
        } else {
          ForEach(model.localWirelessCandidates) { record in
            Button {
              selectedBonjourID = record.id
            } label: {
              HStack {
                Image(
                  systemName: selectedBonjourID == record.id ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(selectedBonjourID == record.id ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                  Text("Apple Wireless Pairing Service (\(record.hostTarget))")
                    .font(.callout.bold())
                  Text("Service: \(record.serviceType) • Port \(record.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
              }
              .padding(8)
              .background(Color.secondary.opacity(0.08))
              .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
          }
        }

        Toggle(
          "I confirm this local advertisement belongs to the exact same physical iPhone/iPad selected in Step 1 (\(selectedDevice?.name ?? "device")).",
          isOn: $hardwareConfirmed
        )
        .font(.callout)

        HStack {
          Button("Back") { step = 2 }
          Spacer()
          Button("Next: Review & Save") { step = 4 }
            .buttonStyle(.borderedProminent)
            .disabled(selectedBonjourRecord == nil || !hardwareConfirmed)
        }
      }
      .padding(8)
    }
  }

  private var stepReviewAndSave: some View {
    GroupBox("Step 4: Review & Save Managed Profile") {
      VStack(alignment: .leading, spacing: 10) {
        if let dev = selectedDevice, let bonjour = selectedBonjourRecord {
          LabeledContent("Device", value: "\(dev.name) (UDID \(Redactor.redactUDID(dev.udid)))")
          LabeledContent("Platform", value: dev.platform.rawValue)
          LabeledContent("VPN Provider", value: selectedVPNProvider.displayName)
          LabeledContent("VPN Endpoint", value: "\(manualVPNAddress):\(lockdownPortString)")
          LabeledContent("Wireless Service", value: "\(bonjour.serviceType) (port \(bonjour.port))")
          Text(
            "Stored locally at 0600 permissions inside Application Support. Raw Bonjour pairing identifiers are never exposed in exported diagnostics."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 4)

          HStack {
            Button("Back") { step = 3 }
            Spacer()
            Button("Verify & Save Device") {
              Task {
                guard let port = UInt16(lockdownPortString) else { return }
                _ = await model.verifyAndSaveProfile(
                  device: dev,
                  vpnProvider: selectedVPNProvider,
                  vpnAddress: manualVPNAddress,
                  peerName: selectedPeerName,
                  tailscaleNodeID: selectedTailscaleNodeID,
                  lockdownPort: port,
                  bonjourRecord: bonjour
                )
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
          }
        }
      }
      .padding(8)
    }
  }
}
