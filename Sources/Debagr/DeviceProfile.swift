import Foundation

struct DeviceProfile: Codable, Equatable {
  let bonjourName: String
  let bonjourTXT: [String: String]
  let provider: String
  let peerIP: String
  let remotePort: UInt16
  let localPortRange: [UInt16]
  let tunnelPortRange: [UInt16]

  init(
    bonjourName: String,
    bonjourTXT: [String: String] = [:],
    provider: String,
    peerIP: String,
    remotePort: UInt16,
    localPortRange: [UInt16],
    tunnelPortRange: [UInt16] = [49_152, 49_216]
  ) {
    self.bonjourName = bonjourName
    self.bonjourTXT = bonjourTXT
    self.provider = provider
    self.peerIP = peerIP
    self.remotePort = remotePort
    self.localPortRange = localPortRange
    self.tunnelPortRange = tunnelPortRange
  }

  private enum CodingKeys: String, CodingKey {
    case bonjourName, bonjourTXT, provider, peerIP, remotePort, localPortRange, tunnelPortRange
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    bonjourName = try values.decode(String.self, forKey: .bonjourName)
    bonjourTXT = try values.decodeIfPresent([String: String].self, forKey: .bonjourTXT) ?? [:]
    provider = try values.decode(String.self, forKey: .provider)
    peerIP = try values.decode(String.self, forKey: .peerIP)
    remotePort = try values.decode(UInt16.self, forKey: .remotePort)
    localPortRange = try values.decode([UInt16].self, forKey: .localPortRange)
    tunnelPortRange =
      try values.decodeIfPresent([UInt16].self, forKey: .tunnelPortRange)
      ?? [49_152, 49_216]
  }

  static let defaultLocalPortRange: [UInt16] = [55_000, 58_000]

  func learningTunnelPort(_ port: UInt16) -> DeviceProfile {
    // shortcut: neighboring ports are heuristic; recapture a verified range if Apple changes allocation.
    guard port >= 1024 else { return self }
    return DeviceProfile(
      bonjourName: bonjourName, bonjourTXT: bonjourTXT, provider: provider,
      peerIP: peerIP, remotePort: remotePort, localPortRange: localPortRange,
      tunnelPortRange: [UInt16(max(1024, Int(port) - 16)), UInt16(min(65535, Int(port) + 64))])
  }

  var localPortBounds: ClosedRange<UInt16> {
    localPortRange[0]...localPortRange[1]
  }

  func validate() throws {
    guard let networkProvider = NetworkProvider(rawValue: provider) else {
      throw ProfileError.invalidProvider(provider)
    }
    guard !bonjourName.isEmpty,
      bonjourName.rangeOfCharacter(from: .controlCharacters) == nil
    else {
      throw ProfileError.invalidBonjourName
    }
    guard networkProvider.allowsAddress(peerIP) else {
      throw ProfileError.invalidPeerIP(peerIP)
    }
    guard (1...65_535).contains(Int(remotePort)) else {
      throw ProfileError.invalidRemotePort(remotePort)
    }
    guard localPortRange.count == 2,
      localPortRange[0] >= 1_024,
      localPortRange[0] <= localPortRange[1],
      localPortRange[1] <= 65_535
    else {
      throw ProfileError.invalidLocalPortRange(localPortRange)
    }
    guard tunnelPortRange.count == 2,
      tunnelPortRange[0] >= 1_024,
      tunnelPortRange[0] <= tunnelPortRange[1],
      Int(tunnelPortRange[1]) - Int(tunnelPortRange[0]) < 1_024
    else {
      throw ProfileError.invalidTunnelPortRange(tunnelPortRange)
    }
  }
}

enum ProfileError: LocalizedError {
  case invalidProvider(String)
  case invalidBonjourName
  case invalidPeerIP(String)
  case invalidRemotePort(UInt16)
  case invalidLocalPortRange([UInt16])
  case invalidTunnelPortRange([UInt16])

  var errorDescription: String? {
    switch self {
    case .invalidProvider(let provider):
      return "Unsupported profile provider: \(provider)."
    case .invalidBonjourName:
      return "The Bonjour instance name must be non-empty and single-line."
    case .invalidPeerIP(let ip):
      return "Profile peerIP is not an allowed private IPv4 address for this provider: \(ip)."
    case .invalidRemotePort(let port):
      return "Invalid remote port: \(port)."
    case .invalidLocalPortRange(let range):
      return "Invalid local port range: \(range)."
    case .invalidTunnelPortRange(let range):
      return "Invalid tunnel port range: \(range). Use 1...1024 ports above 1023."
    }
  }
}

struct ProfileStore {
  let url: URL

  static var defaultStore: ProfileStore {
    let directory = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("debagr", isDirectory: true)
    return ProfileStore(url: directory.appendingPathComponent("device-profile.json"))
  }

  func load() throws -> DeviceProfile? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    let profile = try JSONDecoder().decode(DeviceProfile.self, from: data)
    try profile.validate()
    return profile
  }

  func save(_ profile: DeviceProfile) throws {
    try profile.validate()

    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(profile)
    try ManagedDeviceStore.writePrivate(data, to: url)
  }
}
