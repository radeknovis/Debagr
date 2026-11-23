import DebagrCore
import SwiftUI

public struct OverviewView: View {
  @ObservedObject var model: AppModel
  @State private var showingForgetConfirm = false
  @State private var showingDiagnosticsSheet = false
  @State private var expandedReceiptIDs: Set<UUID> = []

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        headerRow

        if let device = model.config.managedDevice {
          heroCard(device: device, verdict: model.verdict)
          checksAndBlockersSection
          receiptsSection
        } else {
          unconfiguredHero
        }
      }
      .frame(maxWidth: DesignTokens.maxContentWidth, alignment: .leading)
      .frame(maxWidth: .infinity)
      .padding(DesignTokens.pagePadding)
    }
    .onAppear {
      if model.config.managedDevice != nil && model.readiness == nil && !model.isCheckingReadiness {
        Task { await model.refreshReadiness(announce: false) }
      }
    }
    .confirmationDialog(
      "Forget Managed Device?",
      isPresented: $showingForgetConfirm,
      titleVisibility: .visible
    ) {
      Button("Forget Device", role: .destructive) {
        Task { await model.forgetManagedDevice() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Removes the saved VPN endpoint and wireless identity from this Builder Mac. Apple pairing in Xcode/CoreDevice stays untouched."
      )
    }
    .sheet(isPresented: $showingDiagnosticsSheet) {
      diagnosticsPreviewSheet
    }
  }

  private var headerRow: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Device & Bridge Overview")
          .font(.title2.weight(.semibold))
        Text(
          "This Builder Mac keeps Apple trust and signing; Debagr bridges your pocket device over private VPN."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      Spacer()
      if model.config.managedDevice != nil {
        Menu {
          Button("Re-run Wireless Setup…") {
            model.setupDraft.resetForNewSetup()
            model.navigate(to: .wirelessSetup)
          }
          Button("Preview Redacted Diagnostics…") {
            showingDiagnosticsSheet = true
          }
          Divider()
          Button("Forget Device…", role: .destructive) {
            showingForgetConfirm = true
          }
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(.title3)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Device actions")
      }
    }
  }

  private func heroCard(device: ManagedDeviceProfile, verdict: DeviceStatusVerdict) -> some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
              Text(verdict.heroTitle)
                .font(.headline)
              StatusPill(
                tone: verdict.tone,
                symbolName: verdict.heroSymbol,
                label: verdict.pillLabel
              )
            }
            Text(model.bridgeSnapshot.lastTransitionReason)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 2) {
            Text("Last Checked")
              .font(.caption2)
              .foregroundStyle(.secondary)
            RelativeTimeText(date: model.lastReadinessCheckedAt)
              .font(.caption.weight(.medium))
          }
        }

        BridgeTopologyView(
          style: .hero,
          config: model.config,
          snapshot: model.bridgeSnapshot,
          readiness: model.readiness,
          isChecking: model.isCheckingReadiness
        )
        .padding(.vertical, 6)

        Divider()

        HStack(spacing: 16) {
          metadataItem(label: "Device", value: device.displayName)
          metadataItem(label: "UDID", value: Redactor.redactUDID(device.udid), monospaced: true)
          metadataItem(
            label: "VPN Endpoint",
            value: DebagrFormatters.formatHostPort(
              host: device.vpn.address,
              port: device.vpn.lockdownPort
            ),
            monospaced: true
          )
          Spacer()
          Button {
            Task { await model.refreshReadiness() }
          } label: {
            DebagrButtonLabel(
              title: model.isCheckingReadiness ? "Checking…" : "Verify Connection",
              systemImage: "checkmark.shield",
              isLoading: model.isCheckingReadiness
            )
          }
          .buttonStyle(DebagrPrimaryButtonStyle(isLoading: model.isCheckingReadiness))
        }
      }
    }
  }

  private func metadataItem(label: String, value: String, monospaced: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value)
        .font(monospaced ? .caption.monospaced() : .caption.weight(.medium))
        .lineLimit(1)
    }
  }

  private var checksAndBlockersSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Readiness Checks")
          .font(.headline)
        Spacer()
        if let readiness = model.readiness {
          Text(
            "Path: \(readiness.connectionPath) • Lock: \(DebagrFormatters.humanLockState(readiness.lockState))"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      if let readiness = model.readiness {
        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
          spacing: 10
        ) {
          ForEach(Array(readiness.checks.enumerated()), id: \.offset) { _, item in
            SurfaceCard(padding: 12) {
              HStack(alignment: .top, spacing: 10) {
                Image(
                  systemName: item.passed ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(item.passed ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                  Text(DebagrFormatters.humanCheckTitle(item.name))
                    .font(.caption.weight(.semibold))
                  Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
            }
          }
        }

        if !readiness.blockers.isEmpty {
          ForEach(Array(readiness.blockers.enumerated()), id: \.offset) { _, blocker in
            SurfaceCard(padding: 14) {
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                  Text(blocker.message)
                    .font(.callout.weight(.semibold))
                  Spacer()
                  Text(blocker.code.rawValue)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.75))
                    .foregroundStyle(.primary)
                }
                if !blocker.nextSteps.isEmpty {
                  VStack(alignment: .leading, spacing: 3) {
                    ForEach(blocker.nextSteps, id: \.self) { step in
                      Text("• \(step)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                  }
                }
              }
            }
          }
        }
      } else {
        SurfaceCard {
          HStack(spacing: 10) {
            if model.isCheckingReadiness {
              ProgressView().controlSize(.small)
              Text("Probing VPN endpoint, CoreDevice pairing, and device lock state…")
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
              Text("Click Verify Connection above to run live readiness checks.")
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }

  private var receiptsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Recent Deployments")
          .font(.headline)
        Spacer()
        if !model.recentReceipts.isEmpty {
          Text("Click any row to inspect outcome details")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }

      if model.recentReceipts.isEmpty {
        SurfaceCard {
          DebagrEmptyState(
            symbolName: "doc.text.magnifyingglass",
            title: "No Deployment Receipts Yet",
            description:
              "Install or deploy a signed iphoneos build via the Debagr CLI or MCP server to record verified outcomes here."
          )
        }
      } else {
        VStack(spacing: 8) {
          ForEach(model.recentReceipts.prefix(12)) { receipt in
            receiptRow(receipt)
          }
        }
      }
    }
  }

  private func receiptRow(_ receipt: DeploymentReceipt) -> some View {
    let isExpanded = expandedReceiptIDs.contains(receipt.id)
    let color = receiptColor(for: receipt.outcome)

    return SurfaceCard(padding: 12) {
      VStack(alignment: .leading, spacing: 10) {
        Button {
          withAnimation(.snappy(duration: 0.22)) {
            if isExpanded {
              expandedReceiptIDs.remove(receipt.id)
            } else {
              expandedReceiptIDs.insert(receipt.id)
            }
          }
        } label: {
          HStack(spacing: 10) {
            Image(systemName: receiptIcon(for: receipt.outcome))
              .foregroundStyle(color)
              .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(DebagrFormatters.humanOperation(receipt.operation))
                  .font(.callout.weight(.semibold))
                Text(receipt.bundleIdentifier ?? "app")
                  .font(.callout.monospaced())
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                  .truncationMode(.middle)
                HStack(spacing: 4) {
                  Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                  Text(DebagrFormatters.humanOutcome(receipt.outcome))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(color.opacity(0.14), in: Capsule())
              }
              Text(receipt.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
              RelativeTimeText(date: receipt.timestamp)
                .font(.caption2)
                .foregroundStyle(.secondary)
              Text(DebagrFormatters.humanDuration(ms: receipt.durationMs))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if isExpanded {
          Divider()
          LazyVGrid(
            columns: [
              GridItem(.flexible()),
              GridItem(.flexible()),
              GridItem(.flexible()),
            ],
            alignment: .leading,
            spacing: 8
          ) {
            receiptDetail("Device", "\(receipt.deviceName) (\(receipt.deviceUDIDRedacted))")
            receiptDetail("Bundle", receipt.appPathName ?? receipt.bundleIdentifier ?? "—")
            receiptDetail(
              "Version / Build",
              [receipt.appVersion, receipt.appBuild].compactMap { $0 }.joined(separator: " / ")
                .ifEmpty("—")
            )
            receiptDetail("Installed & Verified", receipt.verifiedInstalled ? "Yes" : "No")
            receiptDetail(
              "Launched",
              receipt.launched ? (receipt.pid.map { "Yes (PID \($0))" } ?? "Yes") : "No"
            )
            receiptDetail("Error Code", receipt.errorCode?.rawValue ?? "None")
          }
        }
      }
    }
  }

  private func receiptDetail(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.caption.monospaced()).lineLimit(1)
    }
  }

  private var unconfiguredHero: some View {
    SurfaceCard {
      DebagrEmptyState(
        symbolName: "iphone.radiowaves.left.and.right",
        title: "No Managed Device Configured",
        description:
          "Bring your already-paired iPhone or iPad nearby on the same Wi-Fi once and walk through Wireless Setup so Debagr can bridge it across your private VPN."
      ) {
        Button("Start Wireless Setup") {
          model.navigate(to: .wirelessSetup)
        }
        .buttonStyle(DebagrPrimaryButtonStyle())
      }
    }
  }

  private var diagnosticsPreviewSheet: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Redacted Diagnostics Preview")
            .font(.title3.weight(.semibold))
          Text(
            "UDIDs, private VPN octets, and Apple Bonjour pairing identifiers are stripped before copying."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Done") { showingDiagnosticsSheet = false }
          .buttonStyle(DebagrSecondaryButtonStyle(compact: true))
          .keyboardShortcut(.cancelAction)
      }

      if model.isLoadingDiagnostics {
        VStack(spacing: 10) {
          Spacer()
          ProgressView("Generating redacted diagnostics…")
          Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let err = model.redactedDiagnosticsError {
        VStack(alignment: .leading, spacing: 12) {
          InlineNotice(
            symbolName: "exclamationmark.triangle.fill",
            color: .red,
            title: "Failed Generating Diagnostics",
            message: err
          )
          Button("Retry") {
            Task { _ = await model.loadRedactedDiagnosticsPreview() }
          }
          .buttonStyle(DebagrPrimaryButtonStyle())
          Spacer()
        }
      } else if let preview = model.redactedDiagnosticsPreview {
        TerminalCommandField(
          code: preview,
          contextTag: "Redacted JSON (Safe to Share)",
          syntax: .json,
          wrapLines: true,
          maxHeight: .infinity
        )
      }
    }
    .padding(20)
    .frame(width: 640, height: 480)
    .task {
      _ = await model.loadRedactedDiagnosticsPreview()
    }
  }

  private func receiptIcon(for outcome: DeploymentOutcome) -> String {
    switch outcome {
    case .succeeded: "checkmark.circle.fill"
    case .partialSuccessLaunchFailed: "exclamationmark.circle.fill"
    case .uncertainTimeout: "clock.badge.questionmark"
    case .failed: "xmark.octagon.fill"
    }
  }

  private func receiptColor(for outcome: DeploymentOutcome) -> Color {
    switch outcome {
    case .succeeded: .green
    case .partialSuccessLaunchFailed, .uncertainTimeout: .orange
    case .failed: .red
    }
  }
}

extension String {
  fileprivate func ifEmpty(_ fallback: String) -> String {
    isEmpty ? fallback : self
  }
}
