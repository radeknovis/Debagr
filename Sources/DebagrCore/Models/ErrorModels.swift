import Foundation

public enum DebagrErrorCode: String, Codable, Sendable {
  case deviceNotConfigured = "DEVICE_NOT_CONFIGURED"
  case deviceNotFound = "DEVICE_NOT_FOUND"
  case deviceUnreachable = "DEVICE_UNREACHABLE"
  case deviceUnpaired = "DEVICE_UNPAIRED"
  case deviceLocked = "DEVICE_LOCKED"
  case developerModeDisabled = "DEVELOPER_MODE_DISABLED"
  case vpnUnavailable = "VPN_UNAVAILABLE"
  case vpnAddressInvalid = "VPN_ADDRESS_INVALID"
  case appBundleInvalid = "APP_BUNDLE_INVALID"
  case appNotSigned = "APP_NOT_SIGNED"
  case installFailed = "INSTALL_FAILED"
  case installVerificationFailed = "INSTALL_VERIFICATION_FAILED"
  case installSucceededLaunchFailed = "INSTALL_SUCCEEDED_LAUNCH_FAILED"
  case launchFailed = "LAUNCH_FAILED"
  case operationTimeoutUncertain = "OPERATION_TIMEOUT_UNCERTAIN"
  case bridgeError = "BRIDGE_ERROR"
  case devicectlUnavailable = "DEVICECTL_UNAVAILABLE"
  case devicectlFailed = "DEVICECTL_FAILED"
  case storageError = "STORAGE_ERROR"
  case experimentalApprovalRequired = "EXPERIMENTAL_APPROVAL_REQUIRED"
  case experimentalToolMissing = "EXPERIMENTAL_TOOL_MISSING"
  case pairingAuthFailed = "PAIRING_AUTH_FAILED"
  case invalidArguments = "INVALID_ARGUMENTS"
  case internalError = "INTERNAL_ERROR"
}

public struct PartialDeployState: Codable, Sendable, Equatable {
  public let installed: Bool
  public let verifiedInstalled: Bool
  public let launched: Bool
  public let bundleIdentifier: String?
  public let launchServicesIdentifier: String?
  public let pid: Int?

  public init(
    installed: Bool,
    verifiedInstalled: Bool,
    launched: Bool,
    bundleIdentifier: String? = nil,
    launchServicesIdentifier: String? = nil,
    pid: Int? = nil
  ) {
    self.installed = installed
    self.verifiedInstalled = verifiedInstalled
    self.launched = launched
    self.bundleIdentifier = bundleIdentifier
    self.launchServicesIdentifier = launchServicesIdentifier
    self.pid = pid
  }
}

public struct DebagrErrorPayload: Codable, Sendable, Equatable {
  public let code: DebagrErrorCode
  public let category: String
  public let message: String
  public let recoverable: Bool
  public let partialSuccess: PartialDeployState?
  public let nextSteps: [String]
  public let diagnostics: [String: String]

  public init(
    code: DebagrErrorCode,
    category: String,
    message: String,
    recoverable: Bool = true,
    partialSuccess: PartialDeployState? = nil,
    nextSteps: [String] = [],
    diagnostics: [String: String] = [:]
  ) {
    self.code = code
    self.category = category
    self.message = message
    self.recoverable = recoverable
    self.partialSuccess = partialSuccess
    self.nextSteps = nextSteps
    self.diagnostics = diagnostics
  }
}

public struct DebagrError: Error, Sendable, Equatable, CustomStringConvertible {
  public let payload: DebagrErrorPayload

  public init(payload: DebagrErrorPayload) {
    self.payload = payload
  }

  public init(
    code: DebagrErrorCode,
    category: String,
    message: String,
    recoverable: Bool = true,
    partialSuccess: PartialDeployState? = nil,
    nextSteps: [String] = [],
    diagnostics: [String: String] = [:]
  ) {
    self.payload = DebagrErrorPayload(
      code: code,
      category: category,
      message: message,
      recoverable: recoverable,
      partialSuccess: partialSuccess,
      nextSteps: nextSteps,
      diagnostics: diagnostics
    )
  }

  public var description: String {
    "[\(payload.code.rawValue)] \(payload.message)"
  }

  public static func deviceNotConfigured() -> DebagrError {
    DebagrError(
      code: .deviceNotConfigured,
      category: "configuration",
      message: "No managed iPhone or iPad is configured on this Builder Mac.",
      recoverable: true,
      nextSteps: [
        "Open the Debagr app on this Builder Mac and run Wireless Setup while the already-paired device is nearby.",
        "Or pass --device <udid> if targeting a directly connected paired device.",
      ]
    )
  }

  public static func deviceLocked(deviceName: String, bundleID: String? = nil) -> DebagrError {
    var steps = [
      "Ask the user to unlock \(deviceName) (passcode/Face ID/Touch ID) and keep it awake.",
      "Re-run `debagr ready` to verify lockState is unlocked.",
    ]
    if let bundleID {
      steps.append("Or pass `--no-launch` to install \(bundleID) without launching it.")
    }
    return DebagrError(
      code: .deviceLocked,
      category: "device_state",
      message:
        "Device '\(deviceName)' is locked; foreground app launch requires the device to be unlocked.",
      recoverable: true,
      nextSteps: steps
    )
  }

  public static func installSucceededLaunchFailed(
    bundleID: String,
    launchServicesIdentifier: String?,
    reason: String,
    deviceLocked: Bool
  ) -> DebagrError {
    var steps: [String] = []
    if deviceLocked {
      steps.append("The device locked during deployment. Ask the user to unlock the device.")
    }
    steps.append(contentsOf: [
      "The app (\(bundleID)) is already installed and verified on the device; do not rebuild or reinstall unnecessarily.",
      "Once ready, launch directly with `debagr launch --bundle-id \(bundleID)` (or MCP `debagr_launch_app`).",
      "If iOS reports an untrusted developer profile, open Settings > General > VPN & Device Management on the device.",
    ])
    return DebagrError(
      code: .installSucceededLaunchFailed,
      category: "partial_deployment",
      message: "Installed and verified '\(bundleID)', but launching it failed: \(reason)",
      recoverable: true,
      partialSuccess: PartialDeployState(
        installed: true,
        verifiedInstalled: true,
        launched: false,
        bundleIdentifier: bundleID,
        launchServicesIdentifier: launchServicesIdentifier,
        pid: nil
      ),
      nextSteps: steps
    )
  }

  public static func operationTimeoutUncertain(
    operation: String,
    timeoutSeconds: TimeInterval,
    bundleID: String?,
    installedVerifiedAfterTimeout: Bool?
  ) -> DebagrError {
    let verificationNote: String
    if let verified = installedVerifiedAfterTimeout {
      verificationNote =
        verified
        ? "Post-timeout check found the app present on the device."
        : "Post-timeout check did not find the app in installed apps yet."
    } else {
      verificationNote = "Post-timeout verification could not confirm device app state."
    }
    var steps = [
      "Inspect current device state with `debagr ready` and `debagr apps\(bundleID.map { " --bundle-id \($0)" } ?? "")`.",
      "Avoid blind retries until VPN and device reachability are verified.",
    ]
    if installedVerifiedAfterTimeout == true, let bundleID {
      steps.append(
        "App appears installed; try `debagr launch --bundle-id \(bundleID)` once device is unlocked."
      )
    }
    return DebagrError(
      code: .operationTimeoutUncertain,
      category: "timeout",
      message:
        "\(operation) exceeded timeout of \(Int(timeoutSeconds))s and its final outcome is uncertain. \(verificationNote)",
      recoverable: true,
      partialSuccess: bundleID.map {
        PartialDeployState(
          installed: installedVerifiedAfterTimeout ?? false,
          verifiedInstalled: installedVerifiedAfterTimeout ?? false,
          launched: false,
          bundleIdentifier: $0,
          launchServicesIdentifier: nil,
          pid: nil
        )
      },
      nextSteps: steps
    )
  }
}
