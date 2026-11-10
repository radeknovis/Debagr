import XCTest

@testable import Debagr

final class ConfigurationTests: XCTestCase {
  func testManagedConfigurationIsPrivateAndLearnedPortsStayBounded() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ManagedTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ManagedDeviceStore(url: directory.appendingPathComponent("device.json"))
    let profile = DeviceProfile(
      bonjourName: "phone", bonjourTXT: ["authTag": "test-secret"],
      provider: "tailscale", peerIP: "100.64.0.2", remotePort: 49152,
      localPortRange: [55000, 58000])
    let device = ConfiguredDevice(
      deviceIdentifier: "udid", displayName: "iPad", peerName: "ipad.test", profile: profile,
      kind: .iPad)
    try store.save(device)
    XCTAssertEqual(try store.load(), device)
    try store.toggleEnabled()
    try store.learn(port: 60549, for: device)
    XCTAssertFalse(try XCTUnwrap(store.load()).enabled)
    let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    for port: UInt16 in [1024, 60549, 65535] {
      let learned = profile.learningTunnelPort(port)
      try learned.validate()
      XCTAssertTrue((learned.tunnelPortRange[0]...learned.tunnelPortRange[1]).contains(port))
      var updated = device
      updated.profile = learned
      XCTAssertTrue(device.hasSameConnection(as: updated))
    }
  }

  func testLegacyManagedConfigurationLoadsWithoutAssumingIPhone() throws {
    let profile = DeviceProfile(
      bonjourName: "device", bonjourTXT: ["authTag": "test"],
      provider: "tailscale", peerIP: "100.64.0.2", remotePort: 49152,
      localPortRange: [55000, 58000])
    let device = ConfiguredDevice(
      deviceIdentifier: "udid", displayName: "iPad", peerName: "ipad.test", profile: profile,
      kind: .iPad)
    let data = try JSONEncoder().encode(device)
    XCTAssertEqual(try JSONDecoder().decode(ConfiguredDevice.self, from: data).kind, .iPad)
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy.removeValue(forKey: "kind")
    let decoded = try JSONDecoder().decode(
      ConfiguredDevice.self, from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertNil(decoded.kind)
    XCTAssertNoThrow(try decoded.validate())
  }

  func testRelayLeaseExcludesCompetingOwnersAndReleasesOnStop() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "LeaseTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    var lease: RelayLease? = try RelayLease(port: 49152, directory: directory)
    XCTAssertNotNil(lease)
    XCTAssertThrowsError(try RelayLease(port: 49152, directory: directory))
    lease = nil
    XCTAssertNoThrow(try RelayLease(port: 49152, directory: directory))
  }

  func testDirectDeviceRequiresProfileForSelectedPeerAndCapturedIdentity() throws {
    let peer = SelectedNetworkPeer(
      hostname: "iphone", dnsName: "iphone.test", ipAddress: "100.64.0.1", online: true)
    func profile(ip: String, txt: [String: String]) -> DeviceProfile {
      DeviceProfile(
        bonjourName: "device-service", bonjourTXT: txt, provider: "tailscale", peerIP: ip,
        remotePort: 49152, localPortRange: [55000, 58000])
    }
    XCTAssertThrowsError(
      try DirectDeviceApplication.makeProxy(
        profile: profile(ip: "100.64.0.2", txt: ["authTag": "test"]), peer: peer,
        interfaceName: "en1", localIP: "192.168.1.2", localPort: 49152))
    XCTAssertThrowsError(
      try DirectDeviceApplication.makeProxy(
        profile: profile(ip: "100.64.0.1", txt: [:]), peer: peer,
        interfaceName: "en1", localIP: "192.168.1.2", localPort: 49152))
    XCTAssertNoThrow(
      try DirectDeviceApplication.makeProxy(
        profile: profile(ip: "100.64.0.1", txt: ["authTag": "test"]), peer: peer,
        interfaceName: "en1", localIP: "192.168.1.2", localPort: 49152))
  }

  func testDirectDeviceTunnelRangeIsBoundedAndSurvivesProfileRoundTrip() throws {
    let profile = DeviceProfile(
      bonjourName: "device-service", bonjourTXT: ["authTag": "test"],
      provider: "tailscale", peerIP: "100.64.0.1", remotePort: 49152,
      localPortRange: [55000, 58000], tunnelPortRange: [50000, 50020])
    let decoded = try JSONDecoder().decode(
      DeviceProfile.self, from: JSONEncoder().encode(profile))
    XCTAssertEqual(decoded.tunnelPortRange, [50000, 50020])
    try decoded.validate()
    for range: [UInt16] in [[], [50000], [50020, 50000], [80, 100], [49152, 65535]] {
      let invalid = DeviceProfile(
        bonjourName: profile.bonjourName, bonjourTXT: profile.bonjourTXT,
        provider: profile.provider, peerIP: profile.peerIP, remotePort: profile.remotePort,
        localPortRange: profile.localPortRange, tunnelPortRange: range)
      XCTAssertThrowsError(try invalid.validate())
    }
  }

  func testProfileUsesRequestedShapeAndValidatesTailscaleIP() throws {
    let profile = DeviceProfile(
      bonjourName: "Remote iPhone",
      bonjourTXT: ["identifier": "phone-id", "flags": "0"],
      provider: "tailscale",
      peerIP: "100.64.0.2",
      remotePort: 49_640,
      localPortRange: [55_000, 58_000]
    )

    let data = try JSONEncoder().encode(profile)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertTrue(json.contains("\"bonjourName\""))
    XCTAssertTrue(json.contains("\"localPortRange\""))
    XCTAssertEqual(
      try JSONDecoder().decode(DeviceProfile.self, from: data).bonjourTXT, profile.bonjourTXT)
    try profile.validate()
    XCTAssertTrue(NetworkSupport.isAllowedTailscaleIPv4("100.127.255.255"))
    XCTAssertFalse(NetworkSupport.isAllowedTailscaleIPv4("192.168.1.2"))
  }
}
