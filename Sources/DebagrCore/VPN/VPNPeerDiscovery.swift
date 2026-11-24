import Foundation

public struct VPNPeer: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let dnsName: String?
  public let hostName: String?
  public let addresses: [String]
  public let os: String
  public let online: Bool
  public let active: Bool
  public let lastSeen: Date?
  public let tags: [String]
  public let ownerName: String?
  public let relay: String?
  public let provider: VPNProvider

  public init(
    id: String,
    name: String,
    dnsName: String? = nil,
    hostName: String? = nil,
    addresses: [String],
    os: String,
    online: Bool,
    active: Bool = false,
    lastSeen: Date? = nil,
    tags: [String] = [],
    ownerName: String? = nil,
    relay: String? = nil,
    provider: VPNProvider
  ) {
    self.id = id
    self.name = name
    self.dnsName = dnsName
    self.hostName = hostName
    self.addresses = addresses
    self.os = os
    self.online = online
    self.active = active
    self.lastSeen = lastSeen
    self.tags = tags
    self.ownerName = ownerName
    self.relay = relay
    self.provider = provider
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case dnsName
    case hostName
    case addresses
    case os
    case online
    case active
    case lastSeen
    case tags
    case ownerName
    case relay
    case provider
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.name = try container.decode(String.self, forKey: .name)
    self.dnsName = try container.decodeIfPresent(String.self, forKey: .dnsName)
    self.hostName = try container.decodeIfPresent(String.self, forKey: .hostName)
    self.addresses = try container.decode([String].self, forKey: .addresses)
    self.os = try container.decode(String.self, forKey: .os)
    self.online = try container.decode(Bool.self, forKey: .online)
    self.active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? false
    self.lastSeen = try container.decodeIfPresent(Date.self, forKey: .lastSeen)
    self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    self.ownerName = try container.decodeIfPresent(String.self, forKey: .ownerName)
    self.relay = try container.decodeIfPresent(String.self, forKey: .relay)
    self.provider = try container.decode(VPNProvider.self, forKey: .provider)
  }

  public var machineName: String? {
    SystemVPNPeerDiscovery.extractMachineName(from: dnsName)
  }

  public var meaningfulHostName: String? {
    guard let raw = hostName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty,
      !SystemVPNPeerDiscovery.isGenericHostName(raw),
      raw.caseInsensitiveCompare(name) != .orderedSame
    else {
      return nil
    }
    return raw
  }

  public var isLikelyAppleMobileDevice: Bool {
    let lowerOS = os.lowercased()
    return lowerOS.contains("ios") || lowerOS.contains("ipados")
  }

  public var isLikelyMacOSDevice: Bool {
    let lowerOS = os.lowercased()
    return lowerOS.contains("macos") || lowerOS.contains("darwin")
  }

  public var isUnknownOS: Bool {
    let lowerOS = os.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return lowerOS.isEmpty || lowerOS == "unknown"
  }

  public var isLikelyIPad: Bool {
    os.lowercased().contains("ipados")
      || name.lowercased().contains("ipad")
      || (dnsName?.lowercased().contains("ipad") ?? false)
  }

  public var isLikelyIPhone: Bool {
    isLikelyAppleMobileDevice
      && !isLikelyIPad
      && (name.lowercased().contains("iphone")
        || (dnsName?.lowercased().contains("iphone") ?? false))
  }

  public var preferredPrivateIP: String? {
    if let v4 = addresses.first(where: { !$0.contains(":") && IPValidation.isPrivateVPNAddress($0) }
    ) {
      return v4
    }
    return addresses.first(where: { IPValidation.isPrivateVPNAddress($0) })
  }
}

public struct VPNEnvironmentStatus: Codable, Sendable, Equatable {
  public let provider: VPNProvider
  public let available: Bool
  public let detail: String
  public let peers: [VPNPeer]

  public init(provider: VPNProvider, available: Bool, detail: String, peers: [VPNPeer]) {
    self.provider = provider
    self.available = available
    self.detail = detail
    self.peers = peers
  }
}

public protocol VPNPeerDiscovering: Sendable {
  func discoverPeers(provider: VPNProvider) async -> VPNEnvironmentStatus
}

public final class SystemVPNPeerDiscovery: VPNPeerDiscovering, Sendable {
  private let runner: any CommandRunning
  private let candidatePaths: [String]

  public init(
    runner: any CommandRunning = SubprocessRunner(),
    candidatePaths: [String] = [
      "/opt/homebrew/bin/tailscale",
      "/usr/local/bin/tailscale",
      "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ]
  ) {
    self.runner = runner
    self.candidatePaths = candidatePaths
  }

  public func discoverPeers(provider: VPNProvider) async -> VPNEnvironmentStatus {
    guard provider.supportsAutomaticDiscovery else {
      return VPNEnvironmentStatus(
        provider: provider,
        available: true,
        detail: provider.setupHint,
        peers: []
      )
    }

    guard
      let executable = candidatePaths.first(where: {
        FileManager.default.isExecutableFile(atPath: $0)
      })
    else {
      return VPNEnvironmentStatus(
        provider: provider,
        available: false,
        detail:
          "Tailscale CLI was not found on this Mac. Install Tailscale CLI or enter the device's private VPN IP manually.",
        peers: []
      )
    }

    do {
      let result = try await runner.run(
        executable: executable,
        arguments: ["status", "--json"],
        timeoutSeconds: 8
      )
      guard result.exitCode == 0, !result.timedOut else {
        let err = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
        return VPNEnvironmentStatus(
          provider: provider,
          available: false,
          detail: err.isEmpty ? "Tailscale daemon is not running or not logged in." : err,
          peers: []
        )
      }
      let peers = Self.parseTailscaleStatusJSON(result.stdout, provider: provider)
      let mobileCount = peers.filter(\.isLikelyAppleMobileDevice).count
      let detail: String
      if peers.isEmpty {
        detail = "Discovered 0 peer(s) via \(executable)."
      } else if mobileCount > 0 {
        detail = "Found \(mobileCount) iOS/iPadOS peer(s) (\(peers.count) total) via \(executable)."
      } else {
        detail =
          "Discovered \(peers.count) peer(s) via \(executable) (no iOS/iPadOS peers found)."
      }
      return VPNEnvironmentStatus(
        provider: provider,
        available: true,
        detail: detail,
        peers: peers
      )
    } catch {
      return VPNEnvironmentStatus(
        provider: provider,
        available: false,
        detail: "Failed querying Tailscale CLI: \(error.localizedDescription)",
        peers: []
      )
    }
  }

  public static func extractMachineName(from dnsName: String?) -> String? {
    guard let dnsName else { return nil }
    let trimmed = dnsName.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    guard !trimmed.isEmpty, let first = trimmed.split(separator: ".").first, !first.isEmpty else {
      return nil
    }
    return String(first)
  }

  public static func isGenericHostName(_ value: String) -> Bool {
    let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return lower.isEmpty || lower == "localhost" || lower == "localhost.localdomain"
      || lower == "unknown"
  }

  public static func parseTailscaleTimestamp(_ raw: String?) -> Date? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]

    guard let date = withFractional.date(from: trimmed) ?? standard.date(from: trimmed) else {
      return nil
    }
    // Go's zero time.Time ("0001-01-01T00:00:00Z") parses as a valid ISO8601 date.
    guard date.timeIntervalSince1970 > 946_684_800 else {
      return nil
    }
    return date
  }

  public static func parseTailscaleStatusJSON(
    _ data: Data,
    provider: VPNProvider = .tailscale
  ) -> [VPNPeer] {
    guard let decoded = try? JSONDecoder().decode(TailscaleStatusPayload.self, from: data),
      let rawPeers = decoded.peer
    else {
      return []
    }

    let usersByID = decoded.user ?? [:]
    var results: [VPNPeer] = []
    for (key, node) in rawPeers {
      let validIPs = (node.tailscaleIPs ?? []).filter { IPValidation.isPrivateVPNAddress($0) }
      guard !validIPs.isEmpty else { continue }

      let machineName = extractMachineName(from: node.dnsName)
      let trimmedHostName = node.hostName?.trimmingCharacters(in: .whitespacesAndNewlines)
      let nonEmptyHostName = trimmedHostName.flatMap { $0.isEmpty ? nil : $0 }

      let displayName: String
      if let machineName {
        displayName = machineName
      } else if let nonEmptyHostName, !isGenericHostName(nonEmptyHostName) {
        displayName = nonEmptyHostName
      } else if let nonEmptyHostName {
        displayName = nonEmptyHostName
      } else {
        displayName = key
      }

      let ownerName: String? = node.userID.flatMap { uid in
        guard let profile = usersByID[String(uid)] else { return nil }
        let display = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let display, !display.isEmpty {
          return display
        }
        let login = profile.loginName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let login, !login.isEmpty {
          return login
        }
        return nil
      }

      let cleanedTags = (node.tags ?? [])
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      let cleanedRelay = node.relay?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let nonEmptyRelay = cleanedRelay.flatMap { $0.isEmpty ? nil : $0 }

      results.append(
        VPNPeer(
          id: node.id ?? key,
          name: displayName,
          dnsName: node.dnsName,
          hostName: nonEmptyHostName,
          addresses: validIPs,
          os: node.os ?? "unknown",
          online: node.online ?? false,
          active: node.active ?? false,
          lastSeen: parseTailscaleTimestamp(node.lastSeen),
          tags: cleanedTags,
          ownerName: ownerName,
          relay: nonEmptyRelay,
          provider: provider
        )
      )
    }
    return results.sorted { lhs, rhs in
      if lhs.isLikelyAppleMobileDevice != rhs.isLikelyAppleMobileDevice {
        return lhs.isLikelyAppleMobileDevice
      }
      if lhs.isLikelyMacOSDevice != rhs.isLikelyMacOSDevice {
        return lhs.isLikelyMacOSDevice
      }
      if lhs.active != rhs.active {
        return lhs.active
      }
      if lhs.online != rhs.online {
        return lhs.online
      }
      if lhs.lastSeen != rhs.lastSeen {
        return (lhs.lastSeen ?? .distantPast) > (rhs.lastSeen ?? .distantPast)
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }
}

private struct TailscaleStatusPayload: Decodable {
  let backendState: String?
  let peer: [String: TailscalePeerNode]?
  let user: [String: TailscaleUserProfile]?

  private enum CodingKeys: String, CodingKey {
    case backendState = "BackendState"
    case peer = "Peer"
    case user = "User"
  }
}

private struct TailscaleUserProfile: Decodable {
  let id: Int64?
  let loginName: String?
  let displayName: String?

  private enum CodingKeys: String, CodingKey {
    case id = "ID"
    case loginName = "LoginName"
    case displayName = "DisplayName"
  }
}

private struct TailscalePeerNode: Decodable {
  let id: String?
  let hostName: String?
  let dnsName: String?
  let os: String?
  let tailscaleIPs: [String]?
  let online: Bool?
  let active: Bool?
  let lastSeen: String?
  let tags: [String]?
  let userID: Int64?
  let relay: String?

  private enum CodingKeys: String, CodingKey {
    case id = "ID"
    case hostName = "HostName"
    case dnsName = "DNSName"
    case os = "OS"
    case tailscaleIPs = "TailscaleIPs"
    case online = "Online"
    case active = "Active"
    case lastSeen = "LastSeen"
    case tags = "Tags"
    case userID = "UserID"
    case relay = "Relay"
  }
}
