import AppKit
import DebagrCore
import SwiftUI

public enum SettingsPane: String, CaseIterable, Identifiable {
  case general
  case bridge
  case privacy

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .general: "General"
    case .bridge: "Bridge"
    case .privacy: "Privacy & Storage"
    }
  }

  public var subtitle: String {
    switch self {
    case .general: "Startup behavior, CLI symlink status, and app metadata."
    case .bridge: "Native transport yielding, probe cadence, and deployment timeouts."
    case .privacy: "Zero-cloud posture, strict local permissions, and redacted diagnostics."
    }
  }

  public var systemImage: String {
    switch self {
    case .general: "gearshape.fill"
    case .bridge: "antenna.radiowaves.left.and.right"
    case .privacy: "lock.shield.fill"
    }
  }

  public var badgeColor: Color {
    switch self {
    case .general: .blue
    case .bridge: .teal
    case .privacy: .green
    }
  }
}

public struct PreferencesView: View {
  @ObservedObject var model: AppModel
  public let pane: SettingsPane
  @State private var inspectionRefreshTick = 0
  @Environment(\.colorScheme) private var colorScheme

  public init(model: AppModel, pane: SettingsPane) {
    self.model = model
    self.pane = pane
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        paneHeader(for: pane)

        switch pane {
        case .general:
          generalPane
        case .bridge:
          bridgePane
        case .privacy:
          privacyPane
        }
      }
      .frame(maxWidth: DesignTokens.maxContentWidth, alignment: .leading)
      .frame(maxWidth: .infinity)
      .padding(DesignTokens.pagePadding)
    }
    .onAppear {
      model.reloadLocalStores()
      inspectionRefreshTick &+= 1
    }
    .onChange(of: pane) { _, _ in
      model.reloadLocalStores()
      inspectionRefreshTick &+= 1
    }
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        .map { _ in () }
    ) {
      model.reloadLocalStores()
      inspectionRefreshTick &+= 1
    }
  }

  private func paneHeader(for tab: SettingsPane) -> some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(tab.badgeColor.gradient)
        Image(systemName: tab.systemImage)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Color.white)
      }
      .frame(width: 34, height: 34)

      VStack(alignment: .leading, spacing: 2) {
        Text(tab.title)
          .font(.title3.weight(.semibold))
        Text(tab.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.bottom, 2)
  }

  // MARK: - General Pane

  private var generalPane: some View {
    let launchBinding = Binding<Bool>(
      get: { model.launchAtLoginStatus.isEnabled },
      set: { model.setLaunchAtLogin($0) }
    )
    let _ = inspectionRefreshTick
    let symlinkStatus = model.cliSymlinkStatus

    return VStack(alignment: .leading, spacing: 14) {
      SurfaceCard {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 8) {
                Text("Launch Debagr at Login")
                  .font(.headline)
                loginStatusPill
              }
              Text("Keep your private VPN bridge and menu-bar monitor active automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Launch Debagr at Login", isOn: launchBinding)
              .labelsHidden()
              .toggleStyle(.switch)
          }

          Divider()

          HStack {
            Text(model.launchAtLoginStatus.descriptionText)
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            if model.launchAtLoginStatus == .requiresApproval
              || model.launchAtLoginStatus.isUnavailable
            {
              Button("Open Login Items…") {
                model.openLoginItemsSettings()
              }
              .buttonStyle(DebagrSecondaryButtonStyle(compact: true))
            }
          }
        }
      }

      SurfaceCard {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 8) {
                Text("CLI & Agent Binary")
                  .font(.headline)
                symlinkStatusPill(for: symlinkStatus)
              }
              Text("Agents and SSH callers invoke Debagr at /usr/local/bin/debagr over stdio.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Copy Path") {
              if model.copyToPasteboard(model.binaryPathForAgents) {
                model.showToast("Copied executable path.")
              }
            }
            .buttonStyle(DebagrSecondaryButtonStyle(compact: true))
          }

          HStack(spacing: 8) {
            Image(systemName: "terminal")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(DebagrFormatters.shortenedHomePath(model.binaryPathForAgents))
              .font(.caption.monospaced())
              .textSelection(.enabled)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: DesignTokens.compactControlRadius, style: .continuous)
              .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045))
          )

          if case .linkedElsewhere(let target) = symlinkStatus {
            Text("Current /usr/local/bin/debagr target: \(target)")
              .font(.caption2.monospaced())
              .foregroundStyle(StatusTone.attention.color)
              .lineLimit(1)
              .truncationMode(.middle)
          }

          if case .linkedToCurrent = symlinkStatus {
            EmptyView()
          } else {
            let quotedBinary = DebagrFormatters.shellSingleQuote(model.binaryPathForAgents)
            TerminalCommandField(
              code: "sudo ln -sf \(quotedBinary) /usr/local/bin/debagr",
              contextTag: "Link Binary onto PATH",
              syntax: .shell
            )
          }
        }
      }

      SurfaceCard {
        VStack(alignment: .leading, spacing: 10) {
          Text("Identity & Compatibility")
            .font(.headline)

          HStack(spacing: 10) {
            metadataTile(
              title: "Debagr Version",
              value: "v\(DebagrVersion.current)",
              monospaced: true
            )
            metadataTile(
              title: "CLI JSON Schema",
              value: "v\(DebagrVersion.schemaVersion)",
              monospaced: true
            )
            metadataTile(
              title: "Managed Device",
              value: model.config.managedDevice?.displayName ?? "Not Configured",
              monospaced: false
            )
          }
        }
      }
    }
  }

  private var loginStatusPill: some View {
    switch model.launchAtLoginStatus {
    case .enabled:
      StatusPill(tone: .ready, symbolName: "checkmark.circle.fill", label: "Enabled", compact: true)
    case .disabled:
      StatusPill(tone: .idle, symbolName: "minus.circle", label: "Disabled", compact: true)
    case .requiresApproval:
      StatusPill(
        tone: .attention,
        symbolName: "exclamationmark.triangle.fill",
        label: "Needs Approval",
        compact: true
      )
    case .unavailable:
      StatusPill(
        tone: .attention,
        symbolName: "info.circle.fill",
        label: "Unavailable",
        compact: true
      )
    }
  }

  private func symlinkStatusPill(for status: CLISymlinkStatus) -> some View {
    switch status {
    case .linkedToCurrent:
      StatusPill(tone: .ready, symbolName: "link.circle.fill", label: "Linked", compact: true)
    case .linkedElsewhere:
      StatusPill(
        tone: .attention,
        symbolName: "exclamationmark.triangle.fill",
        label: "Different Target",
        compact: true
      )
    case .notLinked:
      StatusPill(tone: .idle, symbolName: "link.badge.plus", label: "Not Linked", compact: true)
    }
  }

  private func metadataTile(title: String, value: String, monospaced: Bool) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value)
        .font(monospaced ? .callout.weight(.semibold).monospaced() : .callout.weight(.semibold))
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
    )
  }

  // MARK: - Bridge Pane

  private var bridgePane: some View {
    let prefs = model.config.preferences
    let yieldBinding = Binding<Bool>(
      get: { prefs.yieldWhenNativelyLocal },
      set: { next in model.updatePreferences { $0.yieldWhenNativelyLocal = next } }
    )
    let intervalBinding = Binding<Int>(
      get: { prefs.healthCheckIntervalSeconds },
      set: { next in model.updatePreferences { $0.healthCheckIntervalSeconds = next } }
    )
    let timeoutBinding = Binding<Int>(
      get: { prefs.defaultDeployTimeoutSeconds },
      set: { next in model.updatePreferences { $0.defaultDeployTimeoutSeconds = next } }
    )

    let standardIntervals = [10, 15, 30, 60]
    let standardTimeouts = [60, 180, 300, 600]
    let isDefaultPreferences =
      prefs.yieldWhenNativelyLocal
      && prefs.healthCheckIntervalSeconds == 15
      && prefs.defaultDeployTimeoutSeconds == 180

    return VStack(alignment: .leading, spacing: 14) {
      SurfaceCard {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Yield When Locally Reachable")
                .font(.headline)
              Text(
                "Pause Debagr's VPN advertisement whenever CoreDevice detects direct USB or local Wi-Fi."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Yield When Locally Reachable", isOn: yieldBinding)
              .labelsHidden()
              .toggleStyle(.switch)
          }

          if prefs.yieldWhenNativelyLocal {
            HStack(spacing: 8) {
              routePostureBadge(
                title: "Nearby (USB / Wi-Fi)",
                route: "Native CoreDevice",
                tone: .local
              )
              routePostureBadge(
                title: "Away",
                route: "Private VPN Bridge",
                tone: .probing
              )
            }
          } else {
            InlineNotice(
              symbolName: "exclamationmark.triangle.fill",
              color: .orange,
              title: "VPN Route Always Advertised",
              message:
                "Debagr continues advertising the VPN endpoint even when your phone is nearby, which may race with native local Bonjour discovery."
            )
          }
        }
      }

      SurfaceCard {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .center) {
            Text("Health Check Cadence")
              .font(.headline)
            if !standardIntervals.contains(prefs.healthCheckIntervalSeconds) {
              StatusPill(
                tone: .probing,
                symbolName: "slider.horizontal.3",
                label: "Custom: \(prefs.healthCheckIntervalSeconds)s",
                compact: true
              )
            }
            Spacer()
            cadenceMeter(intervalSeconds: prefs.healthCheckIntervalSeconds)
          }

          DebagrSegmentedControl(
            "Health check interval",
            selection: intervalBinding,
            options: standardIntervals,
            equalWidth: true,
            title: { "\($0)s" }
          )

          Text(intervalDescription(for: prefs.healthCheckIntervalSeconds))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      SurfaceCard {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .center) {
            Text("Default Deployment Timeout")
              .font(.headline)
            if !standardTimeouts.contains(prefs.defaultDeployTimeoutSeconds) {
              StatusPill(
                tone: .probing,
                symbolName: "clock",
                label: "Custom: \(prefs.defaultDeployTimeoutSeconds)s",
                compact: true
              )
            }
            Spacer()
            Text("CLI & MCP")
              .font(.caption2.weight(.medium))
              .foregroundStyle(.secondary)
          }

          DebagrSegmentedControl(
            "Default deployment timeout",
            selection: timeoutBinding,
            options: standardTimeouts,
            equalWidth: true,
            title: { "\($0 / 60) min" }
          )

          Text(timeoutDescription(for: prefs.defaultDeployTimeoutSeconds))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      HStack {
        Text("Preference changes apply to the background supervisor immediately.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Reset Bridge Defaults") {
          model.resetBridgePreferencesToDefaults()
        }
        .buttonStyle(DebagrSecondaryButtonStyle(compact: true))
        .disabled(isDefaultPreferences)
      }
      .padding(.top, 2)
    }
  }

  private func routePostureBadge(title: String, route: String, tone: StatusTone) -> some View {
    HStack(spacing: 6) {
      Circle()
        .fill(tone.color)
        .frame(width: 7, height: 7)
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Image(systemName: "arrow.right")
        .font(.caption2)
        .foregroundStyle(.tertiary)
      Text(route)
        .font(.caption2.weight(.semibold))
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
        .fill(tone.color.opacity(colorScheme == .dark ? 0.14 : 0.08))
    )
    .overlay(
      RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
        .strokeBorder(tone.color.opacity(0.24), lineWidth: 0.75)
    )
  }

  private func cadenceMeter(intervalSeconds: Int) -> some View {
    let activeBars: Int
    if intervalSeconds <= 12 {
      activeBars = 4
    } else if intervalSeconds <= 20 {
      activeBars = 3
    } else if intervalSeconds <= 45 {
      activeBars = 2
    } else {
      activeBars = 1
    }

    return HStack(alignment: .bottom, spacing: 3) {
      ForEach(1...4, id: \.self) { level in
        let isLit = level <= activeBars
        Capsule()
          .fill(
            isLit
              ? StatusTone.local.color
              : Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.12)
          )
          .frame(width: 4, height: CGFloat(5 + level * 3))
      }
    }
    .help("Responsiveness level (\(activeBars)/4)")
    .accessibilityLabel("Responsiveness \(activeBars) of 4")
  }

  private func intervalDescription(for seconds: Int) -> String {
    switch seconds {
    case 10:
      "Fastest VPN & wake recovery (10s). Best for frequent desk-to-pocket transitions."
    case 15:
      "Balanced supervision cadence (15s default) with minimal background CPU wakeups."
    case 30:
      "Power-conscious cadence (30s). Reduces background polling on battery."
    case 60:
      "Quiet cadence (60s). Relies mainly on macOS wake/network events and on-demand checks."
    default:
      "Reconciles VPN and USB transport state every \(seconds) seconds."
    }
  }

  private func timeoutDescription(for seconds: Int) -> String {
    switch seconds {
    case 60:
      "60s timeout — fail fast for lightweight test builds on strong local networks."
    case 180:
      "3 minute default — handles typical debug bundles and symbol preparation over VPN."
    case 300:
      "5 minute timeout — safer for asset-heavy targets over mobile hotspots or cellular."
    case 600:
      "10 minute extended window — built for huge debug bundles on constrained links."
    default:
      "Deployments wait up to \(seconds) seconds before verifying post-timeout outcome."
    }
  }

  // MARK: - Privacy Pane

  private var privacyPane: some View {
    let _ = inspectionRefreshTick
    let storageEntries = model.inspectStorageFiles()

    return VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 10) {
        postureTile(
          icon: "icloud.slash.fill",
          color: .green,
          title: "Zero Cloud",
          detail: "No accounts or remote server"
        )
        postureTile(
          icon: "eye.slash.fill",
          color: .teal,
          title: "Zero Telemetry",
          detail: "Everything stays on this Mac"
        )
        postureTile(
          icon: "network.slash",
          color: .blue,
          title: "Zero Listeners",
          detail: "Stdio MCP & existing SSH only"
        )
      }

      SurfaceCard {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .center, spacing: 8) {
            Text("Local Storage (0700 / 0600)")
              .font(.headline)
            StatusPill(
              tone: model.storagePermissionsOK ? .ready : .offline,
              symbolName: model.storagePermissionsOK
                ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
              label: model.storagePermissionsOK ? "Verified" : "Too Permissive",
              compact: true
            )
            Spacer()
            if model.storagePermissionsOK {
              Button("Re-check") {
                model.reloadLocalStores()
                inspectionRefreshTick &+= 1
                model.showToast("Verified 0700/0600 local storage permissions.")
              }
              .buttonStyle(DebagrSecondaryButtonStyle(compact: true))
            } else {
              Button("Fix Permissions") {
                model.fixStoragePermissions()
                inspectionRefreshTick &+= 1
              }
              .buttonStyle(DebagrPrimaryButtonStyle(compact: true))
            }
          }

          VStack(spacing: 0) {
            ForEach(Array(storageEntries.enumerated()), id: \.element.id) { index, entry in
              if index > 0 {
                Divider()
                  .padding(.vertical, 8)
              }
              storageInspectionRow(entry)
            }
          }
        }
      }

      SurfaceCard {
        HStack(alignment: .center, spacing: 12) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Redacted Diagnostics Export")
              .font(.headline)
            Text(
              "Strips device UDIDs, private VPN octets, PEM keys, and Apple Bonjour pairing tokens before leaving Debagr."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            Task { _ = await model.copyRedactedDiagnostics() }
          } label: {
            DebagrButtonLabel(
              title: model.isLoadingDiagnostics ? "Preparing…" : "Copy Diagnostics",
              systemImage: "doc.on.doc",
              isLoading: model.isLoadingDiagnostics
            )
          }
          .buttonStyle(
            DebagrSecondaryButtonStyle(compact: true, isLoading: model.isLoadingDiagnostics))
        }
      }
    }
  }

  private func postureTile(icon: String, color: Color, title: String, detail: String) -> some View {
    SurfaceCard(padding: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Image(systemName: icon)
          .font(.callout.weight(.semibold))
          .foregroundStyle(color)
        Text(title)
          .font(.callout.weight(.semibold))
        Text(detail)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func storageInspectionRow(_ entry: StorageFileInspection) -> some View {
    let badgeTone: StatusTone = entry.permissionsOK ? .ready : .offline
    let modeLabel = entry.octalPermissions ?? "Pending"

    return HStack(spacing: 10) {
      Image(systemName: entry.iconName)
        .font(.callout)
        .foregroundStyle(Color.accentColor)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.title)
          .font(.callout.weight(.medium))
        Text(DebagrFormatters.shortenedHomePath(entry.url.path))
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 2) {
        Text(modeLabel)
          .font(.caption2.weight(.semibold).monospaced())
          .foregroundStyle(entry.exists ? badgeTone.color : .secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(
            Capsule()
              .fill(
                entry.exists
                  ? badgeTone.color.opacity(0.14)
                  : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
              )
          )
        if let size = entry.formattedSize {
          Text(size)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }

      Button {
        if model.copyToPasteboard(entry.url.path) {
          model.showToast("Copied path for \(entry.title).")
        }
      } label: {
        Image(systemName: "doc.on.doc")
          .font(.caption.weight(.medium))
      }
      .buttonStyle(DebagrSecondaryButtonStyle(compact: true))
      .help("Copy full path")
      .accessibilityLabel("Copy path for \(entry.title)")

      Button("Reveal") {
        model.revealInFinder(entry.url)
      }
      .buttonStyle(DebagrSecondaryButtonStyle(compact: true))
    }
  }
}
