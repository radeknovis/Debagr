import ServiceManagement
import SwiftUI

enum LaunchAtLogin {
  static func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}

struct DebagrPreferencesView: View {
  @State private var status = SMAppService.mainApp.status
  @State private var error: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        SettingsHeading(
          eyebrow: "Preferences", title: "Make yourself at home.",
          subtitle: "Choose how Debagr starts on this Mac.")
        VStack(alignment: .leading, spacing: 12) {
          Toggle(
            "Launch at Login",
            isOn: Binding(
              get: { status == .enabled || status == .requiresApproval },
              set: { enabled in
                do {
                  try LaunchAtLogin.setEnabled(enabled)
                  error = nil
                } catch {
                  self.error = error.localizedDescription
                }
                status = SMAppService.mainApp.status
              })
          )
          .toggleStyle(.switch)
          Text("Start Debagr in the menu bar when you log in to this Mac.")
            .font(.callout).foregroundStyle(.secondary)
          if status == .requiresApproval {
            Text("Allow Debagr in macOS Login Items to finish enabling automatic launch.")
              .font(.callout)
            Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
          }
          if let error {
            Label(error, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red).textSelection(.enabled)
          }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
      }
      .padding(32)
    }
    .onAppear { status = SMAppService.mainApp.status }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      status = SMAppService.mainApp.status
    }
  }
}
