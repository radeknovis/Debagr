import DebagrCore
import SwiftUI

public struct MainWindowView: View {
  @ObservedObject var model: AppModel

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    NavigationSplitView {
      List(SidebarDestination.allCases, selection: $model.selectedSection) { section in
        Label {
          HStack {
            Text(section.title)
            if section == .experimental {
              Spacer()
              Text("EXP")
                .font(.caption2.bold())
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
            }
          }
        } icon: {
          Image(systemName: section.systemImage)
        }
        .tag(section)
      }
      .navigationSplitViewColumnWidth(min: 205, ideal: 220)
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 4) {
          Divider()
          HStack(spacing: 6) {
            Circle()
              .fill(bridgePillColor)
              .frame(width: 8, height: 8)
            Text(model.bridgeSnapshot.state.displayTitle)
              .font(.caption.weight(.medium))
          }
          Text(model.config.managedDevice?.displayName ?? "No device saved")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    } detail: {
      VStack(spacing: 0) {
        if let err = model.errorBanner {
          banner(text: err, color: .red, icon: "exclamationmark.octagon.fill") {
            model.errorBanner = nil
          }
        } else if let status = model.statusBanner {
          banner(text: status, color: .accentColor, icon: "info.circle.fill") {
            model.statusBanner = nil
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
          case .preferences:
            PreferencesView(model: model)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private var bridgePillColor: Color {
    switch model.bridgeSnapshot.state {
    case .bridgingActive, .nativeLocalStandby: .green
    case .deviceOffline, .vpnUnavailable, .error: .orange
    case .paused, .probingVPN, .unconfigured: .secondary
    }
  }

  private func banner(
    text: String,
    color: Color,
    icon: String,
    onDismiss: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .foregroundStyle(color)
      Text(text)
        .font(.callout)
        .lineLimit(2)
      Spacer()
      Button("Dismiss", action: onDismiss)
        .buttonStyle(.borderless)
        .font(.caption)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(color.opacity(0.1))
  }
}
