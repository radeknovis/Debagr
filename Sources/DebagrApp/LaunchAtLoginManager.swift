import Foundation
import Security
import ServiceManagement

public enum LaunchAtLoginStatus: Sendable, Equatable {
  case enabled
  case disabled
  case requiresApproval
  case unavailable(String)

  public var isEnabled: Bool {
    self == .enabled
  }

  public var isUnavailable: Bool {
    if case .unavailable = self {
      return true
    }
    return false
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
      if Self.currentBundleIsAdHocSigned() {
        return .unavailable(
          "Ad-hoc signed builds cannot register with macOS Login Items. Sign Debagr.app with a Developer ID certificate, or add it in System Settings → General → Login Items."
        )
      }
      return .unavailable(
        "App registration not found in macOS Login Items. Run Debagr.app from /Applications, or add it in System Settings → General → Login Items."
      )
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

    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      return currentStatus()
    } catch {
      let nsError = error as NSError
      let isOperationNotPermitted =
        (nsError.code == 1
          && (nsError.domain == NSPOSIXErrorDomain
            || nsError.domain == NSOSStatusErrorDomain
            || nsError.domain == "SMAppServiceErrorDomain"))
        || nsError.localizedDescription.localizedCaseInsensitiveContains("operation not permitted")
      if isOperationNotPermitted {
        if Self.currentBundleIsAdHocSigned() {
          throw NSError(
            domain: "dev.debagr.launchatlogin",
            code: 2,
            userInfo: [
              NSLocalizedDescriptionKey:
                "macOS rejected Login Item registration because this build is ad-hoc signed without a Developer ID team identity. Rebuild with Developer ID signing, or add Debagr.app manually in System Settings → General → Login Items."
            ]
          )
        }
        throw NSError(
          domain: "dev.debagr.launchatlogin",
          code: 3,
          userInfo: [
            NSLocalizedDescriptionKey:
              "macOS rejected Login Item registration (Operation not permitted). This often happens if another stale copy of Debagr.app was previously registered. Remove older copies of Debagr.app, relaunch /Applications/Debagr.app, or toggle Debagr in System Settings → General → Login Items."
          ]
        )
      }
      throw error
    }
  }

  public func openSystemSettingsLoginItems() {
    SMAppService.openSystemSettingsLoginItems()
  }

  private static func currentBundleIsAdHocSigned() -> Bool {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
      return false
    }
    var infoCF: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        staticCode,
        SecCSFlags(rawValue: kSecCSSigningInformation),
        &infoCF
      ) == errSecSuccess,
      let info = infoCF as? [String: Any]
    else {
      return false
    }
    let flags = (info[kSecCodeInfoFlags as String] as? UInt32) ?? 0
    let isAdHoc = (flags & SecCodeSignatureFlags.adhoc.rawValue) != 0
    let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
    return isAdHoc || (teamID?.isEmpty ?? true)
  }
}
