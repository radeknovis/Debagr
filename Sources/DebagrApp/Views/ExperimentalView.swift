import DebagrCore
import DebagrExperimental
import SwiftUI

public struct ExperimentalView: View {
  @ObservedObject var model: AppModel

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        DiagonalHatchBanner(
          title: "Experimental Routes",
          subtitle:
            "Fallback tools for edge cases when normal Wi-Fi + VPN deployment is unavailable. For daily use, stick to Wireless Setup."
        )

        cableServiceBridgeCard
        usbipPairingCard
      }
      .frame(maxWidth: DesignTokens.maxContentWidth, alignment: .leading)
      .frame(maxWidth: .infinity)
      .padding(DesignTokens.pagePadding)
    }
  }

  private var cableServiceBridgeCard: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
              Text("USB via Mac (Cable Service Bridge)")
                .font(.headline)
              ExperimentalBadge()
            }
            Text(
              "Use when an already-paired iPhone/iPad has Wi-Fi off and is plugged via USB into a second Mac."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          Spacer()
        }

        DisclosureGroup(
          "When would I need this? & Terminal Setup",
          isExpanded: $model.experimentalDraft.showCableBridge
        ) {
          VStack(alignment: .leading, spacing: 12) {
            InlineNotice(
              symbolName: "cable.connector",
              color: .secondary,
              title: "Service Forwarding Only — No Root, No Raw USB, No SIP Changes",
              message:
                "Forwards Apple usbmuxd port 62078 strictly on 127.0.0.1 over SSH + your private VPN. Requires the device to already be paired with this Builder Mac."
            )

            let trimmedPort = model.experimentalDraft.cablePort.trimmingCharacters(
              in: .whitespacesAndNewlines
            )
            let resolvedPort: UInt16? =
              trimmedPort.isEmpty ? 22078 : DebagrFormatters.parseTCPPort(trimmedPort)
            let isPortInvalid = !trimmedPort.isEmpty && resolvedPort == nil

            HStack(alignment: .top, spacing: 12) {
              DebagrTextField(
                label: "Client Mac SSH Target",
                text: $model.experimentalDraft.clientSSHHost,
                prompt: "user@100.64.x.y",
                leadingIcon: "network",
                showClearButton: true
              )

              DebagrTextField(
                label: "Loopback Port",
                text: $model.experimentalDraft.cablePort,
                prompt: "22078",
                leadingIcon: "number",
                numericOnly: true,
                maxLength: 5,
                validation: isPortInvalid ? .invalid("") : .none
              )
              .frame(width: 145)
            }

            let trimmedHost = model.experimentalDraft.clientSSHHost.trimmingCharacters(
              in: .whitespacesAndNewlines
            )
            let effectiveHost = trimmedHost.isEmpty ? "<user>@<client-vpn-ip>" : trimmedHost
            let udid = model.config.managedDevice?.udid ?? "<device-udid>"

            if let validPort = resolvedPort {
              let guide = CableBridgeGuide(
                clientHost: effectiveHost,
                deviceUDID: udid,
                bonjourInstance: "<captured-bonjour-instance>",
                port: validPort
              )

              TerminalCommandField(
                code: guide.clientCommand,
                contextTag: "1. Run on Client Mac (Phone Plugged In)",
                syntax: .shell
              )
              TerminalCommandField(
                code: guide.sshTunnelCommand,
                contextTag: "2. Open SSH Tunnel from Builder Mac",
                syntax: .shell
              )
              TerminalCommandField(
                code: guide.builderCommand,
                contextTag: "3. Run on Builder Mac",
                syntax: .shell
              )
            } else {
              InlineNotice(
                symbolName: "xmark.octagon.fill",
                color: .red,
                title: "Invalid Loopback Port",
                message:
                  "Enter a loopback TCP port between 1 and 65535 (or leave blank to use 22078)."
              )
            }

            Link(
              "Read Cable Service Bridge Guide (docs/cable-bridge.md)",
              destination: URL(
                string: "https://github.com/debagr-dev/debagr/blob/main/docs/cable-bridge.md"
              )!
            )
            .font(.caption)
          }
          .padding(.top, 10)
        }
        .font(.callout.weight(.medium))
      }
    }
  }

  private var usbipPairingCard: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
              Text("Pair via USB/IP (Temporary Raw USB)")
                .font(.headline)
              ExperimentalBadge()
            }
            Text(
              "Use only for initial Apple USB pairing when an unpaired device is away from your Builder Mac."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          Spacer()
        }

        DisclosureGroup(
          "When would I need this? & Guided Prerequisites",
          isExpanded: $model.experimentalDraft.showUSBIP
        ) {
          VStack(alignment: .leading, spacing: 14) {
            InlineNotice(
              symbolName: "lock.shield",
              color: .orange,
              title: "Explicit Security Policy & Terminal Execution",
              message:
                "Debagr never bundles third-party USB drivers or weakens SIP. Interactive two-Mac USB/IP bind/attach commands run in Terminal (CLI only for now) after you explicitly review and confirm them."
            )

            VStack(alignment: .leading, spacing: 8) {
              Text("1. Check Separately Installed USB/IP Tools")
                .font(.callout.weight(.semibold))
              HStack(alignment: .center, spacing: 10) {
                DebagrTextField(
                  text: $model.experimentalDraft.usbipCustomBinaryPath,
                  prompt: "Optional custom usbip binary path",
                  leadingIcon: "terminal",
                  showClearButton: true,
                  trailingActionIcon: "folder",
                  trailingActionHelp: "Choose usbip binary on this Mac…"
                ) {
                  Task {
                    switch await DebagrFilePicker.pickExecutable(
                      title: "Select usbip Binary",
                      initialPath: model.experimentalDraft.usbipCustomBinaryPath
                    ) {
                    case .picked(let path):
                      model.experimentalDraft.usbipCustomBinaryPath = path
                    case .notExecutable(let path):
                      model.showToast(
                        "Selected file is not executable: \(URL(fileURLWithPath: path).lastPathComponent)"
                      )
                    case .cancelled:
                      break
                    }
                  }
                }
                Button("Check Prerequisites") {
                  let custom = model.experimentalDraft.usbipCustomBinaryPath
                  Task {
                    await model.checkUSBIPPrerequisites(
                      customPath: custom.isEmpty ? nil : custom
                    )
                  }
                }
                .buttonStyle(DebagrSecondaryButtonStyle())
              }

              if let prereq = model.usbipPrerequisites {
                InlineNotice(
                  symbolName: prereq.usbipAvailable
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                  color: prereq.usbipAvailable ? .green : .orange,
                  title: prereq.usbipAvailable ? "USB/IP Tool Found" : "USB/IP Binary Not Found",
                  message: "\(prereq.summary) \(prereq.installNotice)"
                )
              }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
              Text("2. Discover Nearby Debagr Peers (On Demand)")
                .font(.callout.weight(.semibold))
              HStack {
                Button {
                  Task { await model.discoverUSBIPPeersOnDemand() }
                } label: {
                  DebagrButtonLabel(
                    title: model.isScanningUSBIPPeers ? "Scanning…" : "Discover Nearby Macs",
                    systemImage: "bonjour",
                    isLoading: model.isScanningUSBIPPeers
                  )
                }
                .buttonStyle(DebagrSecondaryButtonStyle(isLoading: model.isScanningUSBIPPeers))

                Text(
                  model.usbipDiscoveredPeers.isEmpty
                    ? "Runs only when clicked; zero always-on listeners."
                    : "Found \(model.usbipDiscoveredPeers.count) peer(s)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }

              if !model.usbipDiscoveredPeers.isEmpty {
                ForEach(model.usbipDiscoveredPeers) { peer in
                  HStack {
                    Image(systemName: "desktopcomputer")
                    Text(peer.name).font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(peer.host):\(peer.port)").font(.caption.monospaced())
                  }
                  .padding(8)
                  .background(
                    Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                  )
                }
              }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
              Text("3. Continue in Terminal (CLI)")
                .font(.callout.weight(.semibold))

              DebagrSegmentedControl(
                "This Mac's Role",
                selection: $model.experimentalDraft.selectedUSBIPRole,
                options: USBIPRole.allCases,
                title: { role in
                  switch role {
                  case .builder: "Builder Mac"
                  case .client: "Client Mac"
                  }
                },
                systemImage: { role in
                  switch role {
                  case .builder: "macstudio"
                  case .client: "iphone.and.arrow.forward"
                  }
                }
              )

              Text(
                model.experimentalDraft.selectedUSBIPRole == .builder
                  ? "Builder Mac runs Xcode, Apple Trust & remote install."
                  : "Client Mac holds the physical iPhone or iPad over USB."
              )
              .font(.caption)
              .foregroundStyle(.secondary)

              let customPath = model.experimentalDraft.usbipCustomBinaryPath.trimmingCharacters(
                in: .whitespacesAndNewlines
              )
              let checkCmd =
                customPath.isEmpty
                ? "debagr experimental usbip check"
                : "debagr experimental usbip check --usbip-path \(DebagrFormatters.shellSingleQuote(customPath))"

              TerminalCommandField(
                code: """
                  \(checkCmd)
                  debagr experimental usbip guide
                  """,
                contextTag: model.experimentalDraft.selectedUSBIPRole == .builder
                  ? "Run on Builder Mac Terminal (CLI only for now)"
                  : "Run on Client Mac Terminal (CLI only for now)",
                syntax: .shell
              )
            }

            Divider()

            HStack {
              Button {
                Task { await model.checkNewlyPairedDeviceForHandoff() }
              } label: {
                DebagrButtonLabel(
                  title: model.isScanningDevices
                    ? "Checking…"
                    : "Check for Newly Paired Device",
                  systemImage: "arrow.triangle.2.circlepath",
                  isLoading: model.isScanningDevices
                )
              }
              .buttonStyle(DebagrSecondaryButtonStyle(isLoading: model.isScanningDevices))

              Spacer()

              if let handoff = model.usbipHandoff {
                Button("Continue to Wireless Setup") {
                  model.handoffUSBIPToWirelessSetup(device: handoff.pairedDevice)
                }
                .buttonStyle(DebagrPrimaryButtonStyle())
              }
            }

            Link(
              "Read Pair via USB/IP Security & Walkthrough (docs/usbip-pairing.md)",
              destination: URL(
                string: "https://github.com/debagr-dev/debagr/blob/main/docs/usbip-pairing.md"
              )!
            )
            .font(.caption)
          }
          .padding(.top, 10)
        }
        .font(.callout.weight(.medium))
      }
    }
  }
}
