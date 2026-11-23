import Foundation

public protocol AppBundleValidating: Sendable {
  func validate(appPath: String) async throws -> ValidatedAppBundle
}

public final class SystemAppBundleValidator: AppBundleValidating, Sendable {
  private let runner: any CommandRunning

  public init(runner: any CommandRunning = SubprocessRunner()) {
    self.runner = runner
  }

  public func validate(appPath: String) async throws -> ValidatedAppBundle {
    let expanded = (appPath as NSString).expandingTildeInPath
    let standardized = URL(fileURLWithPath: expanded).standardizedFileURL
    let fm = FileManager.default

    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
      throw DebagrError(
        code: .appBundleInvalid,
        category: "app_bundle",
        message: "App bundle does not exist at path: \(standardized.path)",
        recoverable: true,
        nextSteps: [
          "Build a signed iphoneos Release/Debug .app bundle with xcodebuild on the Builder Mac.",
          "Pass the full path to the .app directory to --app.",
        ]
      )
    }

    guard isDirectory.boolValue && standardized.pathExtension.lowercased() == "app" else {
      throw DebagrError(
        code: .appBundleInvalid,
        category: "app_bundle",
        message: "Expected a .app directory bundle at \(standardized.path).",
        recoverable: true,
        nextSteps: [
          "Pass the path to the built .app bundle (for example Build/Products/Debug-iphoneos/MyApp.app)."
        ]
      )
    }

    let infoPlistURL = standardized.appendingPathComponent("Info.plist", isDirectory: false)
    guard fm.fileExists(atPath: infoPlistURL.path),
      let plistData = try? Data(contentsOf: infoPlistURL),
      let rawPlist = try? PropertyListSerialization.propertyList(
        from: plistData,
        options: [],
        format: nil
      ),
      let info = rawPlist as? [String: Any]
    else {
      throw DebagrError(
        code: .appBundleInvalid,
        category: "app_bundle",
        message: "Bundle is missing a readable Info.plist at \(infoPlistURL.path).",
        recoverable: true,
        nextSteps: [
          "Ensure the build succeeded and produced a complete .app bundle."
        ]
      )
    }

    guard let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty else {
      throw DebagrError(
        code: .appBundleInvalid,
        category: "app_bundle",
        message: "Info.plist at \(infoPlistURL.path) does not define CFBundleIdentifier.",
        recoverable: true
      )
    }

    let dtPlatform = (info["DTPlatformName"] as? String)?.lowercased()
    let supportedPlatforms =
      (info["CFBundleSupportedPlatforms"] as? [String])?.map { $0.lowercased() } ?? []

    let resolvedPlatform = dtPlatform ?? supportedPlatforms.first ?? ""
    if resolvedPlatform == "iphonesimulator" || supportedPlatforms.contains("iphonesimulator") {
      throw DebagrError(
        code: .appBundleInvalid,
        category: "app_bundle",
        message:
          "App bundle '\(standardized.lastPathComponent)' targets iphonesimulator, not a physical iOS/iPadOS device.",
        recoverable: true,
        nextSteps: [
          "Rebuild with `-sdk iphoneos` and `-destination 'generic/platform=iOS'` on the Builder Mac."
        ]
      )
    }

    if resolvedPlatform == "macosx" || supportedPlatforms.contains("macosx") {
      throw DebagrError(
        code: .appBundleInvalid,
        category: "app_bundle",
        message:
          "App bundle '\(standardized.lastPathComponent)' targets macOS, which Debagr does not deploy.",
        recoverable: true,
        nextSteps: [
          "Provide a signed iOS or iPadOS device .app bundle built for iphoneos."
        ]
      )
    }

    if !resolvedPlatform.isEmpty && resolvedPlatform != "iphoneos" {
      throw DebagrError(
        code: .appBundleInvalid,
        category: "app_bundle",
        message:
          "Unsupported app bundle platform '\(resolvedPlatform)'. Expected iphoneos for physical iPhone/iPad deployment.",
        recoverable: true
      )
    }

    let verifyResult = try await runner.run(
      executable: "/usr/bin/codesign",
      arguments: ["--verify", "--deep", "--strict", standardized.path],
      timeoutSeconds: 20
    )

    if verifyResult.timedOut {
      throw DebagrError(
        code: .appNotSigned,
        category: "codesign",
        message: "Timed out verifying code signature for \(standardized.lastPathComponent).",
        recoverable: true
      )
    }

    if verifyResult.exitCode != 0 {
      let detail = verifyResult.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
      throw DebagrError(
        code: .appNotSigned,
        category: "codesign",
        message:
          "Code signature verification failed for '\(standardized.lastPathComponent)'. Debagr only deploys already-signed device apps.",
        recoverable: true,
        nextSteps: [
          "Build and sign the app for iOS device deployment using Xcode on the Builder Mac.",
          "Inspect signing details with `codesign -dvv \(standardized.path)`.",
        ],
        diagnostics: detail.isEmpty ? [:] : ["codesignStderr": String(detail.prefix(500))]
      )
    }

    // Best-effort authority inspection (non-fatal if absent)
    let infoResult = try? await runner.run(
      executable: "/usr/bin/codesign",
      arguments: ["-dv", standardized.path],
      timeoutSeconds: 10
    )
    let authority = infoResult.flatMap { parseSigningAuthority(from: $0.stderrString) }

    let displayName =
      (info["CFBundleDisplayName"] as? String)
      ?? (info["CFBundleName"] as? String)
      ?? standardized.deletingPathExtension().lastPathComponent

    return ValidatedAppBundle(
      path: standardized.path,
      bundleIdentifier: bundleID,
      displayName: displayName,
      shortVersion: info["CFBundleShortVersionString"] as? String,
      buildVersion: info["CFBundleVersion"] as? String,
      platformName: resolvedPlatform.isEmpty ? "iphoneos" : resolvedPlatform,
      signingAuthority: authority
    )
  }

  private func parseSigningAuthority(from codesignOutput: String) -> String? {
    for line in codesignOutput.split(separator: "\n") {
      if line.hasPrefix("Authority=") {
        return String(line.dropFirst("Authority=".count))
      }
    }
    return nil
  }
}
