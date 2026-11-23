import Foundation

public enum BridgeRuntimeState: String, Codable, Sendable {
  case unconfigured
  case paused
  case nativeLocalStandby
  case probingVPN
  case bridgingActive
  case deviceOffline
  case vpnUnavailable
  case error

  public var displayTitle: String {
    switch self {
    case .unconfigured: "Not Configured"
    case .paused: "Paused"
    case .nativeLocalStandby: "Native Local Connection"
    case .probingVPN: "Checking VPN..."
    case .bridgingActive: "Bridged Over VPN"
    case .deviceOffline: "Device Unreachable"
    case .vpnUnavailable: "VPN Unavailable"
    case .error: "Bridge Error"
    }
  }
}

public struct BridgeStateSnapshot: Codable, Sendable, Equatable {
  public let state: BridgeRuntimeState
  public let activeProxyHost: String?
  public let activeProxyPort: UInt16?
  public let nativeTransport: TransportType?
  public let vpnReachable: Bool
  public let lastUpdated: Date
  public let lastTransitionReason: String
  public let consecutiveFailures: Int

  public init(
    state: BridgeRuntimeState,
    activeProxyHost: String? = nil,
    activeProxyPort: UInt16? = nil,
    nativeTransport: TransportType? = nil,
    vpnReachable: Bool = false,
    lastUpdated: Date = Date(),
    lastTransitionReason: String,
    consecutiveFailures: Int = 0
  ) {
    self.state = state
    self.activeProxyHost = activeProxyHost
    self.activeProxyPort = activeProxyPort
    self.nativeTransport = nativeTransport
    self.vpnReachable = vpnReachable
    self.lastUpdated = lastUpdated
    self.lastTransitionReason = lastTransitionReason
    self.consecutiveFailures = consecutiveFailures
  }
}

public struct ReadinessCheckItem: Codable, Sendable, Equatable {
  public let name: String
  public let passed: Bool
  public let detail: String

  public init(name: String, passed: Bool, detail: String) {
    self.name = name
    self.passed = passed
    self.detail = detail
  }
}

public struct ReadinessReport: Codable, Sendable, Equatable {
  public let ready: Bool
  public let deviceName: String?
  public let deviceUDIDRedacted: String?
  public let connectionPath: String
  public let pairingState: PairingState
  public let lockState: LockState
  public let bridgeState: BridgeRuntimeState
  public let checks: [ReadinessCheckItem]
  public let blockers: [DebagrErrorPayload]

  public init(
    ready: Bool,
    deviceName: String?,
    deviceUDIDRedacted: String?,
    connectionPath: String,
    pairingState: PairingState,
    lockState: LockState,
    bridgeState: BridgeRuntimeState,
    checks: [ReadinessCheckItem],
    blockers: [DebagrErrorPayload]
  ) {
    self.ready = ready
    self.deviceName = deviceName
    self.deviceUDIDRedacted = deviceUDIDRedacted
    self.connectionPath = connectionPath
    self.pairingState = pairingState
    self.lockState = lockState
    self.bridgeState = bridgeState
    self.checks = checks
    self.blockers = blockers
  }
}

public struct DoctorReport: Codable, Sendable, Equatable {
  public let debagrVersion: String
  public let macOSVersion: String
  public let architecture: String
  public let xcodeVersion: String?
  public let devicectlVersion: String?
  public let configuredDeviceSummary: String?
  public let vpnStatus: String
  public let bridgeSnapshot: BridgeStateSnapshot?
  public let storagePermissionsOK: Bool
  public let recentReceipts: [DeploymentReceipt]
  public let warnings: [String]
  public let redacted: Bool

  public init(
    debagrVersion: String,
    macOSVersion: String,
    architecture: String,
    xcodeVersion: String?,
    devicectlVersion: String?,
    configuredDeviceSummary: String?,
    vpnStatus: String,
    bridgeSnapshot: BridgeStateSnapshot?,
    storagePermissionsOK: Bool,
    recentReceipts: [DeploymentReceipt],
    warnings: [String],
    redacted: Bool
  ) {
    self.debagrVersion = debagrVersion
    self.macOSVersion = macOSVersion
    self.architecture = architecture
    self.xcodeVersion = xcodeVersion
    self.devicectlVersion = devicectlVersion
    self.configuredDeviceSummary = configuredDeviceSummary
    self.vpnStatus = vpnStatus
    self.bridgeSnapshot = bridgeSnapshot
    self.storagePermissionsOK = storagePermissionsOK
    self.recentReceipts = recentReceipts
    self.warnings = warnings
    self.redacted = redacted
  }
}
