import Foundation

public struct DeviceCtlEnvelope<Result: Decodable>: Decodable {
  public let info: DeviceCtlInfo?
  public let result: Result?
  public let error: DeviceCtlErrorObject?
}

public struct DeviceCtlInfo: Decodable {
  public let outcome: String?
  public let version: String?
  public let jsonVersion: Int?
}

public struct DeviceCtlErrorObject: Decodable {
  public let domain: String?
  public let code: Int?
  public let localizedDescription: String?
  public let failureReason: String?
  public let recoverySuggestion: String?
}

public struct DeviceCtlListDevicesResult: Decodable {
  public let devices: [DeviceCtlRawDevice]
}

public struct DeviceCtlRawDevice: Decodable {
  public let identifier: String
  public let visibilityClass: String?
  public let properties: DeviceCtlModernProperties?
  public let hardwareProperties: DeviceCtlLegacyHardwareProperties?
  public let deviceProperties: DeviceCtlLegacyDeviceProperties?
  public let connectionProperties: DeviceCtlLegacyConnectionProperties?

  public func toPhysicalDevice() -> PhysicalDevice {
    let hw = properties?.hardware
    let legacyHW = hardwareProperties
    let conn = properties?.connection
    let legacyConn = connectionProperties
    let state = properties?.state
    let legacyDev = deviceProperties
    let software = properties?.software

    let rawPlatform = hw?.platform ?? legacyHW?.platform ?? "unknown"
    let rawDeviceType = hw?.deviceType ?? legacyHW?.deviceType ?? ""
    let platform = Self.resolvePlatform(rawPlatform: rawPlatform, rawDeviceType: rawDeviceType)

    let rawReality = hw?.reality ?? legacyHW?.reality ?? "unknown"
    let reality: DeviceReality =
      switch rawReality.lowercased() {
      case "physical": .physical
      case "simulated": .simulated
      default: .unknown
      }

    let rawPairing = conn?.pairingState ?? legacyConn?.pairingState ?? "unknown"
    let pairingState: PairingState =
      switch rawPairing.lowercased() {
      case "paired": .paired
      case "unpaired": .unpaired
      default: .unknown
      }

    let rawTransport = conn?.transportType ?? legacyConn?.transportType ?? "unknown"
    let transportType: TransportType =
      switch rawTransport.lowercased() {
      case "wired", "usb": .wired
      case "localnetwork", "network", "wifi": .localNetwork
      default: .unknown
      }

    let rawTunnel = conn?.state ?? legacyConn?.tunnelState ?? "unknown"
    let tunnelState: TunnelState =
      switch rawTunnel.lowercased() {
      case "connected": .connected
      case "disconnected": .disconnected
      case "unavailable": .unavailable
      default: .unknown
      }

    let devModeEnabled: Bool?
    if let modernStatus = state?.developerModeStatus {
      devModeEnabled = modernStatus.isEnabled
    } else if let legacyStatus = legacyDev?.developerModeStatus {
      devModeEnabled = legacyStatus.lowercased() == "enabled"
    } else {
      devModeEnabled = nil
    }

    let name = state?.name ?? legacyDev?.name ?? "Unknown Device"
    let model =
      hw?.marketingName ?? legacyHW?.marketingName ?? hw?.productType ?? legacyHW?.productType
    let productType = hw?.productType ?? legacyHW?.productType
    let osVersion = software?.osVersionNumber?.stringValue ?? legacyDev?.osVersionNumber
    let udid = hw?.udid ?? legacyHW?.udid
    let ecid = hw?.ecid ?? legacyHW?.ecid

    return PhysicalDevice(
      coreDeviceID: identifier,
      udid: udid,
      ecid: ecid,
      name: name,
      model: model,
      productType: productType,
      platform: platform,
      osVersion: osVersion,
      reality: reality,
      pairingState: pairingState,
      transportType: transportType,
      tunnelState: tunnelState,
      isDeveloperModeEnabled: devModeEnabled,
      ddiServicesAvailable: legacyDev?.ddiServicesAvailable,
      potentialHostnames: legacyConn?.potentialHostnames ?? []
    )
  }

  private static func resolvePlatform(rawPlatform: String, rawDeviceType: String) -> DevicePlatform
  {
    let lowerPlat = rawPlatform.lowercased()
    let lowerType = rawDeviceType.lowercased()
    if lowerPlat == "ipados" || (lowerPlat == "ios" && lowerType == "ipad") {
      return .iPadOS
    }
    switch lowerPlat {
    case "ios": return .iOS
    case "watchos": return .watchOS
    case "tvos": return .tvOS
    case "visionos": return .visionOS
    case "macos": return .macOS
    default: return .unknown
    }
  }
}

public struct DeviceCtlModernProperties: Decodable {
  public let hardware: DeviceCtlModernHardware?
  public let connection: DeviceCtlModernConnection?
  public let state: DeviceCtlModernState?
  public let software: DeviceCtlModernSoftware?
}

public struct DeviceCtlModernHardware: Decodable {
  public let deviceType: String?
  public let ecid: UInt64?
  public let marketingName: String?
  public let platform: String?
  public let productType: String?
  public let reality: String?
  public let udid: String?
}

public struct DeviceCtlModernConnection: Decodable {
  public let pairingState: String?
  public let state: String?
  public let transportType: String?
}

public struct DeviceCtlModernState: Decodable {
  public let bootState: String?
  public let name: String?
  public let developerModeStatus: DeviceCtlDeveloperModeValue?
}

public enum DeviceCtlDeveloperModeValue: Decodable {
  case string(String)
  case enabledObject(Bool)

  public var isEnabled: Bool {
    switch self {
    case .string(let value): value.lowercased() == "enabled"
    case .enabledObject(let flag): flag
    }
  }

  public init(from decoder: Decoder) throws {
    if let single = try? decoder.singleValueContainer(),
      let stringVal = try? single.decode(String.self)
    {
      self = .string(stringVal)
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.enabled) {
      self = .enabledObject(true)
    } else {
      self = .enabledObject(false)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case enabled
  }
}

public struct DeviceCtlModernSoftware: Decodable {
  public let osVersionNumber: DeviceCtlOSVersion?
}

public struct DeviceCtlOSVersion: Decodable {
  public let stringValue: String?
}

public struct DeviceCtlLegacyHardwareProperties: Decodable {
  public let deviceType: String?
  public let ecid: UInt64?
  public let marketingName: String?
  public let platform: String?
  public let productType: String?
  public let reality: String?
  public let udid: String?
}

public struct DeviceCtlLegacyDeviceProperties: Decodable {
  public let ddiServicesAvailable: Bool?
  public let developerModeStatus: String?
  public let name: String?
  public let osVersionNumber: String?
}

public struct DeviceCtlLegacyConnectionProperties: Decodable {
  public let pairingState: String?
  public let potentialHostnames: [String]?
  public let transportType: String?
  public let tunnelState: String?
}

public struct DeviceCtlLockStateResult: Decodable {
  public let passcodeRequired: Bool?
  public let deviceLocked: Bool?
  public let isLocked: Bool?
  public let lockState: String?

  public func toLockState() -> LockState {
    if let lockState {
      switch lockState.lowercased() {
      case "unlocked": return .unlocked
      case "locked": return .locked
      case "passcoderequired": return .passcodeRequired
      default: break
      }
    }
    if passcodeRequired == true {
      return .passcodeRequired
    }
    if deviceLocked == true || isLocked == true {
      return .locked
    }
    if passcodeRequired == false || deviceLocked == false || isLocked == false {
      return .unlocked
    }
    return .unknown
  }
}

public struct DeviceCtlAppsResult: Decodable {
  public let apps: [DeviceCtlRawApp]?
}

public struct DeviceCtlRawApp: Decodable {
  public let bundleIdentifier: String?
  public let name: String?
  public let version: String?
  public let bundleVersion: String?
  public let shortVersion: String?
  public let appClip: Bool?
  public let removable: Bool?
  public let url: String?

  public func toInstalledApp() -> InstalledApp? {
    guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
    return InstalledApp(
      bundleIdentifier: bundleIdentifier,
      name: name,
      version: version ?? bundleVersion,
      shortVersion: shortVersion ?? version,
      appClip: appClip,
      removable: removable,
      bundleURL: url
    )
  }
}

public struct DeviceCtlInstallResult: Decodable {
  public let installedApplications: [DeviceCtlInstalledApplication]?
}

public struct DeviceCtlInstalledApplication: Decodable {
  public let bundleID: String?
  public let bundleIdentifier: String?
  public let launchServicesIdentifier: String?
}

public struct DeviceCtlLaunchResult: Decodable {
  public let process: DeviceCtlLaunchedProcess?
}

public struct DeviceCtlLaunchedProcess: Decodable {
  public let processIdentifier: Int?
}
