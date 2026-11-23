import AppKit
import DebagrCore
import SwiftUI

public struct MenuBarView: View {
  @ObservedObject var model: AppModel
  let onOpenMainWindow: () -> Void

  public init(model: AppModel, onOpenMainWindow: @escaping () -> Void) {
    self.model = model
    self.onOpenMainWindow = onOpenMainWindow
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: model.menuBarIconName)
          .font(.title2)
          .foregroundStyle(statusColor)
          .frame(width: 28)

        VStack(alignment: .leading, spacing: 2) {
          Text(model.config.managedDevice?.displayName ?? "No Device Configured")
            .font(.headline)
          Text(model.bridgeSnapshot.state.displayTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        statusRow(
          "VPN Route", value: model.config.managedDevice?.vpn.provider.displayName ?? "Not set")
        statusRow("Lock State", value: model.readiness?.lockState.rawValue.capitalized ?? "Unknown")
        statusRow("Bridge Note", value: model.bridgeSnapshot.lastTransitionReason)
      }
      .font(.caption)

      Divider()

      VStack(spacing: 6) {
        Button {
          Task { await model.refreshReadiness() }
        } label: {
          Label("Check Readiness Now", systemImage: "checkmark.shield")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(model.isBusy)

        Button {
          Task { await model.toggleBridgePaused() }
        } label: {
          Label(
            model.isBridgePaused ? "Resume Bridge" : "Pause Bridge",
            systemImage: model.isBridgePaused ? "play.circle" : "pause.circle"
          )
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(model.config.managedDevice == nil)

        Button {
          model.copyToPasteboard("ssh <builder-mac> '\(model.binaryPathForAgents)' ready")
          model.statusBanner = "Copied SSH check command."
        } label: {
          Label("Copy SSH Check Command", systemImage: "doc.on.doc")
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        Button {
          onOpenMainWindow()
        } label: {
          Label("Open Debagr...", systemImage: "macwindow")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .buttonStyle(.bordered)

      Divider()

      HStack {
        Text("v\(DebagrVersion.current)")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Quit Debagr") {
          Task {
            await model.shutdownBridge()
            NSApplication.shared.terminate(nil)
          }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .frame(width: 320)
  }

  private var statusColor: Color {
    switch model.bridgeSnapshot.state {
    case .bridgingActive, .nativeLocalStandby: .green
    case .deviceOffline, .vpnUnavailable, .error: .orange
    case .paused, .probingVPN, .unconfigured: .secondary
    }
  }

  private func statusRow(_ label: String, value: String) -> some View {
    HStack(alignment: .top) {
      Text(label)
        .foregroundStyle(.secondary)
        .frame(width: 82, alignment: .leading)
      Text(value)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
    }
  }
}
