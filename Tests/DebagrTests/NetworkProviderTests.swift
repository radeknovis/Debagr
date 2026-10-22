import XCTest

@testable import Debagr

final class NetworkProviderTests: XCTestCase {
  func testProviderAddressPoliciesRejectPublicAndSpecialDestinations() throws {
    for provider in NetworkProvider.allCases {
      XCTAssertTrue(provider.allowsAddress("100.64.0.2"))
      for ip in [
        "8.8.8.8", "127.0.0.1", "0.0.0.0", "169.254.1.1", "224.0.0.1",
        "255.255.255.255", "::1", "fd00::1", "10.0.0.999", "10.00.0.2",
        "+10.0.0.2", "10.0.0.2\n", "example.com",
      ] {
        XCTAssertFalse(provider.allowsAddress(ip), "\(provider): \(ip)")
      }
      for ip in ["10.20.0.2", "172.16.0.2", "172.31.255.254", "192.168.20.2"] {
        XCTAssertEqual(provider.allowsAddress(ip), provider != .tailscale)
      }
      XCTAssertFalse(provider.allowsAddress("172.32.0.2"))
    }
  }

  func testManualProvidersResolveWithoutTailscaleAndProfilesRoundTrip() throws {
    for provider in [NetworkProvider.zerotier, .netbird, .wireguard] {
      let peer = try provider.resolvePeer("10.20.0.2")
      XCTAssertEqual(peer.ipAddress, "10.20.0.2")
      XCTAssertFalse(peer.online, "Manual selection must not claim network readiness")
      XCTAssertThrowsError(try provider.resolvePeer("8.8.8.8"))
      let profile = DeviceProfile(
        bonjourName: "phone", bonjourTXT: ["identity": "test"], provider: provider.rawValue,
        peerIP: peer.ipAddress, remotePort: 49152, localPortRange: [55000, 58000])
      try profile.validate()
      let decoded = try JSONDecoder().decode(
        DeviceProfile.self, from: JSONEncoder().encode(profile))
      XCTAssertEqual(decoded, profile)
      try decoded.validate()
      XCTAssertNoThrow(
        try DirectDeviceApplication.makeProxy(
          profile: decoded, peer: peer, interfaceName: "en0", localIP: "192.168.1.2",
          localPort: 49152))
    }
  }

  func testHeadscaleDiscoveryAllowsPrivatePoolAndFiltersOfflinePeers() throws {
    let data = Data(
      #"{"BackendState":"Running","Peer":{"a":{"HostName":"phone","DNSName":"phone.test","TailscaleIPs":["10.20.0.2"],"Online":true},"b":{"TailscaleIPs":["10.20.0.3"],"Online":false},"c":{"TailscaleIPs":["8.8.8.8"],"Online":true}}}"#
        .utf8)
    XCTAssertEqual(
      try TailscaleClient.onlinePeers(from: data, provider: .headscale).map(\.ipAddress),
      ["10.20.0.2"])
    XCTAssertTrue(try TailscaleClient.onlinePeers(from: data).isEmpty)
    for state in ["NeedsLogin", "Stopped", "NoState"] {
      XCTAssertThrowsError(
        try TailscaleClient.onlinePeers(from: Data("{\"BackendState\":\"\(state)\"}".utf8)))
    }
  }

  func testProviderSelectionIsExplicitAndLimitedToSetup() throws {
    for provider in NetworkProvider.allCases {
      let options = try CommandLineOptions.parse([
        "--configure", "--device", "phone", "--provider", provider.rawValue,
        "--peer", "10.20.0.2", "--bonjour-host", "phone.local", "--json",
      ])
      XCTAssertEqual(options.provider, provider)
    }
    XCTAssertEqual(try CommandLineOptions.parse([]).provider, .tailscale)
    for args in [
      ["--provider", "unknown"], ["--devices", "--provider", "zerotier"],
      ["--direct-device", "--peer", "phone", "--provider", "wireguard"],
      ["--deploy-app", "/tmp/App.app", "--device", "phone", "--provider", "netbird"],
    ] { XCTAssertThrowsError(try CommandLineOptions.parse(args)) }
  }

  func testSwitchingProvidersChangesManagedConnectionIdentity() {
    func device(_ provider: String) -> ConfiguredDevice {
      ConfiguredDevice(
        deviceIdentifier: "phone", displayName: "Phone", peerName: "100.64.0.2",
        profile: DeviceProfile(
          bonjourName: "phone", bonjourTXT: ["identity": "test"],
          provider: provider, peerIP: "100.64.0.2", remotePort: 49152,
          localPortRange: [55000, 58000]))
    }
    XCTAssertFalse(device("tailscale").hasSameConnection(as: device("netbird")))
    XCTAssertTrue(device("netbird").hasSameConnection(as: device("netbird")))
  }
}
