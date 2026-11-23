import DebagrCore
import SwiftUI

public struct PreferencesView: View {
  @ObservedObject var model: AppModel

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    VStack(spacing: 0) {
      if let settingsErr = model.settingsErrorBanner {
        ExpandableErrorCard(message: settingsErr) {
          model.settingsErrorBanner = nil
        }
      }

      TabView {
        generalTab
          .tabItem { Label("General", systemImage: "gearshape") }

        bridgeTab
          .tabItem { Label("Bridge", systemImage: "antenna.radiowaves.left.and.right") }

        privacyTab
          .tabItem { Label("Privacy", systemImage: "lock.shield") }
      }
    }
    .frame(width: 540, height: 360)
    .onAppear {
      model.reloadLocalStores()
    }
  }

  private var generalTab: some View {
    let launchBinding = Binding<Bool>(
      get: { model.launchAtLoginStatus.isEnabled },
      set: { model.setLaunchAtLogin($0) }
    )

    return Form {
      Section("Startup") {
        Toggle("Launch Debagr at Login", isOn: launchBinding)
        Text(model.launchAtLoginStatus.descriptionText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Version") {
        LabeledContent("Debagr Version", value: DebagrVersion.current)
        LabeledContent("CLI JSON Schema", value: DebagrVersion.schemaVersion)
      }
    }
    .formStyle(.grouped)
  }

  private var bridgeTab: some View {
    let yieldBinding = Binding<Bool>(
      get: { model.config.preferences.yieldWhenNativelyLocal },
      set: { next in model.updatePreferences { $0.yieldWhenNativelyLocal = next } }
    )
    let intervalBinding = Binding<Int>(
      get: { model.config.preferences.healthCheckIntervalSeconds },
      set: { next in model.updatePreferences { $0.healthCheckIntervalSeconds = next } }
    )
    let timeoutBinding = Binding<Int>(
      get: { model.config.preferences.defaultDeployTimeoutSeconds },
      set: { next in model.updatePreferences { $0.defaultDeployTimeoutSeconds = next } }
    )

    return Form {
      Section("Bridge Supervision") {
        Toggle(
          "Yield automatically when connected natively (USB / local Wi-Fi)",
          isOn: yieldBinding
        )

        Picker("Health check interval", selection: intervalBinding) {
          Text("Every 10 seconds").tag(10)
          Text("Every 15 seconds").tag(15)
          Text("Every 30 seconds").tag(30)
          Text("Every 60 seconds").tag(60)
        }

        Picker("Default deployment timeout", selection: timeoutBinding) {
          Text("60 seconds").tag(60)
          Text("180 seconds (Default)").tag(180)
          Text("300 seconds").tag(300)
          Text("600 seconds").tag(600)
        }
      }
    }
    .formStyle(.grouped)
  }

  private var privacyTab: some View {
    Form {
      Section("Local Storage (0700 / 0600)") {
        storageRow(
          label: "Configuration",
          url: model.configStore.fileURL
        )
        storageRow(
          label: "Deployment Receipts",
          url: model.receiptStore.fileURL
        )
        HStack {
          LabeledContent(
            "File Permissions",
            value: model.storagePermissionsOK ? "Verified (0600 / 0700)" : "Too Permissive"
          )
          if !model.storagePermissionsOK {
            Spacer()
            Button("Fix Permissions") {
              model.fixStoragePermissions()
            }
          }
        }
      }

      Section("Zero Cloud & Zero Telemetry") {
        Text(
          "No user accounts, no cloud backend, no analytics or telemetry, and no network listener for deployment commands. Exported diagnostics strip raw Apple pairing metadata."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private func storageRow(label: String, url: URL) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
        Text(DebagrFormatters.shortenedHomePath(url.path))
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      Button("Reveal") {
        model.revealInFinder(url)
      }
      .controlSize(.small)
    }
  }
}
