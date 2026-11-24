import DebagrCore
import SwiftUI

public struct MainWindowView: View {
  @ObservedObject var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var toolbarCopied = false

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    let verdict = model.verdict

    NavigationSplitView {
      List(selection: $model.selectedSection) {
        Section("Device") {
          sidebarRow(.overview)
          sidebarRow(.wirelessSetup)
        }

        Section("Automation") {
          sidebarRow(.agentOnboarding)
        }

        Section("Labs") {
          sidebarRow(.experimental)
        }

        Section("Settings") {
          sidebarRow(.settingsGeneral)
          sidebarRow(.settingsBridge)
          sidebarRow(.settingsPrivacy)
        }
      }
      .navigationSplitViewColumnWidth(min: 220, ideal: 236)
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 8) {
          Divider()
          HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
              StatusPill(
                tone: verdict.tone,
                symbolName: verdict.heroSymbol,
                label: verdict.pillLabel,
                compact: true
              )
              Text(model.config.managedDevice?.displayName ?? "No device configured")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Text("v\(DebagrVersion.current)")
              .font(.caption2.monospaced())
              .foregroundStyle(.tertiary)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    } detail: {
      ZStack(alignment: .bottom) {
        VStack(spacing: 0) {
          if let err = model.errorBanner {
            ExpandableErrorCard(message: err) {
              model.errorBanner = nil
            }
          }

          Group {
            switch model.selectedSection {
            case .overview:
              OverviewView(model: model)
            case .wirelessSetup:
              WirelessSetupWizardView(model: model)
            case .agentOnboarding:
              AgentOnboardingView(model: model)
            case .experimental:
              ExperimentalView(model: model)
            case .settingsGeneral:
              PreferencesView(model: model, pane: .general)
            case .settingsBridge:
              PreferencesView(model: model, pane: .bridge)
            case .settingsPrivacy:
              PreferencesView(model: model, pane: .privacy)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        if let toast = model.toastMessage {
          FloatingToastOverlay(message: toast)
            .padding(.bottom, 18)
            .transition(
              reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
            )
        }
      }
      .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.toastMessage)
    }
    .navigationTitle(model.selectedSection.title)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          Task { await model.refreshReadiness() }
        } label: {
          HStack(spacing: 6) {
            ZStack {
              if model.isCheckingReadiness {
                ProgressView()
                  .controlSize(.small)
              } else {
                Image(systemName: "checkmark.shield")
              }
            }
            .frame(width: 16, height: 16)
            Text("Verify")
          }
        }
        .disabled(model.config.managedDevice == nil || model.isCheckingReadiness)
        .help("Verify saved connection & device readiness (⌘R)")

        Button {
          Task { await model.toggleBridgePaused() }
        } label: {
          Label(
            model.isBridgePaused ? "Resume Bridge" : "Pause Bridge",
            systemImage: model.isBridgePaused ? "play.circle" : "pause.circle"
          )
        }
        .disabled(model.config.managedDevice == nil)
        .help(model.isBridgePaused ? "Resume background VPN bridge" : "Pause background VPN bridge")

        Button {
          Task {
            let ok = await model.copyRedactedDiagnostics()
            guard ok else { return }
            toolbarCopied = true
            try? await Task.sleep(for: .seconds(1.5))
            toolbarCopied = false
          }
        } label: {
          Label(
            toolbarCopied ? "Copied" : "Copy Diagnostics",
            systemImage: toolbarCopied ? "checkmark" : "doc.on.doc"
          )
          .contentTransition(.symbolEffect(.replace))
        }
        .help("Copy redacted diagnostics JSON (⌘⇧C)")
      }
    }
  }

  private func sidebarRow(_ section: SidebarDestination) -> some View {
    let isSelected = model.selectedSection == section

    return HStack(spacing: 10) {
      Image(systemName: section.systemImage)
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
        .frame(width: 18, alignment: .center)

      Text(section.title)
        .lineLimit(1)

      if section == .experimental {
        Spacer()
        HStack(spacing: 4) {
          Circle()
            .fill(Color.orange)
            .frame(width: 5, height: 5)
          Text("EXP")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.16), in: Capsule())
      } else if section == .settingsPrivacy && !model.storagePermissionsOK {
        Spacer()
        Circle()
          .fill(StatusTone.offline.color)
          .frame(width: 7, height: 7)
          .help("Storage file permissions need attention")
      }
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 4)
    .tag(section)
  }
}
