import Foundation

struct SelectedTailscalePeer: Equatable {
  let hostname: String
  let dnsName: String
  let ipAddress: String
  let online: Bool
}

enum TailscaleError: LocalizedError {
  case executableNotFound
  case commandFailed(Int32)
  case invalidJSON(String)
  case peerNotFound(String)
  case peerIsOffline(String)
  case peerHasNoAllowedIPv4(String)
  case ambiguousPeer(String)

  var errorDescription: String? {
    switch self {
    case .executableNotFound:
      return "Could not find tailscale in a supported fixed executable path."
    case .commandFailed(let status):
      return "tailscale status --json failed with exit status \(status)."
    case .invalidJSON(let details):
      return "Unable to decode tailscale status --json: \(details)"
    case .peerNotFound(let name):
      return "No Tailscale peer matched the explicit selection '\(name)'."
    case .peerIsOffline(let name):
      return "The selected Tailscale peer '\(name)' is offline."
    case .peerHasNoAllowedIPv4(let name):
      return "The selected Tailscale peer '\(name)' has no allowed 100.64.0.0/10 IPv4 address."
    case .ambiguousPeer(let name):
      return "The explicit Tailscale peer selection '\(name)' matched more than one peer."
    }
  }
}

final class TailscaleClient {
  static let supportedExecutablePaths = [
    "/opt/homebrew/bin/tailscale",
    "/usr/local/bin/tailscale",
    "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
  ]

  private struct Status: Decodable {
    let peers: [String: Peer]

    enum CodingKeys: String, CodingKey {
      case peers = "Peer"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      peers = try container.decodeIfPresent([String: Peer].self, forKey: .peers) ?? [:]
    }
  }

  private struct Peer: Decodable {
    let hostname: String?
    let dnsName: String?
    let tailscaleIPs: [String]
    let online: Bool?

    enum CodingKeys: String, CodingKey {
      case hostname = "HostName"
      case dnsName = "DNSName"
      case tailscaleIPs = "TailscaleIPs"
      case online = "Online"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
      dnsName = try container.decodeIfPresent(String.self, forKey: .dnsName)
      tailscaleIPs = try container.decodeIfPresent([String].self, forKey: .tailscaleIPs) ?? []
      online = try container.decodeIfPresent(Bool.self, forKey: .online)
    }
  }

  func selectPeer(named requestedName: String) throws -> SelectedTailscalePeer {
    let path = try executablePath()
    let data = try statusJSON(at: path)

    let status: Status
    do {
      status = try JSONDecoder().decode(Status.self, from: data)
    } catch {
      throw TailscaleError.invalidJSON(error.localizedDescription)
    }

    let normalizedRequest = normalizeHostName(requestedName)
    let matches = status.peers.values.filter { peer in
      let exactNames = [peer.hostname, peer.dnsName]
        .compactMap { $0 }
        .map(normalizeHostName)
      let shortDNSName = peer.dnsName?
        .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
        .first
        .map(String.init)
        .map(normalizeHostName)

      return exactNames.contains(normalizedRequest) || shortDNSName == normalizedRequest
    }

    guard !matches.isEmpty else {
      throw TailscaleError.peerNotFound(requestedName)
    }
    guard matches.count == 1 else {
      throw TailscaleError.ambiguousPeer(requestedName)
    }

    let peer = matches[0]
    let displayName = peer.hostname ?? peer.dnsName ?? requestedName
    guard peer.online == true else {
      throw TailscaleError.peerIsOffline(displayName)
    }

    guard let ipAddress = peer.tailscaleIPs.first(where: NetworkSupport.isAllowedTailscaleIPv4)
    else {
      throw TailscaleError.peerHasNoAllowedIPv4(displayName)
    }

    return SelectedTailscalePeer(
      hostname: peer.hostname ?? requestedName,
      dnsName: peer.dnsName ?? "",
      ipAddress: ipAddress,
      online: true
    )
  }

  private func executablePath() throws -> String {
    guard
      let path = Self.supportedExecutablePaths.first(where: {
        FileManager.default.isExecutableFile(atPath: $0)
      })
    else {
      throw TailscaleError.executableNotFound
    }
    return path
  }

  private func statusJSON(at path: String) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["status", "--json"]
    process.standardInput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    let output = Pipe()
    process.standardOutput = output

    do {
      try process.run()
    } catch {
      throw TailscaleError.commandFailed(-1)
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      throw TailscaleError.commandFailed(process.terminationStatus)
    }
    return data
  }

  private func normalizeHostName(_ name: String) -> String {
    name
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      .lowercased()
  }
}
