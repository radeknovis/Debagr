import DebagrBridge
import DebagrCore
import SwiftUI

public struct WirelessSetupWizardView: View {
  @ObservedObject var model: AppModel
  @Namespace private var railNamespace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showOtherVPNPeers = false

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Wireless Setup — Use Existing Pairing")
              .font(.title2.weight(.semibold))
            Text(
              "Configure your already-paired iPhone or iPad while nearby so Debagr can bridge it over a private VPN when you roam."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
          }

          progressRail

          Group {
            switch model.setupDraft.step {
            case .pickDevice: stepPickDevice
            case .chooseVPN: stepChooseVPN
            case .captureIdentity: stepCaptureIdentity
            case .review: stepReview
            case .completed: stepCompleted
            }
          }
          .id(model.setupDraft.step)
          .transition(.opacity)
        }
        .frame(maxWidth: DesignTokens.maxContentWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.pagePadding)
      }

      if model.setupDraft.step != .completed {
        footerBar
      }
    }
    .onAppear {
      if model.setupDevices.isEmpty && !model.isScanningDevices {
        Task { await model.scanSetupDevices() }
      }
    }
  }

  private var progressRail: some View {
    HStack(spacing: 6) {
      ForEach(Array(WirelessSetupStep.allCases.dropLast()), id: \.rawValue) { step in
        let isCurrent = model.setupDraft.step == step
        let isCompleted = model.setupDraft.step.rawValue > step.rawValue

        Button {
          guard isCompleted, !model.isSavingProfile else { return }
          go(to: step)
        } label: {
          HStack(spacing: 6) {
            Image(
              systemName: isCompleted ? "checkmark.circle.fill" : "\(step.rawValue).circle.fill"
            )
            .font(.callout)
            .foregroundStyle(isCurrent ? Color.accentColor : (isCompleted ? .green : .secondary))
            Text(step.title)
              .font(.caption.weight(isCurrent ? .semibold : .medium))
              .foregroundStyle(.primary)
              .lineLimit(1)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background {
            if isCurrent {
              Capsule()
                .fill(Color.accentColor.opacity(0.18))
                .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
                .matchedGeometryEffect(id: "activeStepPill", in: railNamespace)
            } else {
              Capsule()
                .fill(Color.primary.opacity(0.05))
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(!isCompleted || model.isSavingProfile)
        .opacity(isCurrent || isCompleted ? 1.0 : 0.55)
        .help(isCompleted ? "Return to \(step.title)" : step.title)

        if step != .review {
          Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      Spacer()
    }
  }

  private var selectedDevice: PhysicalDevice? {
    model.setupDevices.first(where: {
      ($0.udid ?? $0.coreDeviceID) == model.setupDraft.selectedDeviceID
    })
  }

  private var selectedBonjour: BonjourServiceRecord? {
    model.localWirelessCandidates.first(where: { $0.id == model.setupDraft.selectedBonjourID })
  }

  private var stepPickDevice: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Step 1 · Select Paired Physical iPhone or iPad")
              .font(.headline)
            Text("Only paired physical iPhones and iPads owned by this Builder Mac appear here.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            Task { await model.scanSetupDevices() }
          } label: {
            DebagrButtonLabel(
              title: "Refresh",
              systemImage: "arrow.clockwise",
              isLoading: model.isScanningDevices
            )
          }
          .buttonStyle(
            DebagrSecondaryButtonStyle(compact: true, isLoading: model.isScanningDevices))
        }

        if model.isScanningDevices && model.setupDevices.isEmpty {
          HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Looking for paired devices…")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 16)
        } else if model.setupDevices.isEmpty {
          DebagrEmptyState(
            symbolName: "cable.connector.slash",
            title: "No Eligible Paired Device Found",
            description:
              "Connect your iPhone or iPad to this Builder Mac with a USB cable, accept Trust This Computer, and enable Developer Mode."
          ) {
            Button("Scan Again") {
              Task { await model.scanSetupDevices() }
            }
            .buttonStyle(DebagrSecondaryButtonStyle())

            Button("Device Not Physically Here? (Experimental USB/IP)") {
              model.navigate(to: .experimental)
            }
            .buttonStyle(DebagrSecondaryButtonStyle())
          }
        } else {
          VStack(spacing: 8) {
            ForEach(model.setupDevices) { dev in
              let id = dev.udid ?? dev.coreDeviceID
              SelectableOptionCard(isSelected: model.setupDraft.selectedDeviceID == id) {
                model.setupDraft.selectDevice(id)
              } content: {
                HStack {
                  Image(systemName: dev.platform == .iPadOS ? "ipad" : "iphone")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(dev.name).font(.callout.weight(.semibold))
                    Text(
                      "\(dev.model ?? dev.platform.rawValue) • \(dev.osVersion ?? "") • UDID \(Redactor.redactUDID(dev.udid))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Text(dev.transportType == .wired ? "USB" : "Network")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
              }
            }
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
      }
    }
  }

  private var stepChooseVPN: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Step 2 · Choose Private VPN Endpoint")
            .font(.headline)
          Text(model.setupDraft.selectedVPNProvider.setupHint)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        DebagrSegmentedControl(
          "VPN Provider",
          selection: $model.setupDraft.selectedVPNProvider,
          options: VPNProvider.allCases,
          title: \.displayName,
          helpText: \.setupHint
        )

        if model.setupDraft.selectedVPNProvider.supportsAutomaticDiscovery {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Button {
                Task { await model.scanVPNPeers(provider: model.setupDraft.selectedVPNProvider) }
              } label: {
                DebagrButtonLabel(
                  title: model.isScanningVPN ? "Discovering Peers…" : "Discover VPN Peers",
                  systemImage: "network",
                  isLoading: model.isScanningVPN
                )
              }
              .buttonStyle(DebagrSecondaryButtonStyle(isLoading: model.isScanningVPN))

              if let env = model.vpnEnvironment {
                Text(env.detail)
                  .font(.caption)
                  .foregroundStyle(env.available ? Color.secondary : Color.orange)
              }

              if model.isIdentifyingVPNPeers {
                HStack(spacing: 5) {
                  ProgressView()
                    .controlSize(.small)
                  Text("Identifying reachable peers…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }

            if let peers = model.vpnEnvironment?.peers, !peers.isEmpty {
              let mobilePeers = sortedMobilePeers(
                peers.filter { $0.isLikelyAppleMobileDevice || $0.isUnknownOS }
              )
              let otherPeers = peers.filter { !($0.isLikelyAppleMobileDevice || $0.isUnknownOS) }
              let hasMultipleOwners = Set(peers.compactMap(\.ownerName)).count > 1
              let selectedIsInOtherPeers = otherPeers.contains { peer in
                let ip = peer.preferredPrivateIP ?? ""
                return !ip.isEmpty
                  && model.setupDraft.manualVPNAddress == ip
                  && model.setupDraft.selectedTailscaleNodeID == peer.id
              }

              if !mobilePeers.isEmpty {
                VStack(spacing: 6) {
                  ForEach(mobilePeers) { peer in
                    vpnPeerRow(
                      peer,
                      muted: false,
                      hasMultipleOwners: hasMultipleOwners,
                      mobilePeers: mobilePeers
                    )
                  }
                }
              } else if !otherPeers.isEmpty {
                InlineNotice(
                  symbolName: "iphone.slash",
                  color: .orange,
                  title: "No iOS or iPadOS Peers Found",
                  message:
                    "Only non-iOS/iPadOS peers were discovered on this VPN. Sign into the VPN on your iPhone/iPad and re-scan, or enter its private VPN IP manually below."
                )
              }

              if !otherPeers.isEmpty {
                let expandedBinding = Binding<Bool>(
                  get: { showOtherVPNPeers || selectedIsInOtherPeers },
                  set: { showOtherVPNPeers = $0 }
                )
                DisclosureGroup(
                  "Other Devices (\(otherPeers.count)) — non-iOS/iPadOS",
                  isExpanded: expandedBinding
                ) {
                  VStack(spacing: 6) {
                    ForEach(otherPeers) { peer in
                      vpnPeerRow(
                        peer,
                        muted: true,
                        hasMultipleOwners: hasMultipleOwners,
                        mobilePeers: mobilePeers
                      )
                    }
                  }
                  .padding(.top, 6)
                }
                .font(.caption)
              }
            }
          }
        }

        let ipBinding = Binding<String>(
          get: { model.setupDraft.manualVPNAddress },
          set: { next in
            model.setupDraft.updateManualAddress(next)
            model.manualVPNIdentifyMessage = nil
          }
        )

        let trimmedManualIP = model.setupDraft.manualVPNAddress.trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        let ipStatus = IPValidation.classify(model.setupDraft.manualVPNAddress)
        let ipFieldValidation: DebagrFieldValidation = {
          if model.setupDraft.manualVPNAddress.isEmpty {
            return .none
          }
          if case .invalidOrDisallowed = ipStatus {
            return .invalid("")
          }
          return .none
        }()
        let parsedPort = DebagrFormatters.parseTCPPort(model.setupDraft.lockdownPortString)
        let portErrorMessage: String? = {
          let trimmed = model.setupDraft.lockdownPortString.trimmingCharacters(
            in: .whitespacesAndNewlines
          )
          if trimmed.isEmpty {
            return "Enter a valid TCP lockdown port between 1 and 65535."
          }
          return parsedPort == nil
            ? "Lockdown port '\(trimmed)' is invalid. Enter a TCP port between 1 and 65535."
            : nil
        }()

        HStack(alignment: .top, spacing: 12) {
          DebagrTextField(
            label: "Device Private VPN IP (RFC 1918, 100.64.0.0/10, or IPv6 ULA)",
            text: ipBinding,
            prompt: "e.g. 100.64.12.34 or fd7a:115c:a1e0::1",
            leadingIcon: "lock.shield",
            validation: ipFieldValidation,
            showClearButton: true
          )

          DebagrTextField(
            label: "Lockdown Port",
            text: $model.setupDraft.lockdownPortString,
            prompt: "62078",
            leadingIcon: "number",
            numericOnly: true,
            maxLength: 5,
            validation: portErrorMessage == nil ? .none : .invalid("")
          )
          .frame(width: 145)
        }

        if let portErrorMessage {
          InlineNotice(
            symbolName: "xmark.octagon.fill",
            color: .red,
            title: "Invalid Lockdown Port",
            message: portErrorMessage
          )
        }

        if !trimmedManualIP.isEmpty {
          if case .invalidOrDisallowed(let reason) = ipStatus {
            InlineNotice(
              symbolName: "xmark.octagon.fill",
              color: .red,
              title: "Invalid VPN Address",
              message: reason
            )
          } else {
            if let peerName = model.setupDraft.selectedPeerName {
              Label(
                "Matched to discovered peer '\(peerName)'.",
                systemImage: "checkmark.circle.fill"
              )
              .font(.caption)
              .foregroundStyle(StatusTone.ready.color)
            }

            if parsedPort != nil {
              manualIdentifySection(for: trimmedManualIP)
            }
          }
        }
      }
    }
  }

  private var stepCaptureIdentity: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Step 3 · Capture Local Wireless Identity")
              .font(.headline)
            Text(
              "Keep your paired device unlocked on the same Wi-Fi network as this Mac so Debagr can record its _apple-mobdev2._tcp identity."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            Task { await model.scanLocalWirelessIdentities() }
          } label: {
            DebagrButtonLabel(
              title: "Scan Bonjour",
              systemImage: "wave.3.right",
              isLoading: model.isScanningBonjour
            )
          }
          .buttonStyle(
            DebagrSecondaryButtonStyle(compact: true, isLoading: model.isScanningBonjour))
        }

        if model.isScanningBonjour && model.localWirelessCandidates.isEmpty {
          HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Browsing local _apple-mobdev2._tcp advertisements…")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 14)
        } else if model.localWirelessCandidates.isEmpty {
          DebagrEmptyState(
            symbolName: "wifi.exclamationmark",
            title: "No Local Wireless Service Found",
            description:
              "Wake and unlock \(selectedDevice?.name ?? "your device") on the same Wi-Fi as this Builder Mac, then scan again."
          ) {
            Button("Scan Local Bonjour") {
              Task { await model.scanLocalWirelessIdentities() }
            }
            .buttonStyle(DebagrSecondaryButtonStyle())
          }
        } else {
          VStack(spacing: 8) {
            ForEach(model.localWirelessCandidates) { record in
              SelectableOptionCard(isSelected: model.setupDraft.selectedBonjourID == record.id) {
                model.setupDraft.selectBonjour(record.id)
              } content: {
                HStack {
                  Image(systemName: "bonjour")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(record.hostTarget)
                      .font(.callout.weight(.semibold))
                    Text("\(record.serviceType) • port \(record.port)")
                      .font(.caption.monospaced())
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                }
              }
            }
          }
        }

        let confirmationBinding = Binding<Bool>(
          get: { model.setupDraft.isHardwareConfirmedForSelection },
          set: { model.setupDraft.setHardwareConfirmed($0) }
        )

        Toggle(
          "I confirm the selected local advertisement belongs to the exact physical device '\(selectedDevice?.name ?? "device")'.",
          isOn: confirmationBinding
        )
        .font(.callout)
        .disabled(selectedBonjour == nil || selectedDevice == nil)
      }
    }
  }

  private var stepReview: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 14) {
        Text("Step 4 · Review & Save Configuration")
          .font(.headline)

        if let dev = selectedDevice, let bonjour = selectedBonjour {
          let formattedPort = UInt16(model.setupDraft.lockdownPortString) ?? 62078
          let endpoint = DebagrFormatters.formatHostPort(
            host: model.setupDraft.manualVPNAddress,
            port: formattedPort
          )
          VStack(spacing: 8) {
            reviewRow("Managed Device", "\(dev.name) (\(dev.model ?? dev.platform.rawValue))")
            reviewRow("Redacted UDID", Redactor.redactUDID(dev.udid), monospaced: true)
            reviewRow("VPN Provider", model.setupDraft.selectedVPNProvider.displayName)
            reviewRow("VPN Endpoint", endpoint, monospaced: true)
            reviewRow("Wireless Service", "\(bonjour.serviceType) (port \(bonjour.port))")
          }
          .padding(12)
          .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

          InlineNotice(
            symbolName: "lock.doc.fill",
            color: .secondary,
            title: "Private Local Storage (0600)",
            message:
              "Saved locally on this Builder Mac only. Raw Apple pairing identifiers and TXT tokens are never included in exported diagnostics."
          )
        }
      }
    }
  }

  private var stepCompleted: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 12) {
          Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 36))
            .foregroundStyle(.green)
            .symbolEffect(.bounce, value: model.setupDraft.step == .completed && !reduceMotion)
          VStack(alignment: .leading, spacing: 3) {
            Text("\(model.setupDraft.savedProfile?.displayName ?? "Device") Saved")
              .font(.title3.weight(.semibold))
            Text("Debagr is now supervising your remote wireless bridge in the background.")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }

        if !model.setupDraft.savedNotes.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(model.setupDraft.savedNotes, id: \.self) { note in
              Text("• \(note)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }

        HStack(spacing: 10) {
          Button("Open Device Overview") {
            model.navigate(to: .overview)
          }
          .buttonStyle(DebagrPrimaryButtonStyle())

          Button("Configure CLI & AI Agents") {
            model.navigate(to: .agentOnboarding)
          }
          .buttonStyle(DebagrSecondaryButtonStyle())
        }
      }
    }
  }

  private var footerBar: some View {
    VStack(spacing: 0) {
      Divider()
      HStack {
        if model.setupDraft.step != .pickDevice {
          Button("Back") {
            if let prev = WirelessSetupStep(rawValue: model.setupDraft.step.rawValue - 1) {
              go(to: prev)
            }
          }
          .buttonStyle(DebagrSecondaryButtonStyle())
          .disabled(model.isSavingProfile)
        }

        Spacer()

        if model.setupDraft.step == .review {
          Button {
            guard let dev = selectedDevice, let bonjour = selectedBonjour else { return }
            Task { await model.verifyAndSaveSetupDraft(device: dev, bonjourRecord: bonjour) }
          } label: {
            DebagrButtonLabel(
              title: model.isSavingProfile ? "Verifying & Saving…" : "Verify & Save Device",
              systemImage: "checkmark.shield",
              isLoading: model.isSavingProfile
            )
          }
          .buttonStyle(DebagrPrimaryButtonStyle(isLoading: model.isSavingProfile))
          .keyboardShortcut(.defaultAction)
          .disabled(selectedDevice == nil || selectedBonjour == nil)
        } else {
          Button("Continue") {
            if let next = WirelessSetupStep(rawValue: model.setupDraft.step.rawValue + 1) {
              go(to: next)
              if next == .captureIdentity && model.localWirelessCandidates.isEmpty {
                Task { await model.scanLocalWirelessIdentities() }
              }
            }
          }
          .buttonStyle(DebagrPrimaryButtonStyle())
          .keyboardShortcut(.defaultAction)
          .disabled(!canAdvanceFromCurrentStep)
        }
      }
      .padding(.horizontal, DesignTokens.pagePadding)
      .padding(.vertical, 14)
      .background(.bar)
    }
  }

  private var canAdvanceFromCurrentStep: Bool {
    switch model.setupDraft.step {
    case .pickDevice:
      return selectedDevice != nil
    case .chooseVPN:
      return IPValidation.isPrivateVPNAddress(model.setupDraft.manualVPNAddress)
        && DebagrFormatters.parseTCPPort(model.setupDraft.lockdownPortString) != nil
    case .captureIdentity:
      return selectedBonjour != nil && model.setupDraft.isHardwareConfirmedForSelection
    case .review, .completed:
      return false
    }
  }

  private func go(to target: WirelessSetupStep) {
    if reduceMotion {
      model.setupDraft.step = target
    } else {
      withAnimation(.snappy(duration: 0.22)) {
        model.setupDraft.step = target
      }
    }
  }

  private func reviewRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
    HStack {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(monospaced ? .caption.monospaced() : .caption.weight(.semibold))
    }
  }

  private func sortedMobilePeers(_ peers: [VPNPeer]) -> [VPNPeer] {
    peers.enumerated().sorted { lhs, rhs in
      let lhsRank = mobileSortRank(lhs.element)
      let rhsRank = mobileSortRank(rhs.element)
      if lhsRank != rhsRank {
        return lhsRank < rhsRank
      }
      return lhs.offset < rhs.offset
    }.map(\.element)
  }

  private func mobileSortRank(_ peer: VPNPeer) -> Int {
    let ip = peer.preferredPrivateIP ?? ""
    let lockdown = ip.isEmpty ? nil : model.peerLockdownIdentities[ip]
    if let lockdown, let dev = selectedDevice, lockdown.compare(to: dev) == .verifiedMatch {
      return 0
    }
    if let dev = selectedDevice {
      if dev.platform == .iPadOS {
        if lockdown?.isIPad == true || peer.isLikelyIPad { return 1 }
        return 2
      } else if dev.platform == .iOS {
        if lockdown?.isIPhone == true || peer.isLikelyIPhone { return 1 }
        if !(lockdown?.isIPad == true || peer.isLikelyIPad) { return 2 }
        return 3
      }
    }
    return 1
  }

  private func shouldShowPlatformMatchBadge(for peer: VPNPeer, in mobilePeers: [VPNPeer]) -> Bool {
    guard mobilePeers.count > 1, let dev = selectedDevice else { return false }
    let matches: (VPNPeer) -> Bool =
      dev.platform == .iPadOS ? { $0.isLikelyIPad } : { $0.isLikelyIPhone }
    return matches(peer) && !mobilePeers.allSatisfy(matches)
  }

  @ViewBuilder
  private func vpnPeerRow(
    _ peer: VPNPeer,
    muted: Bool,
    hasMultipleOwners: Bool,
    mobilePeers: [VPNPeer]
  ) -> some View {
    let ip = peer.preferredPrivateIP ?? ""
    let isSelected =
      !ip.isEmpty
      && model.setupDraft.manualVPNAddress == ip
      && model.setupDraft.selectedTailscaleNodeID == peer.id
    let lockdown = ip.isEmpty ? nil : model.peerLockdownIdentities[ip]
    let verdict = lockdown.flatMap { identity in
      selectedDevice.map { identity.compare(to: $0) }
    }

    SelectableOptionCard(isSelected: isSelected) {
      model.setupDraft.applyDiscoveredPeer(peer)
      model.manualVPNIdentifyMessage = nil
    } content: {
      HStack(spacing: 10) {
        Image(systemName: peerSymbolName(for: peer, lockdown: lockdown))
          .font(.title3)
          .foregroundStyle(muted ? Color.secondary : Color.accentColor)
          .frame(width: 24)

        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(lockdown?.deviceName ?? peer.name)
              .font(.callout.weight(.semibold))
              .foregroundStyle(muted ? .secondary : .primary)
              .lineLimit(1)

            if let probedName = lockdown?.deviceName,
              probedName.caseInsensitiveCompare(peer.name) != .orderedSame
            {
              Text("(\(peer.name))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else if let host = peer.meaningfulHostName {
              Text("(\(host))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            if verdict == .verifiedMatch {
              peerBadge("Verified Match", color: StatusTone.ready.color)
            } else if case .mismatch = verdict {
              peerBadge("Different Device", color: StatusTone.attention.color)
            } else if !muted && shouldShowPlatformMatchBadge(for: peer, in: mobilePeers) {
              peerBadge("Matches Step 1", color: .accentColor)
            }
          }

          HStack(spacing: 5) {
            let isReachableNow = peer.online || peer.active || lockdown != nil
            Circle()
              .fill(isReachableNow ? Color.green : Color.secondary.opacity(0.6))
              .frame(width: 6, height: 6)

            Text(
              peerMetadataSummary(peer, lockdown: lockdown, hasMultipleOwners: hasMultipleOwners)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          }
        }

        Spacer(minLength: 8)

        Text(ip)
          .font(.caption.monospaced())
          .foregroundStyle(muted ? .secondary : .primary)
      }
    }
    .opacity(muted ? (isSelected ? 0.92 : 0.62) : 1.0)
    .help(peerHelpText(peer, lockdown: lockdown))
  }

  private func peerBadge(_ label: String, color: Color) -> some View {
    Text(label)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.14), in: Capsule())
      .overlay(Capsule().strokeBorder(color.opacity(0.32), lineWidth: 0.75))
  }

  private func peerSymbolName(for peer: VPNPeer, lockdown: LockdownDeviceIdentity?) -> String {
    if lockdown?.isIPad == true || peer.isLikelyIPad {
      return "ipad"
    }
    if lockdown?.isIPhone == true || peer.isLikelyAppleMobileDevice {
      return "iphone"
    }
    if peer.isLikelyMacOSDevice {
      return "laptopcomputer"
    }
    if peer.os.lowercased().contains("linux") {
      return "server.rack"
    }
    return "network"
  }

  private func peerMetadataSummary(
    _ peer: VPNPeer,
    lockdown: LockdownDeviceIdentity?,
    hasMultipleOwners: Bool
  ) -> String {
    let statusText: String
    if peer.active {
      statusText = "Active"
    } else if peer.online {
      statusText = "Online"
    } else if lockdown != nil {
      statusText = "Reachable"
    } else if let lastSeen = peer.lastSeen {
      statusText = "Last seen \(DebagrFormatters.relativeTimestamp(from: lastSeen))"
    } else {
      statusText = "Offline"
    }

    var parts = [statusText]
    let trimmedOS = peer.os.trimmingCharacters(in: .whitespacesAndNewlines)

    if let lockdown {
      if let productType = lockdown.productType {
        parts.append(productType)
      }
      if let osLabel = lockdown.osDisplayLabel {
        parts.append(osLabel)
      } else if !trimmedOS.isEmpty {
        parts.append(trimmedOS)
      }
    } else if !trimmedOS.isEmpty {
      parts.append(trimmedOS)
    }

    if hasMultipleOwners, let owner = peer.ownerName {
      parts.append(owner)
    }

    if !peer.tags.isEmpty {
      parts.append(peer.tags.joined(separator: ", "))
    }

    return parts.joined(separator: " • ")
  }

  private func peerHelpText(_ peer: VPNPeer, lockdown: LockdownDeviceIdentity?) -> String {
    var lines: [String] = []
    if let dns = peer.dnsName?.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: ".")),
      !dns.isEmpty
    {
      lines.append("MagicDNS: \(dns)")
    }
    if let host = peer.hostName, !host.isEmpty {
      lines.append("Hostname: \(host)")
    }
    if !peer.addresses.isEmpty {
      lines.append("VPN IPs: \(peer.addresses.joined(separator: ", "))")
    }
    if let relay = peer.relay {
      lines.append("Relay: \(relay)")
    }
    if let lockdown {
      var hwParts = [
        lockdown.deviceName, lockdown.productType, lockdown.hardwareModel, lockdown.osDisplayLabel,
      ]
      .compactMap { $0 }
      if let arch = lockdown.cpuArchitecture {
        hwParts.append(arch)
      }
      if !hwParts.isEmpty {
        lines.append("Lockdown: \(hwParts.joined(separator: " · "))")
      }
    }
    return lines.joined(separator: "\n")
  }

  @ViewBuilder
  private func manualIdentifySection(for ip: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Button {
          Task { await model.identifyManualVPNDevice() }
        } label: {
          DebagrButtonLabel(
            title: model.isIdentifyingManualVPNAddress ? "Identifying…" : "Identify Device",
            systemImage: "iphone.gen3.radiowaves.left.and.right",
            isLoading: model.isIdentifyingManualVPNAddress
          )
        }
        .buttonStyle(
          DebagrSecondaryButtonStyle(compact: true, isLoading: model.isIdentifyingManualVPNAddress)
        )

        if let identity = model.peerLockdownIdentities[ip] {
          if let dev = selectedDevice {
            switch identity.compare(to: dev) {
            case .verifiedMatch:
              Label(
                "Verified match: \(identity.compactSummary)",
                systemImage: "checkmark.seal.fill"
              )
              .font(.caption)
              .foregroundStyle(StatusTone.ready.color)
            case .mismatch:
              Label(
                "Answered as \(identity.compactSummary)",
                systemImage: "exclamationmark.triangle.fill"
              )
              .font(.caption)
              .foregroundStyle(StatusTone.attention.color)
            case .inconclusive:
              Label(
                "Answered over VPN: \(identity.compactSummary)",
                systemImage: "info.circle"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          } else {
            Label(
              "Answered over VPN: \(identity.compactSummary)",
              systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(StatusTone.ready.color)
          }
        } else if let note = model.manualVPNIdentifyMessage {
          Label(note, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      if let identity = model.peerLockdownIdentities[ip],
        let dev = selectedDevice,
        case .mismatch(let reason) = identity.compare(to: dev)
      {
        InlineNotice(
          symbolName: "exclamationmark.triangle.fill",
          color: .orange,
          title: "Answered as \(identity.compactSummary)",
          message: reason
        )
      }
    }
  }
}
