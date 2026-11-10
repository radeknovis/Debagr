import Darwin
import Foundation

enum DeviceDeploymentError: LocalizedError {
  case invalidApp(String)
  case commandFailed(arguments: [String], status: Int32)
  case invalidResult
  case installedBundleNotConfirmed(String)
  case timedOut
  case installationTimedOut
  case appleError(code: Int, domain: String, message: String)
  case launchFailed(String)
  case deviceLocked

  var errorDescription: String? {
    switch self {
    case .invalidApp(let details):
      return "Invalid iOS app bundle: \(details)"
    case .commandFailed(let arguments, let status):
      return "xcrun \(arguments.joined(separator: " ")) failed with exit status \(status)."
    case .invalidResult:
      return "devicectl returned an unreadable installation result."
    case .installedBundleNotConfirmed(let bundleIdentifier):
      return "devicectl did not confirm installation of \(bundleIdentifier)."
    case .appleError(_, _, let message):
      return message
    case .installationTimedOut:
      return
        "Installation exceeded its deadline; the installation outcome is unknown. Inspect installed apps before retrying."
    case .timedOut:
      return "Apple's device command exceeded its deadline."
    case .launchFailed(let identifier):
      return "Installed \(identifier), but launch failed. Retry launch rather than installation."
    case .deviceLocked:
      return "Unlock the device before deployment."
    }
  }
}

struct DeploymentResult: Codable, Equatable {
  let bundleIdentifier: String
  let launched: Bool
}

struct DeviceDeployer {
  private static let commands = LockedValue((cancelled: false, processes: [Process]()))

  static func cancelPendingCommands() {
    let processes = commands.withValue { state in
      state.cancelled = true
      return state.processes
    }
    for process in processes where process.isRunning { process.terminate() }
  }

  var run: ([String], TimeInterval) throws -> Data = DeviceDeployer.runDevicectl

  func checkReady(deviceIdentifier: String, timeout: TimeInterval = 5) throws {
    let data = try run(
      [
        "device", "info", "lockState", "--device", deviceIdentifier,
        "--timeout", String(max(5, Int(timeout.rounded(.up)))),
      ], timeout)
    guard let output = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = output["result"] as? [String: Any],
      let passcodeRequired = result["passcodeRequired"] as? Bool,
      let unlockedSinceBoot = result["unlockedSinceBoot"] as? Bool
    else { throw DeviceDeploymentError.invalidResult }
    guard !passcodeRequired, unlockedSinceBoot else { throw DeviceDeploymentError.deviceLocked }
  }

  func deploy(appURL: URL, deviceIdentifier: String, launch: Bool) throws -> DeploymentResult {
    let bundleIdentifier = try Self.bundleIdentifier(at: appURL)

    try checkReady(deviceIdentifier: deviceIdentifier)
    let resultData: Data
    do {
      resultData = try run(
        [
          "device", "install", "app",
          "--device", deviceIdentifier,
          appURL.path,
          "--timeout", "120",
        ], 125)
    } catch DeviceDeploymentError.timedOut {
      throw DeviceDeploymentError.installationTimedOut
    }
    guard let result = try JSONSerialization.jsonObject(with: resultData) as? [String: Any]
    else {
      throw DeviceDeploymentError.invalidResult
    }
    guard let installation = result["result"], Self.contains(bundleIdentifier, in: installation)
    else {
      throw DeviceDeploymentError.installedBundleNotConfirmed(bundleIdentifier)
    }

    if launch {
      do {
        _ = try run(
          [
            "device", "process", "launch",
            "--device", deviceIdentifier,
            "--terminate-existing",
            "--timeout", "30",
            bundleIdentifier,
          ], 35)
      } catch { throw DeviceDeploymentError.launchFailed(bundleIdentifier) }
    }

    return DeploymentResult(bundleIdentifier: bundleIdentifier, launched: launch)
  }

  func launch(bundleIdentifier: String, deviceIdentifier: String) throws {
    guard !bundleIdentifier.isEmpty, !bundleIdentifier.hasPrefix("-"),
      bundleIdentifier.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    else {
      throw CLIError.missingValue("--launch-app bundle identifier")
    }
    try checkReady(deviceIdentifier: deviceIdentifier)
    _ = try run(
      [
        "device", "process", "launch", "--device", deviceIdentifier,
        "--terminate-existing", "--timeout", "30", bundleIdentifier,
      ], 35)
  }

  func installedApps(deviceIdentifier: String, timeout: TimeInterval) throws -> [[String: Any]] {
    let data = try run(
      [
        "device", "info", "apps", "--device", deviceIdentifier,
        "--timeout", String(max(5, Int(timeout.rounded(.up)))),
      ], timeout)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = object["result"] as? [String: Any], let apps = result["apps"] as? [[String: Any]]
    else {
      throw DeviceDeploymentError.invalidResult
    }
    return apps.map { app in
      var summary: [String: Any] = [:]
      for key in ["bundleIdentifier", "name", "version", "bundleVersion"] {
        if let value = app[key] as? String { summary[key] = value }
      }
      return summary
    }
  }

  static func bundleIdentifier(at appURL: URL) throws -> String {
    var isDirectory: ObjCBool = false
    guard appURL.pathExtension == "app",
      FileManager.default.fileExists(atPath: appURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw DeviceDeploymentError.invalidApp("expected an existing .app directory")
    }

    let infoURL = appURL.appendingPathComponent("Info.plist")
    guard let data = try? Data(contentsOf: infoURL),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let dictionary = plist as? [String: Any],
      let identifier = dictionary["CFBundleIdentifier"] as? String,
      !identifier.isEmpty
    else {
      throw DeviceDeploymentError.invalidApp("Info.plist has no CFBundleIdentifier")
    }
    let platforms = dictionary["CFBundleSupportedPlatforms"] as? [String] ?? []
    guard platforms.contains("iPhoneOS") || dictionary["DTPlatformName"] as? String == "iphoneos"
    else {
      throw DeviceDeploymentError.invalidApp(
        "expected a device iPhoneOS build, not a simulator or macOS app")
    }
    return identifier
  }

  static func contains(_ expected: String, in value: Any) -> Bool {
    if let string = value as? String {
      return string == expected
    }
    if let array = value as? [Any] {
      return array.contains { contains(expected, in: $0) }
    }
    if let dictionary = value as? [String: Any] {
      return dictionary.values.contains { contains(expected, in: $0) }
    }
    return false
  }

  static func appleError(from data: Data) -> DeviceDeploymentError? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let error = object["error"] as? [String: Any],
      let code = error["code"] as? Int, let domain = error["domain"] as? String
    else { return nil }
    let info = error["userInfo"] as? [String: Any]
    let typedDescription = info?["NSLocalizedDescription"] as? [String: Any]
    return .appleError(
      code: code, domain: domain,
      message: error["localizedDescription"] as? String
        ?? typedDescription?["string"] as? String
        ?? info?["NSLocalizedDescription"] as? String
        ?? "Apple device command failed (\(domain), \(code)).")
  }

  static func runDevicectl(_ arguments: [String], timeout: TimeInterval) throws -> Data {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("debagr-command-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let resultURL = directory.appendingPathComponent("result.json")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["devicectl"] + arguments + ["--json-output", resultURL.path]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try commands.withValue { state in
      guard !state.cancelled else { throw CocoaError(.userCancelled) }
      try process.run()
      state.processes.append(process)
    }
    defer { commands.withValue { $0.processes.removeAll { $0 === process } } }
    guard finished.wait(timeout: .now() + timeout) == .success else {
      process.terminate()
      if finished.wait(timeout: .now() + 1) != .success {
        _ = kill(process.processIdentifier, SIGKILL)
      }
      throw DeviceDeploymentError.timedOut
    }
    guard process.terminationStatus == 0 else {
      if let data = try? Data(contentsOf: resultURL), let error = Self.appleError(from: data) {
        throw error
      }
      throw DeviceDeploymentError.commandFailed(
        arguments: arguments, status: process.terminationStatus)
    }
    return try Data(contentsOf: resultURL)
  }
}
