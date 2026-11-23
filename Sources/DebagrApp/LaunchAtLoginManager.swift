import Foundation
import ServiceManagement

public enum LaunchAtLoginStatus: Sendable, Equatable {
  case enabled
  case disabled
  case requiresApproval
  case unavailable(String)

  public var isEnabled: Bool {
    self == .enabled
  }

  public var descriptionText: String {
    switch self {
    case .enabled:
      "Enabled (Debagr launches automatically when you log in)."
    case .disabled:
      "Disabled."
    case .requiresApproval:
      "Requires approval in System Settings > General > Login Items."
    case .unavailable(let reason):
      reason
    }
  }
}

@MainActor
public final class LaunchAtLoginManager {
  public init() {}

  public func currentStatus() -> LaunchAtLoginStatus {
    guard Bundle.main.bundleURL.pathExtension == "app" else {
      return .unavailable(
        "Launch at Login requires running from the bundled Debagr.app application."
      )
    }
    switch SMAppService.mainApp.status {
    case .enabled:
      return .enabled
    case .notRegistered:
      return .disabled
    case .requiresApproval:
      return .requiresApproval
    case .notFound:
      return .unavailable("App registration not found in macOS Login Items.")
    @unknown default:
      return .unavailable("Unknown Login Items status.")
    }
  }

  public func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
    guard Bundle.main.bundleURL.pathExtension == "app" else {
      throw NSError(
        domain: "dev.debagr.launchatlogin",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Install and run Debagr.app (for example in /Applications) to manage Launch at Login."
        ]
      )
    }

    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
    return currentStatus()
  }

  public func openSystemSettingsLoginItems() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
