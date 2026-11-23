import Foundation

public enum VPNProvider: String, Codable, Sendable, CaseIterable, Identifiable {
  case tailscale
  case headscale
  case zerotier
  case netbird
  case wireguard

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .tailscale: "Tailscale"
    case .headscale: "Headscale"
    case .zerotier: "ZeroTier"
    case .netbird: "NetBird"
    case .wireguard: "WireGuard"
    }
  }

  public var supportsAutomaticDiscovery: Bool {
    self == .tailscale || self == .headscale
  }

  public var setupHint: String {
    switch self {
    case .tailscale:
      "Supports automatic peer discovery from the local Tailscale CLI."
    case .headscale:
      "Supports automatic peer discovery when connected through the local Tailscale CLI, or manual private IP entry."
    case .zerotier:
      "Enter the device's ZeroTier private IPv4/IPv6 address manually."
    case .netbird:
      "Enter the device's NetBird private IPv4/IPv6 address (100.64.0.0/10) manually."
    case .wireguard:
      "Enter the device's WireGuard peer private IPv4/IPv6 address manually."
    }
  }
}

public struct VPNEndpoint: Codable, Sendable, Equatable {
  public static let defaultLockdownPort: UInt16 = 62078

  public let provider: VPNProvider
  public let address: String
  public let peerName: String?
  public let tailscaleNodeID: String?
  public let lockdownPort: UInt16

  public init(
    provider: VPNProvider,
    address: String,
    peerName: String? = nil,
    tailscaleNodeID: String? = nil,
    lockdownPort: UInt16 = VPNEndpoint.defaultLockdownPort
  ) {
    self.provider = provider
    self.address = address
    self.peerName = peerName
    self.tailscaleNodeID = tailscaleNodeID
    self.lockdownPort = lockdownPort
  }
}

public struct WirelessIdentity: Codable, Sendable, Equatable {
  public static let mobdevServiceType = "_apple-mobdev2._tcp"
  public static let defaultDomain = "local."

  public let bonjourInstanceName: String
  public let serviceType: String
  public let domain: String
  public let port: UInt16
  public let txtRecords: [String: String]
  public let confirmedHardwareUDID: String
  public let capturedAt: Date

  public init(
    bonjourInstanceName: String,
    serviceType: String = WirelessIdentity.mobdevServiceType,
    domain: String = WirelessIdentity.defaultDomain,
    port: UInt16 = VPNEndpoint.defaultLockdownPort,
    txtRecords: [String: String] = [:],
    confirmedHardwareUDID: String,
    capturedAt: Date = Date()
  ) {
    self.bonjourInstanceName = bonjourInstanceName
    self.serviceType = serviceType
    self.domain = domain
    self.port = port
    self.txtRecords = txtRecords
    self.confirmedHardwareUDID = confirmedHardwareUDID
    self.capturedAt = capturedAt
  }
}

public struct ManagedDeviceProfile: Codable, Sendable, Equatable {
  public let udid: String
  public let coreDeviceID: String
  public let displayName: String
  public let model: String?
  public let platform: DevicePlatform
  public var vpn: VPNEndpoint
  public let wirelessIdentity: WirelessIdentity
  public let savedAt: Date
  public var lastVerifiedAt: Date?

  public init(
    udid: String,
    coreDeviceID: String,
    displayName: String,
    model: String? = nil,
    platform: DevicePlatform,
    vpn: VPNEndpoint,
    wirelessIdentity: WirelessIdentity,
    savedAt: Date = Date(),
    lastVerifiedAt: Date? = nil
  ) {
    self.udid = udid
    self.coreDeviceID = coreDeviceID
    self.displayName = displayName
    self.model = model
    self.platform = platform
    self.vpn = vpn
    self.wirelessIdentity = wirelessIdentity
    self.savedAt = savedAt
    self.lastVerifiedAt = lastVerifiedAt
  }
}

public struct DebagrPreferences: Codable, Sendable, Equatable {
  public var healthCheckIntervalSeconds: Int
  public var defaultDeployTimeoutSeconds: Int
  public var yieldWhenNativelyLocal: Bool
  public var launchAtLoginRequested: Bool

  public init(
    healthCheckIntervalSeconds: Int = 15,
    defaultDeployTimeoutSeconds: Int = 180,
    yieldWhenNativelyLocal: Bool = true,
    launchAtLoginRequested: Bool = false
  ) {
    self.healthCheckIntervalSeconds = max(5, min(300, healthCheckIntervalSeconds))
    self.defaultDeployTimeoutSeconds = max(30, min(900, defaultDeployTimeoutSeconds))
    self.yieldWhenNativelyLocal = yieldWhenNativelyLocal
    self.launchAtLoginRequested = launchAtLoginRequested
  }

  public mutating func clamp() {
    healthCheckIntervalSeconds = max(5, min(300, healthCheckIntervalSeconds))
    defaultDeployTimeoutSeconds = max(30, min(900, defaultDeployTimeoutSeconds))
  }
}

public struct DebagrConfig: Codable, Sendable, Equatable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public var managedDevice: ManagedDeviceProfile?
  public var preferences: DebagrPreferences

  public init(
    schemaVersion: Int = DebagrConfig.currentSchemaVersion,
    managedDevice: ManagedDeviceProfile? = nil,
    preferences: DebagrPreferences = DebagrPreferences()
  ) {
    self.schemaVersion = schemaVersion
    self.managedDevice = managedDevice
    self.preferences = preferences
  }
}
