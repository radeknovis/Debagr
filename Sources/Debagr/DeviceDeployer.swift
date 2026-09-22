import Foundation

enum DeviceDeploymentError: LocalizedError {
  case invalidApp(String)
  case commandFailed(arguments: [String], status: Int32)
  case invalidResult
  case installedBundleNotConfirmed(String)

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
    }
  }
}

struct DeploymentResult: Equatable {
  let bundleIdentifier: String
  let launched: Bool
}

struct DeviceDeployer {
  func deploy(appURL: URL, deviceIdentifier: String, launch: Bool) throws -> DeploymentResult {
    let bundleIdentifier = try Self.bundleIdentifier(at: appURL)

    try runDevicectl([
      "device", "info", "lockState",
      "--device", deviceIdentifier,
      "--timeout", "15",
    ])

    let resultURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("debagr-install-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: resultURL) }

    try runDevicectl([
      "device", "install", "app",
      "--device", deviceIdentifier,
      appURL.path,
      "--timeout", "120",
      "--json-output", resultURL.path,
    ])

    let resultData = try Data(contentsOf: resultURL)
    guard let result = try JSONSerialization.jsonObject(with: resultData) as? [String: Any]
    else {
      throw DeviceDeploymentError.invalidResult
    }
    guard Self.contains(bundleIdentifier, in: result) else {
      throw DeviceDeploymentError.installedBundleNotConfirmed(bundleIdentifier)
    }

    if launch {
      try runDevicectl([
        "device", "process", "launch",
        "--device", deviceIdentifier,
        "--terminate-existing",
        "--timeout", "30",
        bundleIdentifier,
      ])
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

  private func runDevicectl(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["devicectl"] + arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw DeviceDeploymentError.commandFailed(
        arguments: arguments, status: process.terminationStatus)
    }
  }
}
