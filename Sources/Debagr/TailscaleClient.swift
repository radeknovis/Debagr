import Darwin
import Foundation

struct SelectedNetworkPeer: Equatable {
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
  case notConnected

  var errorDescription: String? {
    switch self {
    case .executableNotFound:
      return
        "Install the Tailscale app or CLI for Tailscale / Headscale discovery, then sign in or connect to your Headscale server. Other providers can use a private IPv4 address instead."
    case .commandFailed(let status):
      return "tailscale status --json failed with exit status \(status)."
    case .invalidJSON(let details):
      return "Unable to decode tailscale status --json: \(details)"
    case .peerNotFound(let name):
      return "No Tailscale peer matched the explicit selection '\(name)'."
    case .peerIsOffline(let name):
      return "The selected Tailscale peer '\(name)' is offline."
    case .peerHasNoAllowedIPv4(let name):
      return
        "The selected Tailscale peer '\(name)' has no private IPv4 address allowed by the selected provider."
    case .ambiguousPeer(let name):
      return "The explicit Tailscale peer selection '\(name)' matched more than one peer."
    case .notConnected:
      return
        "Open the Tailscale app and sign in or connect it to your Headscale server, then turn the connection on and retry."
    }
  }
}

final class TailscaleClient {
  static let supportedExecutablePaths = [
    "/opt/homebrew/bin/tailscale",
    "/usr/local/bin/tailscale",
    "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
  ]

  static func installedExecutablePath() -> String? {
    supportedExecutablePaths.first(where: FileManager.default.isExecutableFile)
  }

  private struct Status: Decodable {
    let peers: [String: Peer]

    enum CodingKeys: String, CodingKey {
      case peers = "Peer"
      case backendState = "BackendState"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      if let state = try container.decodeIfPresent(String.self, forKey: .backendState),
        state != "Running"
      {
        throw TailscaleError.notConnected
      }
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

  func selectPeer(named requestedName: String, provider: NetworkProvider = .tailscale) throws
    -> SelectedNetworkPeer
  {
    try Self.selectPeer(
      named: requestedName, from: statusJSON(at: executablePath()), provider: provider)
  }

  static func selectPeer(
    named requestedName: String, from data: Data,
    provider: NetworkProvider = .tailscale
  ) throws -> SelectedNetworkPeer {

    let status: Status
    do {
      status = try JSONDecoder().decode(Status.self, from: data)
    } catch let error as TailscaleError {
      throw error
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
        || peer.tailscaleIPs.contains(requestedName)
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

    guard let ipAddress = peer.tailscaleIPs.first(where: provider.allowsAddress)
    else {
      throw TailscaleError.peerHasNoAllowedIPv4(displayName)
    }

    return SelectedNetworkPeer(
      hostname: peer.hostname ?? requestedName,
      dnsName: peer.dnsName ?? "",
      ipAddress: ipAddress,
      online: true
    )
  }

  func onlinePeers(provider: NetworkProvider = .tailscale) throws -> [SelectedNetworkPeer] {
    try Self.onlinePeers(from: statusJSON(at: executablePath()), provider: provider)
  }

  static func onlinePeers(from data: Data, provider: NetworkProvider = .tailscale) throws
    -> [SelectedNetworkPeer]
  {
    let status = try JSONDecoder().decode(Status.self, from: data)
    return status.peers.values.compactMap { peer in
      guard peer.online == true,
        let ip = peer.tailscaleIPs.first(where: provider.allowsAddress)
      else { return nil }
      return SelectedNetworkPeer(
        hostname: peer.hostname ?? ip, dnsName: peer.dnsName ?? "",
        ipAddress: ip, online: true)
    }.sorted { $0.dnsName < $1.dnsName }
  }

  private func executablePath() throws -> String {
    guard let path = Self.installedExecutablePath() else {
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

    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "debagr-tailscale-\(UUID().uuidString)")
    FileManager.default.createFile(
      atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    defer { try? FileManager.default.removeItem(at: url) }
    let output = try FileHandle(forWritingTo: url)
    defer { try? output.close() }
    process.standardOutput = output
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do { try process.run() } catch { throw TailscaleError.commandFailed(-1) }
    guard finished.wait(timeout: .now() + 10) == .success else {
      process.terminate()
      if finished.wait(timeout: .now() + 1) != .success { kill(process.processIdentifier, SIGKILL) }
      throw DeviceDeploymentError.timedOut
    }
    let data = try Data(contentsOf: url)

    guard process.terminationStatus == 0 else {
      throw TailscaleError.commandFailed(process.terminationStatus)
    }
    return data
  }

  private static func normalizeHostName(_ name: String) -> String {
    name
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      .lowercased()
  }
}
