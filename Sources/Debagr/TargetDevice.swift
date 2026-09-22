import Foundation

enum TargetDeviceKind: String, Codable, Equatable {
  case iPhone
  case iPad
  case unknown

  var displayName: String {
    switch self {
    case .iPhone:
      return "iPhone"
    case .iPad:
      return "iPad"
    case .unknown:
      return "Target Device"
    }
  }

  static func inferred(from service: BonjourDevice) -> Self {
    let values = [
      service.instanceName,
      service.hostName,
      service.suggestedDisplayName,
      service.txt["kind"],
      service.txt["device"],
      service.txt["device_type"],
      service.txt["product"],
      service.txt["model"],
    ]
    .compactMap { $0 }
    .map { $0.lowercased() }

    if values.contains(where: { $0.contains("ipad") }) {
      return .iPad
    }
    if values.contains(where: { $0.contains("iphone") }) {
      return .iPhone
    }
    return .unknown
  }
}

enum TargetDeviceStatus: String, Codable, Equatable {
  case visible
  case paired
  case unavailable

  var displayName: String {
    switch self {
    case .visible:
      return "Wireless service visible"
    case .paired:
      return "Paired to this Mac"
    case .unavailable:
      return "Paired, currently unavailable"
    }
  }
}

struct TargetDeviceIdentity: Codable, Equatable, Hashable {
  enum Source: String, Codable {
    case appleIdentifier
    case bonjourInstance
  }

  let pairedMacNodeID: String
  let value: String
  let source: Source

  static func apple(pairedMacNodeID: String, identifier: String) -> Self {
    Self(
      pairedMacNodeID: pairedMacNodeID,
      value: identifier,
      source: .appleIdentifier
    )
  }

  static func provisional(
    pairedMacNodeID: String,
    service: BonjourDevice
  ) -> Self {
    let metadataIdentifier = service.txt["identifier"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let identifier: String
    if let metadataIdentifier, !metadataIdentifier.isEmpty {
      identifier = metadataIdentifier
    } else {
      identifier = service.instanceName
    }
    return Self(
      pairedMacNodeID: pairedMacNodeID,
      value: "bonjour:\(identifier)",
      source: .bonjourInstance
    )
  }
}

struct TargetDevice: Codable, Equatable, Identifiable {
  let identity: TargetDeviceIdentity
  var displayName: String
  var kind: TargetDeviceKind
  var service: BonjourDevice?
  var status: TargetDeviceStatus = .visible

  var id: TargetDeviceIdentity {
    identity
  }
}

struct TargetDeviceRegistry {
  private(set) var devices: [TargetDeviceIdentity: TargetDevice] = [:]

  var orderedDevices: [TargetDevice] {
    devices.values.sorted { lhs, rhs in
      let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
      if nameOrder != .orderedSame {
        return nameOrder == .orderedAscending
      }
      return lhs.identity.value < rhs.identity.value
    }
  }

  mutating func upsert(_ device: TargetDevice) {
    devices[device.identity] = device
  }

  mutating func merge(_ device: TargetDevice) {
    let identifier = device.identity.value.replacingOccurrences(of: "bonjour:", with: "")
    var matchingKeys = devices.keys.filter {
      $0.pairedMacNodeID == device.identity.pairedMacNodeID
        && $0.value.replacingOccurrences(of: "bonjour:", with: "") == identifier
    }
    let normalizedName = Self.normalizedName(device.displayName)
    if matchingKeys.isEmpty,
      !["iphone", "ipad", "targetdevice"].contains(normalizedName)
    {
      // ponytail: friendly-name merge avoids duplicate CoreDevice/Bonjour rows;
      // replace it when Bonjour reliably exposes the Apple device identifier.
      matchingKeys = devices.compactMap { identity, existing in
        guard
          identity.pairedMacNodeID == device.identity.pairedMacNodeID,
          existing.kind == device.kind,
          Self.normalizedName(existing.displayName) == normalizedName
        else { return nil }
        return identity
      }
    }

    if matchingKeys.count == 1, let existingKey = matchingKeys.first {
      var merged = devices.removeValue(forKey: existingKey) ?? device
      merged.displayName =
        device.identity.source == .appleIdentifier
        ? device.displayName : merged.displayName
      merged.kind = device.kind == .unknown ? merged.kind : device.kind
      merged.service = device.service ?? merged.service
      merged.status = device.status == .visible ? .visible : merged.status
      let finalIdentity =
        device.identity.source == .appleIdentifier ? device.identity : merged.identity
      devices[finalIdentity] = TargetDevice(
        identity: finalIdentity,
        displayName: merged.displayName,
        kind: merged.kind,
        service: merged.service,
        status: merged.status
      )
      return
    }
    upsert(device)
  }

  private static func normalizedName(_ value: String) -> String {
    value.lowercased().filter { $0.isLetter || $0.isNumber }
  }

  mutating func upsert(
    identity: TargetDeviceIdentity,
    displayName: String,
    kind: TargetDeviceKind,
    service: BonjourDevice?
  ) {
    upsert(
      TargetDevice(
        identity: identity,
        displayName: displayName,
        kind: kind,
        service: service
      )
    )
  }

  mutating func remove(_ identity: TargetDeviceIdentity) {
    devices.removeValue(forKey: identity)
  }

  mutating func replaceAll(_ devices: [TargetDevice]) {
    self.devices.removeAll(keepingCapacity: true)
    for device in devices {
      self.devices[device.identity] = device
    }
  }

  func device(for identity: TargetDeviceIdentity) -> TargetDevice? {
    devices[identity]
  }
}
