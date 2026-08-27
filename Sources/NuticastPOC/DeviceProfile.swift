import Foundation

struct DeviceProfile: Codable, Equatable {
  let bonjourName: String
  let provider: String
  let peerIP: String
  let remotePort: UInt16
  let localPortRange: [UInt16]

  static let defaultLocalPortRange: [UInt16] = [55_000, 58_000]

  var localPortBounds: ClosedRange<UInt16> {
    localPortRange[0]...localPortRange[1]
  }

  func validate() throws {
    guard provider == "tailscale" else {
      throw ProfileError.invalidProvider(provider)
    }
    guard !bonjourName.isEmpty,
      bonjourName.rangeOfCharacter(from: .controlCharacters) == nil
    else {
      throw ProfileError.invalidBonjourName
    }
    guard NetworkSupport.isAllowedTailscaleIPv4(peerIP) else {
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
  }
}

enum ProfileError: LocalizedError {
  case invalidProvider(String)
  case invalidBonjourName
  case invalidPeerIP(String)
  case invalidRemotePort(UInt16)
  case invalidLocalPortRange([UInt16])

  var errorDescription: String? {
    switch self {
    case .invalidProvider(let provider):
      return "Unsupported profile provider: \(provider)."
    case .invalidBonjourName:
      return "The Bonjour instance name must be non-empty and single-line."
    case .invalidPeerIP(let ip):
      return "Profile peerIP is not an allowed Tailscale IPv4 address: \(ip)."
    case .invalidRemotePort(let port):
      return "Invalid remote port: \(port)."
    case .invalidLocalPortRange(let range):
      return "Invalid local port range: \(range)."
    }
  }
}

struct ProfileStore {
  let url: URL

  static var defaultStore: ProfileStore {
    let directory = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("nuticast-poc", isDirectory: true)
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
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
  }
}
