import Foundation

public struct VPNPeer: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let dnsName: String?
  public let addresses: [String]
  public let os: String
  public let online: Bool
  public let provider: VPNProvider

  public init(
    id: String,
    name: String,
    dnsName: String? = nil,
    addresses: [String],
    os: String,
    online: Bool,
    provider: VPNProvider
  ) {
    self.id = id
    self.name = name
    self.dnsName = dnsName
    self.addresses = addresses
    self.os = os
    self.online = online
    self.provider = provider
  }

  public var isLikelyAppleMobileDevice: Bool {
    let lowerOS = os.lowercased()
    return lowerOS.contains("ios") || lowerOS.contains("ipados")
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
      return VPNEnvironmentStatus(
        provider: provider,
        available: true,
        detail: "Discovered \(peers.count) peer(s) via \(executable).",
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

  public static func parseTailscaleStatusJSON(
    _ data: Data,
    provider: VPNProvider = .tailscale
  ) -> [VPNPeer] {
    guard let decoded = try? JSONDecoder().decode(TailscaleStatusPayload.self, from: data),
      let rawPeers = decoded.peer
    else {
      return []
    }

    var results: [VPNPeer] = []
    for (key, node) in rawPeers {
      let validIPs = (node.tailscaleIPs ?? []).filter { IPValidation.isPrivateVPNAddress($0) }
      guard !validIPs.isEmpty else { continue }
      let displayName = node.hostName ?? node.dnsName ?? key
      results.append(
        VPNPeer(
          id: node.id ?? key,
          name: displayName,
          dnsName: node.dnsName,
          addresses: validIPs,
          os: node.os ?? "unknown",
          online: node.online ?? false,
          provider: provider
        )
      )
    }
    return results.sorted { lhs, rhs in
      if lhs.isLikelyAppleMobileDevice != rhs.isLikelyAppleMobileDevice {
        return lhs.isLikelyAppleMobileDevice
      }
      if lhs.online != rhs.online {
        return lhs.online
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }
}

private struct TailscaleStatusPayload: Decodable {
  let backendState: String?
  let peer: [String: TailscalePeerNode]?

  private enum CodingKeys: String, CodingKey {
    case backendState = "BackendState"
    case peer = "Peer"
  }
}

private struct TailscalePeerNode: Decodable {
  let id: String?
  let hostName: String?
  let dnsName: String?
  let os: String?
  let tailscaleIPs: [String]?
  let online: Bool?

  private enum CodingKeys: String, CodingKey {
    case id = "ID"
    case hostName = "HostName"
    case dnsName = "DNSName"
    case os = "OS"
    case tailscaleIPs = "TailscaleIPs"
    case online = "Online"
  }
}
