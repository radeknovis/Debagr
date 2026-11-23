import Foundation

public enum DevicePlatform: String, Codable, Sendable, CaseIterable {
  case iOS
  case iPadOS
  case watchOS
  case tvOS
  case visionOS
  case macOS
  case unknown

  public var isSupportedMobileDevice: Bool {
    self == .iOS || self == .iPadOS
  }
}

public enum DeviceReality: String, Codable, Sendable {
  case physical
  case simulated
  case unknown
}

public enum PairingState: String, Codable, Sendable {
  case paired
  case unpaired
  case unknown
}

public enum TransportType: String, Codable, Sendable {
  case wired
  case localNetwork
  case unknown
}

public enum TunnelState: String, Codable, Sendable {
  case connected
  case disconnected
  case unavailable
  case unknown
}

public enum LockState: String, Codable, Sendable {
  case unlocked
  case locked
  case passcodeRequired
  case unknown

  public var blocksForegroundLaunch: Bool {
    self == .locked || self == .passcodeRequired
  }
}

public struct PhysicalDevice: Codable, Sendable, Equatable, Identifiable {
  public var id: String { udid ?? coreDeviceID }

  public let coreDeviceID: String
  public let udid: String?
  public let ecid: UInt64?
  public let name: String
  public let model: String?
  public let productType: String?
  public let platform: DevicePlatform
  public let osVersion: String?
  public let reality: DeviceReality
  public let pairingState: PairingState
  public let transportType: TransportType
  public let tunnelState: TunnelState
  public let isDeveloperModeEnabled: Bool?
  public let ddiServicesAvailable: Bool?
  public let potentialHostnames: [String]

  public init(
    coreDeviceID: String,
    udid: String?,
    ecid: UInt64? = nil,
    name: String,
    model: String? = nil,
    productType: String? = nil,
    platform: DevicePlatform,
    osVersion: String? = nil,
    reality: DeviceReality,
    pairingState: PairingState,
    transportType: TransportType,
    tunnelState: TunnelState,
    isDeveloperModeEnabled: Bool? = nil,
    ddiServicesAvailable: Bool? = nil,
    potentialHostnames: [String] = []
  ) {
    self.coreDeviceID = coreDeviceID
    self.udid = udid
    self.ecid = ecid
    self.name = name
    self.model = model
    self.productType = productType
    self.platform = platform
    self.osVersion = osVersion
    self.reality = reality
    self.pairingState = pairingState
    self.transportType = transportType
    self.tunnelState = tunnelState
    self.isDeveloperModeEnabled = isDeveloperModeEnabled
    self.ddiServicesAvailable = ddiServicesAvailable
    self.potentialHostnames = potentialHostnames
  }

  public var isEligibleForDebagr: Bool {
    reality == .physical
      && platform.isSupportedMobileDevice
      && pairingState == .paired
      && (udid?.isEmpty == false)
  }

  public var ineligibilityReason: String? {
    if reality == .simulated {
      return "Simulated device (Debagr targets physical iPhones and iPads only)."
    }
    if !platform.isSupportedMobileDevice {
      return "Unsupported platform \(platform.rawValue) (Debagr supports iPhone and iPad only)."
    }
    if pairingState != .paired {
      return
        "Device is not paired with this Builder Mac. Pair via USB in Xcode/Finder first, or use Experimental Pair via USB/IP."
    }
    if udid?.isEmpty != false {
      return "Device did not report a hardware UDID."
    }
    return nil
  }

  public var primaryIdentifier: String {
    udid ?? coreDeviceID
  }

  public func matches(identifier: String) -> Bool {
    let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if coreDeviceID.caseInsensitiveCompare(trimmed) == .orderedSame { return true }
    if let udid, udid.caseInsensitiveCompare(trimmed) == .orderedSame { return true }
    if let ecid, String(ecid) == trimmed { return true }
    if name.caseInsensitiveCompare(trimmed) == .orderedSame { return true }
    return potentialHostnames.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
  }
}

public struct InstalledApp: Codable, Sendable, Equatable {
  public let bundleIdentifier: String
  public let name: String?
  public let version: String?
  public let shortVersion: String?
  public let appClip: Bool?
  public let removable: Bool?
  public let bundleURL: String?

  public init(
    bundleIdentifier: String,
    name: String? = nil,
    version: String? = nil,
    shortVersion: String? = nil,
    appClip: Bool? = nil,
    removable: Bool? = nil,
    bundleURL: String? = nil
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.name = name
    self.version = version
    self.shortVersion = shortVersion
    self.appClip = appClip
    self.removable = removable
    self.bundleURL = bundleURL
  }
}
