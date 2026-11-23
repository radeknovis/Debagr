import DebagrCore
import Foundation

public enum CLIExitCode: Int32, Sendable {
  case success = 0
  case generalError = 1
  case usageError = 2
  case deviceNotReady = 3
  case partialSuccessLaunchFailed = 4
  case uncertainTimeout = 5

  public static func from(errorCode: DebagrErrorCode) -> CLIExitCode {
    switch errorCode {
    case .invalidArguments:
      return .usageError
    case .deviceNotConfigured,
      .deviceNotFound,
      .deviceUnreachable,
      .deviceUnpaired,
      .deviceLocked,
      .developerModeDisabled,
      .vpnUnavailable,
      .vpnAddressInvalid:
      return .deviceNotReady
    case .installSucceededLaunchFailed:
      return .partialSuccessLaunchFailed
    case .operationTimeoutUncertain:
      return .uncertainTimeout
    default:
      return .generalError
    }
  }
}

public struct CLIEnvelope<DataPayload: Encodable & Sendable>: Encodable, Sendable {
  public let schemaVersion: String
  public let command: String
  public let ok: Bool
  public let timestamp: Date
  public let data: DataPayload?
  public let error: DebagrErrorPayload?

  public init(
    schemaVersion: String = DebagrVersion.schemaVersion,
    command: String,
    ok: Bool,
    timestamp: Date = Date(),
    data: DataPayload? = nil,
    error: DebagrErrorPayload? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.command = command
    self.ok = ok
    self.timestamp = timestamp
    self.data = data
    self.error = error
  }
}

public struct EmptyCLIResult: Codable, Sendable, Equatable {
  public init() {}
}

public struct RedactedConfigSummary: Codable, Sendable, Equatable {
  public let configured: Bool
  public let deviceName: String?
  public let deviceUDIDRedacted: String?
  public let platform: DevicePlatform?
  public let vpnProvider: VPNProvider?
  public let vpnAddressRedacted: String?
  public let vpnLockdownPort: UInt16?
  public let wirelessIdentityCaptured: Bool
  public let preferences: DebagrPreferences

  public init(from config: DebagrConfig) {
    if let managed = config.managedDevice {
      self.configured = true
      self.deviceName = managed.displayName
      self.deviceUDIDRedacted = Redactor.redactUDID(managed.udid)
      self.platform = managed.platform
      self.vpnProvider = managed.vpn.provider
      self.vpnAddressRedacted = Redactor.redactIP(managed.vpn.address, strict: true)
      self.vpnLockdownPort = managed.vpn.lockdownPort
      self.wirelessIdentityCaptured = !managed.wirelessIdentity.bonjourInstanceName.isEmpty
    } else {
      self.configured = false
      self.deviceName = nil
      self.deviceUDIDRedacted = nil
      self.platform = nil
      self.vpnProvider = nil
      self.vpnAddressRedacted = nil
      self.vpnLockdownPort = nil
      self.wirelessIdentityCaptured = false
    }
    self.preferences = config.preferences
  }
}

public struct VersionInfoPayload: Codable, Sendable, Equatable {
  public let name: String
  public let version: String
  public let schemaVersion: String
  public let bundleIdentifier: String

  public init() {
    self.name = "Debagr"
    self.version = DebagrVersion.current
    self.schemaVersion = DebagrVersion.schemaVersion
    self.bundleIdentifier = DebagrVersion.bundleIdentifier
  }
}
