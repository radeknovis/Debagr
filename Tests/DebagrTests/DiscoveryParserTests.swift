import XCTest

@testable import Debagr

final class DiscoveryParserTests: XCTestCase {
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

  func testBonjourZoneParserReturnsEveryCompleteService() {
    var parser = BonjourZoneParser()
    parser.consume("_remotepairing._tcp.local. PTR iPhone._remotepairing._tcp.local.")
    parser.consume("iPhone._remotepairing._tcp.local. SRV 0 0 49152 iphone.local.")
    parser.consume("iPhone._remotepairing._tcp.local. TXT \"kind=iPhone\"")
    parser.consume("_remotepairing._tcp.local. PTR iPad._remotepairing._tcp.local.")
    parser.consume("iPad._remotepairing._tcp.local. SRV 0 0 49153 ipad.local.")
    parser.consume("iPad._remotepairing._tcp.local. TXT \"kind=iPad\"")

    XCTAssertEqual(parser.devices.map(\.instanceName), ["iPad", "iPhone"])
    XCTAssertEqual(parser.devices.map(\.port), [49_153, 49_152])
    XCTAssertEqual(parser.devices[0].txt["kind"], "iPad")
    XCTAssertEqual(parser.devices[1].txt["kind"], "iPhone")
  }

  func testBonjourDeviceUsesHumanHostNameForDisplay() {
    let device = BonjourDevice(
      instanceName: "D352A1EA-2CA2-4CBE-84C9-84874F6B4645",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "Radeks-iPhone-16-Pro.local.",
      port: 49_152,
      txt: [:]
    )

    XCTAssertEqual(device.suggestedDisplayName, "Radeks iPhone 16 Pro")
    XCTAssertEqual(TargetDeviceKind.inferred(from: device), .iPhone)
  }

  func testBonjourZoneParserAcceptsDnsSDInstanceNamesWithoutLocalSuffix() {
    var parser = BonjourZoneParser()
    parser.consume("_remotepairing._tcp PTR iPhone._remotepairing._tcp")
    parser.consume("iPhone._remotepairing._tcp SRV 0 0 49152 iPhone.local.")
    parser.consume("iPhone._remotepairing._tcp TXT \"flags=0\"")

    XCTAssertEqual(
      parser.device,
      BonjourDevice(
        instanceName: "iPhone",
        serviceType: "_remotepairing._tcp",
        hostName: "iPhone.local",
        port: 49_152,
        txt: ["flags": "0"]
      )
    )
  }

  func testBonjourZoneParserCanSelectPreferredHost() {
    var parser = BonjourZoneParser(preferredHostName: "Radek-iPhone.local")
    parser.consume("_remotepairing._tcp PTR Jane._remotepairing._tcp")
    parser.consume("Jane._remotepairing._tcp SRV 0 0 49152 Jane-iPhone.local.")
    parser.consume("_remotepairing._tcp PTR Radek._remotepairing._tcp")
    parser.consume("Radek._remotepairing._tcp SRV 0 0 49153 Radek-iPhone.local.")

    XCTAssertEqual(parser.device?.instanceName, "Radek")
    XCTAssertEqual(parser.device?.hostName, "Radek-iPhone.local")
    XCTAssertEqual(parser.device?.port, 49_153)
  }

  func testTunnelPortParserAcceptsIPv4AndIPv6Endpoints() {
    XCTAssertEqual(
      TunnelPortParser.port(in: "Got tunnel endpoint: '192.168.1.140%en1:60546'"),
      60_546
    )
    XCTAssertEqual(
      TunnelPortParser.port(in: "remotepairingd: Got tunnel endpoint: '100.64.0.2:49640'"),
      49_640
    )
    XCTAssertEqual(
      TunnelPortParser.port(in: "remotepairingd: Got tunnel endpoint: '[fd7a::2]:49641'"),
      49_641
    )
    XCTAssertEqual(
      TunnelPortParser.port(
        in: "remotepairingd: Got tunnel endpoint: 'fe80::10f8:361c:ce42:fa56%en0.57652'"
      ),
      57_652
    )
    XCTAssertNil(TunnelPortParser.port(in: "remotepairingd: endpoint unavailable"))
  }

  func testBonjourProxyRejectsOversizedTXTBeforeRegistration() throws {
    let proxy = try BonjourProxy(
      interfaceName: "0", instanceName: "test", localPort: 55000,
      localHost: "test.local.", localIP: "192.168.1.10",
      txt: ["key": String(repeating: "a", count: 256)])
    XCTAssertThrowsError(try proxy.start())
    XCTAssertFalse(proxy.isHealthy)
  }
}
