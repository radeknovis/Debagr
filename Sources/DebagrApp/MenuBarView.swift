import AppKit
import DebagrCore
import SwiftUI

public struct MenuBarView: View {
  @ObservedObject var model: AppModel
  let onOpenMainWindow: () -> Void
  let onOpenSettings: () -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hoveredRow: String?

  public init(
    model: AppModel,
    onOpenMainWindow: @escaping () -> Void,
    onOpenSettings: @escaping () -> Void
  ) {
    self.model = model
    self.onOpenMainWindow = onOpenMainWindow
    self.onOpenSettings = onOpenSettings
  }

  public var body: some View {
    let verdict = model.verdict

    VStack(alignment: .leading, spacing: 12) {
      if let device = model.config.managedDevice {
        configuredHeader(device: device, verdict: verdict)
        BridgeTopologyView(
          style: .compact,
          config: model.config,
          snapshot: model.bridgeSnapshot,
          readiness: model.readiness,
          isChecking: model.isCheckingReadiness
        )
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

        metricsGrid(device: device)
        primaryCheckSection
      } else {
        unconfiguredSection
      }

      Divider()

      VStack(spacing: 2) {
        if model.config.managedDevice != nil {
          menuRow(
            id: "pause",
            title: model.isBridgePaused ? "Resume Bridge" : "Pause Bridge",
            systemImage: model.isBridgePaused ? "play.circle" : "pause.circle",
            shortcut: nil
          ) {
            Task { await model.toggleBridgePaused() }
          }
        }

        menuRow(
          id: "open",
          title: "Open Debagr…",
          systemImage: "macwindow",
          shortcut: nil
        ) {
          dismiss()
          onOpenMainWindow()
        }

        OpenSettingsButton {
          onOpenSettings()
        } afterOpen: {
          dismiss()
        } label: {
          menuRowLabel(
            id: "settings",
            title: "Settings…",
            systemImage: "gearshape",
            shortcut: "⌘,"
          )
        }
        .buttonStyle(.plain)

        Divider()
          .padding(.vertical, 4)

        menuRow(
          id: "quit",
          title: "Quit Debagr",
          systemImage: "power",
          shortcut: "⌘Q"
        ) {
          Task {
            await model.shutdownBridge()
            NSApplication.shared.terminate(nil)
          }
        }
        .keyboardShortcut("q", modifiers: .command)
      }
    }
    .padding(14)
    .frame(width: 344)
    .background(.regularMaterial)
  }

  private func configuredHeader(
    device: ManagedDeviceProfile,
    verdict: DeviceStatusVerdict
  ) -> some View {
    HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(device.displayName)
          .font(.headline)
          .lineLimit(1)
        Text("\(device.model ?? device.platform.rawValue) • \(device.vpn.provider.displayName)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      StatusPill(
        tone: verdict.tone,
        symbolName: verdict.heroSymbol,
        label: verdict.pillLabel,
        compact: true
      )
    }
  }

  private func metricsGrid(device: ManagedDeviceProfile) -> some View {
    HStack(spacing: 8) {
      metricTile(
        label: "Route",
        value: model.bridgeSnapshot.state == .nativeLocalStandby
          ? (model.bridgeSnapshot.nativeTransport == .wired ? "Direct USB" : "Local Wi-Fi")
          : device.vpn.provider.displayName,
        date: nil
      )
      metricTile(
        label: "Screen Lock",
        value: DebagrFormatters.humanLockState(model.readiness?.lockState),
        date: model.lastReadinessCheckedAt
      )
    }
  }

  private func metricTile(label: String, value: String, date: Date?) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
      if date != nil {
        RelativeTimeText(date: date, prefix: "Checked ")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      .quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var primaryCheckSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        Task { await model.refreshReadiness() }
      } label: {
        HStack(spacing: 8) {
          ZStack {
            if model.isCheckingReadiness {
              ProgressView()
                .controlSize(.small)
            } else {
              Image(systemName: "checkmark.shield")
            }
          }
          .frame(width: 16, height: 16)
          Text(model.isCheckingReadiness ? "Checking Readiness…" : "Check Again")
            .fontWeight(.semibold)
          Spacer()
          if !model.isCheckingReadiness {
            Text("⌘R")
              .font(.caption2.weight(.medium))
              .foregroundStyle(Color.white.opacity(0.85))
              .padding(.horizontal, 5)
              .padding(.vertical, 2)
              .background(
                Color.white.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
              )
          }
        }
      }
      .buttonStyle(DebagrPrimaryButtonStyle(fullWidth: true, isLoading: model.isCheckingReadiness))
      .keyboardShortcut("r", modifiers: .command)

      if let blocker = model.readiness?.blockers.first {
        Text(blocker.message)
          .font(.caption2)
          .foregroundStyle(.primary)
          .lineLimit(2)
      } else if let err = model.errorBanner {
        Text(err)
          .font(.caption2)
          .foregroundStyle(.red)
          .lineLimit(2)
      }
    }
  }

  private var unconfiguredSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "iphone.radiowaves.left.and.right")
          .font(.title2)
          .foregroundStyle(Color.accentColor)
        VStack(alignment: .leading, spacing: 2) {
          Text("Set Up Remote Device")
            .font(.headline)
          Text("Connect your already-paired iPhone or iPad once while nearby.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Button {
        model.navigate(to: .wirelessSetup)
        dismiss()
        onOpenMainWindow()
      } label: {
        Text("Set Up Device…")
      }
      .buttonStyle(DebagrPrimaryButtonStyle(fullWidth: true))
    }
  }

  private func menuRow(
    id: String,
    title: String,
    systemImage: String,
    shortcut: String?,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      menuRowLabel(id: id, title: title, systemImage: systemImage, shortcut: shortcut)
    }
    .buttonStyle(.plain)
  }

  private func menuRowLabel(
    id: String,
    title: String,
    systemImage: String,
    shortcut: String?
  ) -> some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .frame(width: 16)
        .foregroundStyle(.secondary)
      Text(title)
        .font(.callout)
      Spacer()
      if let shortcut {
        Text(shortcut)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(hoveredRow == id ? Color.primary.opacity(0.08) : Color.clear)
    )
    .contentShape(Rectangle())
    .onHover { inside in
      if reduceMotion {
        hoveredRow = inside ? id : nil
      } else {
        withAnimation(.easeOut(duration: 0.12)) {
          hoveredRow = inside ? id : nil
        }
      }
    }
  }
}
