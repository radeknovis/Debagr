import XCTest

@testable import NuticastPOC

final class ParserTests: XCTestCase {
  func testBonjourZoneParserNormalizesSRVAndTXT() {
    var parser = BonjourZoneParser()
    parser.consume("_remotepairing._tcp.local. 120 IN PTR My\\032iPhone._remotepairing._tcp.local.")
    parser.consume(
      "My\\032iPhone._remotepairing._tcp.local. 120 IN SRV 0 0 49640 remote-mac.local.")
    parser.consume(
      "My\\032iPhone._remotepairing._tcp.local. 120 IN TXT \"pairing_tag=secret\" \"flags=1\"")

    XCTAssertEqual(
      parser.device,
      BonjourDevice(
        instanceName: "My iPhone",
        serviceType: "_remotepairing._tcp",
        hostName: "remote-mac.local",
        port: 49_640,
        txt: ["pairing_tag": "secret", "flags": "1"]
      )
    )
  }

  func testBonjourZoneParserKeepsFirstServiceOnly() {
    var parser = BonjourZoneParser()
    parser.consume("_remotepairing._tcp.local. PTR First._remotepairing._tcp.local.")
    parser.consume("First._remotepairing._tcp.local. SRV 0 0 49640 first.local.")
    parser.consume("_remotepairing._tcp.local. PTR Second._remotepairing._tcp.local.")
    parser.consume("Second._remotepairing._tcp.local. SRV 0 0 49641 second.local.")

    XCTAssertEqual(parser.device?.instanceName, "First")
    XCTAssertEqual(parser.device?.port, 49_640)
    XCTAssertEqual(parser.device?.hostName, "first.local")
  }

  func testTunnelPortParserAcceptsIPv4AndIPv6Endpoints() {
    XCTAssertEqual(
      TunnelPortParser.port(in: "remotepairingd: Got tunnel endpoint: '100.64.0.2:49640'"),
      49_640
    )
    XCTAssertEqual(
      TunnelPortParser.port(in: "remotepairingd: Got tunnel endpoint: '[fd7a::2]:49641'"),
      49_641
    )
    XCTAssertNil(TunnelPortParser.port(in: "remotepairingd: endpoint unavailable"))
  }

  func testProfileUsesRequestedShapeAndValidatesTailscaleIP() throws {
    let profile = DeviceProfile(
      bonjourName: "Remote iPhone",
      provider: "tailscale",
      peerIP: "100.64.0.2",
      remotePort: 49_640,
      localPortRange: [55_000, 58_000]
    )

    let data = try JSONEncoder().encode(profile)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertTrue(json.contains("\"bonjourName\""))
    XCTAssertTrue(json.contains("\"localPortRange\""))
    try profile.validate()
    XCTAssertTrue(NetworkSupport.isAllowedTailscaleIPv4("100.127.255.255"))
    XCTAssertFalse(NetworkSupport.isAllowedTailscaleIPv4("192.168.1.2"))
  }

  func testBonjourProxyArgumentsAreAnArgumentArray() {
    let arguments = BonjourProxy.makeArguments(
      interfaceName: "en0",
      instanceName: "Remote iPhone",
      serviceType: "_remotepairing._tcp",
      domain: "local",
      localPort: 55_000,
      localHost: "mac.local.",
      localIP: "192.168.1.10",
      txt: ["flags": "1"]
    )

    XCTAssertEqual(
      arguments.prefix(9),
      [
        "-i", "en0", "-P", "Remote iPhone", "_remotepairing._tcp",
        "local", "55000", "mac.local.", "192.168.1.10",
      ])
    XCTAssertEqual(arguments.last, "flags=1")
  }
}
