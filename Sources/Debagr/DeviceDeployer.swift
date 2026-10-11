import Darwin
import Foundation

enum DeviceDeploymentError: LocalizedError {
  case invalidApp(String)
  case commandFailed(arguments: [String], status: Int32)
  case invalidResult
  case installedBundleNotConfirmed(String)
  case timedOut
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
  var run: ([String], TimeInterval) throws -> Data = DeviceDeployer.runDevicectl

  func checkReady(deviceIdentifier: String, timeout: TimeInterval = 5) throws {
    let data = try run(
      [
        "device", "info", "lockState", "--device", deviceIdentifier,
        "--timeout", String(max(1, Int(timeout))),
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
    let resultData = try run(
      [
        "device", "install", "app",
        "--device", deviceIdentifier,
        appURL.path,
        "--timeout", "120",
      ], 120)
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
          ], 30)
      } catch { throw DeviceDeploymentError.launchFailed(bundleIdentifier) }
    }

    return DeploymentResult(bundleIdentifier: bundleIdentifier, launched: launch)
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
    try process.run()
    guard finished.wait(timeout: .now() + timeout) == .success else {
      process.terminate()
      if finished.wait(timeout: .now() + 1) != .success {
        _ = kill(process.processIdentifier, SIGKILL)
      }
      throw DeviceDeploymentError.timedOut
    }
    guard process.terminationStatus == 0 else {
      throw DeviceDeploymentError.commandFailed(
        arguments: arguments, status: process.terminationStatus)
    }
    return try Data(contentsOf: resultURL)
  }
}
