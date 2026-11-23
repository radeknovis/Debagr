import Foundation

public enum DeploymentOperation: String, Codable, Sendable {
  case install
  case launch
  case deploy
}

public enum DeploymentOutcome: String, Codable, Sendable {
  case succeeded
  case partialSuccessLaunchFailed
  case uncertainTimeout
  case failed
}

public struct DeploymentReceipt: Codable, Sendable, Equatable, Identifiable {
  public let id: UUID
  public let timestamp: Date
  public let operation: DeploymentOperation
  public let outcome: DeploymentOutcome
  public let deviceUDIDRedacted: String
  public let deviceName: String
  public let bundleIdentifier: String?
  public let appVersion: String?
  public let appBuild: String?
  public let appPathName: String?
  public let installed: Bool
  public let verifiedInstalled: Bool
  public let launched: Bool
  public let pid: Int?
  public let durationMs: Int
  public let errorCode: DebagrErrorCode?
  public let summary: String

  public init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    operation: DeploymentOperation,
    outcome: DeploymentOutcome,
    deviceUDIDRedacted: String,
    deviceName: String,
    bundleIdentifier: String?,
    appVersion: String? = nil,
    appBuild: String? = nil,
    appPathName: String? = nil,
    installed: Bool,
    verifiedInstalled: Bool,
    launched: Bool,
    pid: Int? = nil,
    durationMs: Int,
    errorCode: DebagrErrorCode? = nil,
    summary: String
  ) {
    self.id = id
    self.timestamp = timestamp
    self.operation = operation
    self.outcome = outcome
    self.deviceUDIDRedacted = deviceUDIDRedacted
    self.deviceName = deviceName
    self.bundleIdentifier = bundleIdentifier
    self.appVersion = appVersion
    self.appBuild = appBuild
    self.appPathName = appPathName
    self.installed = installed
    self.verifiedInstalled = verifiedInstalled
    self.launched = launched
    self.pid = pid
    self.durationMs = durationMs
    self.errorCode = errorCode
    self.summary = summary
  }
}

public struct ValidatedAppBundle: Codable, Sendable, Equatable {
  public let path: String
  public let bundleIdentifier: String
  public let displayName: String
  public let shortVersion: String?
  public let buildVersion: String?
  public let platformName: String
  public let signingAuthority: String?

  public init(
    path: String,
    bundleIdentifier: String,
    displayName: String,
    shortVersion: String?,
    buildVersion: String?,
    platformName: String,
    signingAuthority: String?
  ) {
    self.path = path
    self.bundleIdentifier = bundleIdentifier
    self.displayName = displayName
    self.shortVersion = shortVersion
    self.buildVersion = buildVersion
    self.platformName = platformName
    self.signingAuthority = signingAuthority
  }
}

public struct InstallResult: Codable, Sendable, Equatable {
  public let deviceName: String
  public let deviceUDIDRedacted: String
  public let bundleIdentifier: String
  public let verifiedInstalled: Bool
  public let launchServicesIdentifier: String?
  public let durationMs: Int
  public let receiptID: UUID

  public init(
    deviceName: String,
    deviceUDIDRedacted: String,
    bundleIdentifier: String,
    verifiedInstalled: Bool,
    launchServicesIdentifier: String?,
    durationMs: Int,
    receiptID: UUID
  ) {
    self.deviceName = deviceName
    self.deviceUDIDRedacted = deviceUDIDRedacted
    self.bundleIdentifier = bundleIdentifier
    self.verifiedInstalled = verifiedInstalled
    self.launchServicesIdentifier = launchServicesIdentifier
    self.durationMs = durationMs
    self.receiptID = receiptID
  }
}

public struct LaunchResult: Codable, Sendable, Equatable {
  public let deviceName: String
  public let deviceUDIDRedacted: String
  public let bundleIdentifier: String
  public let pid: Int?
  public let durationMs: Int
  public let receiptID: UUID

  public init(
    deviceName: String,
    deviceUDIDRedacted: String,
    bundleIdentifier: String,
    pid: Int?,
    durationMs: Int,
    receiptID: UUID
  ) {
    self.deviceName = deviceName
    self.deviceUDIDRedacted = deviceUDIDRedacted
    self.bundleIdentifier = bundleIdentifier
    self.pid = pid
    self.durationMs = durationMs
    self.receiptID = receiptID
  }
}

public struct DeployResult: Codable, Sendable, Equatable {
  public let deviceName: String
  public let deviceUDIDRedacted: String
  public let bundleIdentifier: String
  public let installed: Bool
  public let verifiedInstalled: Bool
  public let launched: Bool
  public let pid: Int?
  public let launchServicesIdentifier: String?
  public let durationMs: Int
  public let receiptID: UUID

  public init(
    deviceName: String,
    deviceUDIDRedacted: String,
    bundleIdentifier: String,
    installed: Bool,
    verifiedInstalled: Bool,
    launched: Bool,
    pid: Int?,
    launchServicesIdentifier: String?,
    durationMs: Int,
    receiptID: UUID
  ) {
    self.deviceName = deviceName
    self.deviceUDIDRedacted = deviceUDIDRedacted
    self.bundleIdentifier = bundleIdentifier
    self.installed = installed
    self.verifiedInstalled = verifiedInstalled
    self.launched = launched
    self.pid = pid
    self.launchServicesIdentifier = launchServicesIdentifier
    self.durationMs = durationMs
    self.receiptID = receiptID
  }
}
