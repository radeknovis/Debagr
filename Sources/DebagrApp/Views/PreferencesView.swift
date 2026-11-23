import DebagrCore
import SwiftUI

public struct PreferencesView: View {
  @ObservedObject var model: AppModel
  @State private var launchAtLogin = false
  @State private var healthInterval = 15
  @State private var deployTimeout = 180
  @State private var yieldLocal = true

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    Form {
      Section("Startup & Background Bridge") {
        Toggle("Launch Debagr at Login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, newValue in
            model.setLaunchAtLogin(newValue)
          }

        Text(model.launchAtLoginStatus.descriptionText)
          .font(.caption)
          .foregroundStyle(.secondary)

        Toggle(
          "Yield automatically when device is connected natively (USB / local Wi-Fi)",
          isOn: $yieldLocal
        )
        .onChange(of: yieldLocal) { _, newValue in
          model.updatePreferences { $0.yieldWhenNativelyLocal = newValue }
        }

        Picker("Bridge health check interval", selection: $healthInterval) {
          Text("Every 10 seconds").tag(10)
          Text("Every 15 seconds").tag(15)
          Text("Every 30 seconds").tag(30)
          Text("Every 60 seconds").tag(60)
        }
        .onChange(of: healthInterval) { _, newValue in
          model.updatePreferences { $0.healthCheckIntervalSeconds = newValue }
        }

        Picker("Default deployment timeout", selection: $deployTimeout) {
          Text("60 seconds").tag(60)
          Text("180 seconds (Default)").tag(180)
          Text("300 seconds").tag(300)
          Text("600 seconds").tag(600)
        }
        .onChange(of: deployTimeout) { _, newValue in
          model.updatePreferences { $0.defaultDeployTimeoutSeconds = newValue }
        }
      }

      Section("Privacy, Security & Local Storage") {
        LabeledContent("Config File", value: model.configStore.fileURL.path)
        LabeledContent("Receipts File", value: model.receiptStore.fileURL.path)
        LabeledContent(
          "Restrictive Permissions (0600/0700)",
          value: model.configStore.verifyPermissions() ? "Verified" : "Warning"
        )
        Text(
          "Zero cloud backend, zero user accounts, zero analytics/telemetry, and zero deployment network listeners. Exported diagnostics strip raw pairing metadata."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding(16)
    .onAppear {
      launchAtLogin = model.launchAtLoginStatus.isEnabled
      healthInterval = model.config.preferences.healthCheckIntervalSeconds
      deployTimeout = model.config.preferences.defaultDeployTimeoutSeconds
      yieldLocal = model.config.preferences.yieldWhenNativelyLocal
    }
  }
}
