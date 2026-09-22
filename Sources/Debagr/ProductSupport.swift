import Foundation

enum ProductSupport {
  static var version: String {
    let bundle = Bundle.main
    let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return [shortVersion, build.map { "(\($0))" }]
      .compactMap { $0 }
      .joined(separator: " ")
      .nilIfEmpty ?? "development"
  }

  static var developerToolsAvailable: Bool {
    commandOutput(executable: "/usr/bin/xcrun", arguments: ["--find", "devicectl"]) != nil
  }

  static var tailscaleExecutablePath: String? {
    TailscaleClient.installedExecutablePath()
  }

  static func configuredURL(forInfoKey key: String) -> URL? {
    guard
      let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
      !value.isEmpty
    else {
      return nil
    }
    return URL(string: value)
  }

  static func diagnostics(devices: [TargetDevice]) -> String {
    var lines = [
      "Debagr diagnostics",
      "Version: \(version)",
      "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
      "Architecture: \(architecture)",
      "Developer tools: \(developerToolsAvailable ? "available" : "not detected")",
      "Tailscale CLI: \(tailscaleExecutablePath ?? "not detected")",
      "Visible Target Devices: \(devices.count)",
    ]

    for device in devices {
      let endpoint = device.service.map { "\($0.hostName):\($0.port)" } ?? "unavailable"
      lines.append(
        "- \(device.kind.displayName) — \(device.displayName) — \(device.status.displayName) — \(endpoint)"
      )
    }

    lines.append("Deployment model: commands execute on this paired Mac")
    return lines.joined(separator: "\n")
  }

  private static var architecture: String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #else
      return "unknown"
    #endif
  }

  private static func commandOutput(executable: String, arguments: [String]) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      return nil
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
  }
}

extension String {
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
