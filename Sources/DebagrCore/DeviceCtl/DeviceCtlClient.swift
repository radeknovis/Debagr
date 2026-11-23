import Foundation

public struct DeviceCtlInstallOutcome: Sendable, Equatable {
  public let bundleIdentifier: String?
  public let launchServicesIdentifier: String?

  public init(bundleIdentifier: String?, launchServicesIdentifier: String?) {
    self.bundleIdentifier = bundleIdentifier
    self.launchServicesIdentifier = launchServicesIdentifier
  }
}

public struct DeviceCtlLaunchOutcome: Sendable, Equatable {
  public let pid: Int?

  public init(pid: Int?) {
    self.pid = pid
  }
}

public protocol DeviceControlling: Sendable {
  func version() async throws -> String?
  func listDevices(timeout: TimeInterval) async throws -> [PhysicalDevice]
  func deviceDetails(identifier: String, timeout: TimeInterval) async throws -> PhysicalDevice
  func lockState(identifier: String, timeout: TimeInterval) async throws -> LockState
  func listApps(identifier: String, bundleID: String?, timeout: TimeInterval) async throws
    -> [InstalledApp]
  func installApp(identifier: String, appPath: String, timeout: TimeInterval) async throws
    -> DeviceCtlInstallOutcome
  func launchApp(
    identifier: String,
    bundleID: String,
    arguments: [String],
    environment: [String: String],
    terminateExisting: Bool,
    launchServicesIdentifier: String?,
    timeout: TimeInterval
  ) async throws -> DeviceCtlLaunchOutcome
  func pairDevice(identifier: String, timeout: TimeInterval) async throws
}

public final class SystemDeviceCtlClient: DeviceControlling, Sendable {
  private let runner: any CommandRunning
  private let xcrunPath: String

  public init(
    runner: any CommandRunning = SubprocessRunner(),
    xcrunPath: String = "/usr/bin/xcrun"
  ) {
    self.runner = runner
    self.xcrunPath = xcrunPath
  }

  public func version() async throws -> String? {
    let result = try await runner.run(
      executable: xcrunPath,
      arguments: ["devicectl", "--version"],
      timeoutSeconds: 10
    )
    guard result.exitCode == 0, !result.timedOut else { return nil }
    let trimmed = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  public func listDevices(timeout: TimeInterval = 20) async throws -> [PhysicalDevice] {
    let envelope: DeviceCtlEnvelope<DeviceCtlListDevicesResult> = try await runJSONCommand(
      subcommandArgs: ["list", "devices"],
      timeout: timeout
    )
    if let err = envelope.error {
      throw mapDeviceCtlError(err, defaultCode: .devicectlFailed, deviceIdentifier: nil)
    }
    return (envelope.result?.devices ?? []).map { $0.toPhysicalDevice() }
  }

  public func deviceDetails(identifier: String, timeout: TimeInterval = 20) async throws
    -> PhysicalDevice
  {
    let envelope: DeviceCtlEnvelope<DeviceCtlRawDevice> = try await runJSONCommand(
      subcommandArgs: ["device", "info", "details", "--device", identifier],
      timeout: timeout
    )
    if let err = envelope.error {
      throw mapDeviceCtlError(err, defaultCode: .deviceUnreachable, deviceIdentifier: identifier)
    }
    guard let raw = envelope.result else {
      throw DebagrError(
        code: .deviceNotFound,
        category: "devicectl",
        message: "devicectl did not return details for device '\(identifier)'."
      )
    }
    return raw.toPhysicalDevice()
  }

  public func lockState(identifier: String, timeout: TimeInterval = 15) async throws -> LockState {
    let envelope: DeviceCtlEnvelope<DeviceCtlLockStateResult> = try await runJSONCommand(
      subcommandArgs: ["device", "info", "lockState", "--device", identifier],
      timeout: timeout
    )
    if let err = envelope.error {
      let msg = [err.localizedDescription, err.failureReason].compactMap { $0 }.joined(
        separator: " "
      )
      if msg.localizedCaseInsensitiveContains("locked")
        || msg.localizedCaseInsensitiveContains("passcode")
      {
        return .locked
      }
      throw mapDeviceCtlError(err, defaultCode: .deviceUnreachable, deviceIdentifier: identifier)
    }
    return envelope.result?.toLockState() ?? .unknown
  }

  public func listApps(
    identifier: String,
    bundleID: String? = nil,
    timeout: TimeInterval = 25
  ) async throws -> [InstalledApp] {
    var args = ["device", "info", "apps", "--device", identifier]
    if let bundleID, !bundleID.isEmpty {
      args.append(contentsOf: ["--bundle-id", bundleID])
    } else {
      args.append("--include-removable-apps")
    }
    let envelope: DeviceCtlEnvelope<DeviceCtlAppsResult> = try await runJSONCommand(
      subcommandArgs: args,
      timeout: timeout
    )
    if let err = envelope.error {
      throw mapDeviceCtlError(err, defaultCode: .devicectlFailed, deviceIdentifier: identifier)
    }
    return (envelope.result?.apps ?? []).compactMap { $0.toInstalledApp() }
  }

  public func installApp(
    identifier: String,
    appPath: String,
    timeout: TimeInterval = 180
  ) async throws -> DeviceCtlInstallOutcome {
    let envelope: DeviceCtlEnvelope<DeviceCtlInstallResult> = try await runJSONCommand(
      subcommandArgs: ["device", "install", "app", "--device", identifier, appPath],
      timeout: timeout
    )
    if let err = envelope.error {
      throw mapDeviceCtlError(err, defaultCode: .installFailed, deviceIdentifier: identifier)
    }
    let installed = envelope.result?.installedApplications?.first
    return DeviceCtlInstallOutcome(
      bundleIdentifier: installed?.bundleID ?? installed?.bundleIdentifier,
      launchServicesIdentifier: installed?.launchServicesIdentifier
    )
  }

  public func launchApp(
    identifier: String,
    bundleID: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    terminateExisting: Bool = false,
    launchServicesIdentifier: String? = nil,
    timeout: TimeInterval = 45
  ) async throws -> DeviceCtlLaunchOutcome {
    var args = ["device", "process", "launch", "--device", identifier]
    if terminateExisting {
      args.append("--terminate-existing")
    }
    if let launchServicesIdentifier, !launchServicesIdentifier.isEmpty {
      args.append(contentsOf: ["--launch-persistent-identifier", launchServicesIdentifier])
    }
    if !environment.isEmpty {
      let envData = try JSONSerialization.data(withJSONObject: environment, options: [.sortedKeys])
      let envJSON = String(decoding: envData, as: UTF8.self)
      args.append(contentsOf: ["--environment-variables", envJSON])
    }
    args.append(bundleID)
    if !arguments.isEmpty {
      args.append("--")
      args.append(contentsOf: arguments)
    }

    let envelope: DeviceCtlEnvelope<DeviceCtlLaunchResult> = try await runJSONCommand(
      subcommandArgs: args,
      timeout: timeout
    )
    if let err = envelope.error {
      throw mapDeviceCtlError(err, defaultCode: .launchFailed, deviceIdentifier: identifier)
    }
    return DeviceCtlLaunchOutcome(pid: envelope.result?.process?.processIdentifier)
  }

  public func pairDevice(identifier: String, timeout: TimeInterval = 45) async throws {
    let envelope: DeviceCtlEnvelope<EmptyDeviceCtlResult> = try await runJSONCommand(
      subcommandArgs: ["manage", "pair", "--device", identifier],
      timeout: timeout
    )
    if let err = envelope.error {
      throw mapDeviceCtlError(err, defaultCode: .deviceUnpaired, deviceIdentifier: identifier)
    }
  }

  private func runJSONCommand<Result: Decodable>(
    subcommandArgs: [String],
    timeout: TimeInterval
  ) async throws -> DeviceCtlEnvelope<Result> {
    guard FileManager.default.isExecutableFile(atPath: xcrunPath) else {
      throw DebagrError(
        code: .devicectlUnavailable,
        category: "tooling",
        message: "Apple developer tool runner not found at \(xcrunPath).",
        recoverable: false,
        nextSteps: [
          "Install Xcode and run `sudo xcode-select --switch /Applications/Xcode.app`."
        ]
      )
    }

    let jsonTempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("debagr-devicectl-\(UUID().uuidString).json")
    defer {
      try? FileManager.default.removeItem(at: jsonTempURL)
    }

    var fullArgs = ["devicectl"]
    fullArgs.append(contentsOf: subcommandArgs)
    let cliTimeout = max(5, Int(ceil(timeout)))
    fullArgs.append(contentsOf: [
      "--timeout", String(cliTimeout),
      "--json-output", jsonTempURL.path,
    ])

    let result = try await runner.run(
      executable: xcrunPath,
      arguments: fullArgs,
      timeoutSeconds: timeout + 5
    )

    if result.timedOut {
      throw DebagrError(
        code: .operationTimeoutUncertain,
        category: "timeout",
        message:
          "devicectl timed out after \(cliTimeout)s while running `\(subcommandArgs.prefix(3).joined(separator: " "))`.",
        recoverable: true
      )
    }

    if let data = try? Data(contentsOf: jsonTempURL), !data.isEmpty {
      do {
        return try JSONDecoder().decode(DeviceCtlEnvelope<Result>.self, from: data)
      } catch {
        throw DebagrError(
          code: .devicectlFailed,
          category: "devicectl",
          message: "Failed parsing devicectl JSON output: \(error.localizedDescription)",
          recoverable: true,
          diagnostics: ["stderr": String(result.stderrString.prefix(500))]
        )
      }
    }

    let stderrText = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
    if stderrText.localizedCaseInsensitiveContains("unable to locate")
      || stderrText.localizedCaseInsensitiveContains("no developer tools")
    {
      throw DebagrError(
        code: .devicectlUnavailable,
        category: "tooling",
        message: "devicectl is unavailable: \(stderrText)",
        recoverable: false,
        nextSteps: ["Install Xcode and select active developer directory via `xcode-select`."]
      )
    }

    if result.exitCode != 0 {
      throw classifyStderrFailure(stderrText)
    }

    throw DebagrError(
      code: .devicectlFailed,
      category: "devicectl",
      message: "devicectl exited cleanly without writing JSON output.",
      recoverable: true
    )
  }

  private func mapDeviceCtlError(
    _ err: DeviceCtlErrorObject,
    defaultCode: DebagrErrorCode,
    deviceIdentifier: String?
  ) -> DebagrError {
    let combined = [err.localizedDescription, err.failureReason, err.recoverySuggestion]
      .compactMap { $0 }
      .joined(separator: " ")

    let lower = combined.lowercased()
    if lower.contains("locked") || lower.contains("passcode") {
      return DebagrError.deviceLocked(deviceName: deviceIdentifier ?? "target device")
    }
    if lower.contains("developer mode") {
      return DebagrError(
        code: .developerModeDisabled,
        category: "device_state",
        message: combined.isEmpty ? "Developer Mode is disabled on the target device." : combined,
        recoverable: true,
        nextSteps: [
          "On the device, enable Settings > Privacy & Security > Developer Mode and restart."
        ]
      )
    }
    if lower.contains("unpaired") || lower.contains("not paired") || lower.contains("trust") {
      return DebagrError(
        code: .deviceUnpaired,
        category: "pairing",
        message: combined.isEmpty ? "Device is not paired with this Builder Mac." : combined,
        recoverable: true,
        nextSteps: [
          "Connect the device once to this Builder Mac via USB and accept 'Trust This Computer'."
        ]
      )
    }
    if lower.contains("timed out") || lower.contains("timeout") {
      return DebagrError(
        code: .operationTimeoutUncertain,
        category: "timeout",
        message: combined.isEmpty ? "devicectl operation timed out." : combined,
        recoverable: true
      )
    }
    if lower.contains("not connected")
      || lower.contains("unavailable")
      || lower.contains("could not connect")
      || lower.contains("unreachable")
    {
      return DebagrError(
        code: .deviceUnreachable,
        category: "connectivity",
        message: combined.isEmpty ? "Device could not be reached." : combined,
        recoverable: true,
        nextSteps: [
          "Verify the private VPN is active on both Mac and device, and that the device is on Wi-Fi.",
          "Run `debagr ready` and `debagr bridge status` on the Builder Mac.",
        ]
      )
    }

    return DebagrError(
      code: defaultCode,
      category: "devicectl",
      message: combined.isEmpty ? "devicectl command failed." : combined,
      recoverable: true,
      nextSteps: err.recoverySuggestion.map { [$0] } ?? []
    )
  }

  private func classifyStderrFailure(_ stderr: String) -> DebagrError {
    let lower = stderr.lowercased()
    if lower.contains("locked") || lower.contains("passcode") {
      return DebagrError.deviceLocked(deviceName: "target device")
    }
    if lower.contains("developer mode") {
      return DebagrError(
        code: .developerModeDisabled,
        category: "device_state",
        message: stderr,
        recoverable: true,
        nextSteps: [
          "Enable Settings > Privacy & Security > Developer Mode on the iPhone/iPad."
        ]
      )
    }
    if lower.contains("timed out") || lower.contains("timeout") {
      return DebagrError(
        code: .operationTimeoutUncertain,
        category: "timeout",
        message: stderr,
        recoverable: true
      )
    }
    return DebagrError(
      code: .devicectlFailed,
      category: "devicectl",
      message: stderr.isEmpty ? "devicectl command failed." : stderr,
      recoverable: true
    )
  }
}

private struct EmptyDeviceCtlResult: Decodable {}
