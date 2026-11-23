import DebagrCore
import SwiftUI

public struct OverviewView: View {
  @ObservedObject var model: AppModel
  @State private var showingForgetConfirm = false

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        headerSection
        managedDeviceSection
        savedVerificationSection
        recentReceiptsSection
      }
      .padding(24)
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
        "Removes saved VPN endpoint and wireless identity from this Mac. Apple pairing in Xcode/CoreDevice is unaffected."
      )
    }
  }

  private var headerSection: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Device & Wireless Bridge")
          .font(.title2.bold())
        Text(
          "Builder Mac owns Apple pairing & signing; Debagr bridges your roaming device over private VPN."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      Spacer()
      HStack(spacing: 8) {
        Button {
          Task { await model.copyRedactedDiagnostics() }
        } label: {
          Label("Copy Redacted Diagnostics", systemImage: "doc.on.doc")
        }
        .disabled(model.isBusy)

        Button {
          Task { await model.refreshReadiness() }
        } label: {
          Label("Verify Saved Connection", systemImage: "checkmark.shield")
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isBusy)
      }
    }
  }

  private var managedDeviceSection: some View {
    GroupBox {
      if let device = model.config.managedDevice {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .top) {
            Image(systemName: device.platform == .iPadOS ? "ipad" : "iphone")
              .font(.system(size: 32))
              .foregroundStyle(Color.accentColor)
              .frame(width: 44)

            VStack(alignment: .leading, spacing: 3) {
              Text(device.displayName)
                .font(.headline)
              Text(
                "\(device.model ?? device.platform.rawValue) • UDID \(Redactor.redactUDID(device.udid))"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              Text(
                "VPN: \(device.vpn.provider.displayName) (\(device.vpn.address):\(device.vpn.lockdownPort))"
              )
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
              Text(model.bridgeSnapshot.state.displayTitle)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
              Button("Forget Device", role: .destructive) {
                showingForgetConfirm = true
              }
              .buttonStyle(.borderless)
              .font(.caption)
            }
          }

          Divider()

          HStack(spacing: 16) {
            LabeledContent("Bridge State", value: model.bridgeSnapshot.lastTransitionReason)
            Spacer()
            Button(model.isBridgePaused ? "Resume Bridge" : "Pause Bridge") {
              Task { await model.toggleBridgePaused() }
            }
          }
          .font(.caption)
        }
        .padding(8)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Text("No Remote Device Configured")
            .font(.headline)
          Text(
            "Connect or bring your already-paired iPhone or iPad nearby once, then run Wireless Setup to save its VPN route and local wireless identity."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          Button("Start Wireless Setup") {
            model.selectedSection = .wirelessSetup
          }
          .buttonStyle(.borderedProminent)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    } label: {
      Label("Managed Device (One Device at a Time)", systemImage: "iphone.gen3")
    }
  }

  private var savedVerificationSection: some View {
    GroupBox {
      if let readiness = model.readiness {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Label(
              readiness.ready ? "Ready for Deployment" : "Action Needed",
              systemImage: readiness.ready
                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(readiness.ready ? .green : .orange)
            Spacer()
            Text("Path: \(readiness.connectionPath) • Lock: \(readiness.lockState.rawValue)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          ForEach(Array(readiness.checks.enumerated()), id: \.offset) { _, item in
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: item.passed ? "checkmark.circle" : "xmark.circle")
                .foregroundStyle(item.passed ? .green : .red)
              VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                  .font(.caption.bold())
                Text(item.detail)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }

          if !readiness.blockers.isEmpty {
            Divider()
            ForEach(Array(readiness.blockers.enumerated()), id: \.offset) { _, blocker in
              VStack(alignment: .leading, spacing: 4) {
                Text("[\(blocker.code.rawValue)] \(blocker.message)")
                  .font(.caption.bold())
                  .foregroundStyle(.orange)
                ForEach(blocker.nextSteps, id: \.self) { step in
                  Text("• \(step)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        .padding(8)
      } else {
        HStack {
          Text(
            "Run “Verify Saved Connection” to probe VPN reachability, CoreDevice pairing, Developer Mode, and lock state."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          Spacer()
        }
        .padding(8)
      }
    } label: {
      Label("Saved Connection Verification", systemImage: "checklist")
    }
  }

  private var recentReceiptsSection: some View {
    GroupBox {
      if model.recentReceipts.isEmpty {
        Text("No local deployment receipts yet.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(model.recentReceipts.prefix(10)) { receipt in
            HStack(alignment: .center, spacing: 10) {
              Image(systemName: receiptIcon(for: receipt.outcome))
                .foregroundStyle(receiptColor(for: receipt.outcome))
              VStack(alignment: .leading, spacing: 2) {
                Text(
                  "\(receipt.operation.rawValue.uppercased()) • \(receipt.bundleIdentifier ?? "app")"
                )
                .font(.caption.bold())
                Text(receipt.summary)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer()
              Text("\(receipt.durationMs) ms")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Divider()
          }
        }
        .padding(8)
      }
    } label: {
      Label("Recent Deployment Receipts", systemImage: "doc.text.magnifyingglass")
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
