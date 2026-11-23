import DebagrCore
import SwiftUI

public struct MainWindowView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var windowLifecycle: WindowLifecycleController
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var toolbarCopied = false

  public init(model: AppModel, windowLifecycle: WindowLifecycleController) {
    self.model = model
    self.windowLifecycle = windowLifecycle
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
      }
      .navigationSplitViewColumnWidth(min: 210, ideal: 224)
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
            OpenSettingsButton {
              windowLifecycle.activateForWindow()
            } label: {
              Image(systemName: "gearshape")
                .font(.body)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Open Settings (⌘,)")
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
    Label {
      HStack {
        Text(section.title)
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
        }
      }
    } icon: {
      Image(systemName: section.systemImage)
    }
    .tag(section)
  }
}
