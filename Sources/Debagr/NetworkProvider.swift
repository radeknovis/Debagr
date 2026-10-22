import Foundation

enum NetworkProvider: String, CaseIterable {
  case tailscale, headscale, zerotier, netbird, wireguard

  var displayName: String {
    switch self {
    case .tailscale: return "Tailscale"
    case .headscale: return "Headscale"
    case .zerotier: return "ZeroTier"
    case .netbird: return "NetBird"
    case .wireguard: return "WireGuard"
    }
  }

  var discoversPeers: Bool { self == .tailscale || self == .headscale }

  func allowsAddress(_ address: String) -> Bool {
    if self == .tailscale { return NetworkSupport.isAllowedTailscaleIPv4(address) }
    return NetworkSupport.isAllowedPrivateVPNIPv4(address)
  }

  func resolvePeer(_ name: String) throws -> SelectedNetworkPeer {
    if discoversPeers { return try TailscaleClient().selectPeer(named: name, provider: self) }
    guard allowsAddress(name) else { throw ProfileError.invalidPeerIP(name) }
    // Manual providers establish readiness through Apple's device check, not a VPN online flag.
    return SelectedNetworkPeer(hostname: name, dnsName: "", ipAddress: name, online: false)
  }
}
