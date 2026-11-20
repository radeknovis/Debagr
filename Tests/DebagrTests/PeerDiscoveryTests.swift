import XCTest

@testable import Debagr

final class PeerDiscoveryTests: XCTestCase {
  func testProcessRolesUseExecutableNamesInsteadOfCommandText() {
    XCTAssertEqual(
      DebagrPeer.roles(in: "/Applications/Debagr.app/Contents/MacOS/Debagr\n"), ["app"])
    XCTAssertEqual(
      DebagrPeer.roles(in: " /Users/me/tool folder/usbip-macos\n/usr/local/bin/longcable-server\n"),
      ["app", "client", "server"])
    XCTAssertEqual(DebagrPeer.roles(in: "/tmp/not-usbip-macos\n/bin/echo\n"), ["app"])
  }

  func testDiscoveryResponseRequiresSupportedVersionAndRoles() throws {
    let peer = DebagrPeer(
      protocolVersion: 1, nodeID: "mac", name: "Build Mac", roles: ["app", "client"])
    XCTAssertEqual(try DebagrPeer.decode(JSONEncoder().encode(peer)), peer)
    for peer in [
      DebagrPeer(protocolVersion: 2, nodeID: "mac", name: "Mac", roles: ["app"]),
      DebagrPeer(protocolVersion: 1, nodeID: "", name: "Mac", roles: ["app"]),
      DebagrPeer(protocolVersion: 1, nodeID: "mac", name: "", roles: ["app"]),
      DebagrPeer(protocolVersion: 1, nodeID: "mac", name: "Mac", roles: ["ready"]),
      DebagrPeer(protocolVersion: 1, nodeID: "mac", name: "Mac", roles: []),
    ] { XCTAssertThrowsError(try DebagrPeer.decode(JSONEncoder().encode(peer))) }
    XCTAssertThrowsError(try DebagrPeer.decode(Data(repeating: 32, count: 16_385)))
    XCTAssertThrowsError(try DebagrPeer.decode(Data("HTTP/1.1 200 OK".utf8)))
  }

  func testOpenPortAloneIsNotEvidenceOfUSBIPServer() {
    XCTAssertTrue(DebagrPeerDiscovery.isUSBIPReply(Data([1, 17, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0])))
    XCTAssertFalse(DebagrPeerDiscovery.isUSBIPReply(Data([1, 17, 0, 5, 0, 0, 0, 0])))
    XCTAssertFalse(DebagrPeerDiscovery.isUSBIPReply(Data([1, 17, 0, 5, 0, 0, 0, 1, 0, 0, 0, 0])))
    XCTAssertFalse(DebagrPeerDiscovery.isUSBIPReply(Data("HTTP/1.1 200 OK".utf8)))
  }

  func testDeviceSummaryIsBoundedOptionalAndContainsNoUSBIdentifiers() throws {
    var peer = DebagrPeer(protocolVersion: 1, nodeID: "mac", name: "Mac", roles: ["app"])
    XCTAssertNil(try DebagrPeer.decode(JSONEncoder().encode(peer)).connectedDeviceNames)
    peer.connectedDeviceNames = ["iPhone", "iPad"]
    XCTAssertEqual(
      try DebagrPeer.decode(JSONEncoder().encode(peer)).connectedDeviceNames, ["iPhone", "iPad"])
    for invalid in [
      [""], [String(repeating: "x", count: 129)], ["iPhone\nspoof"],
      Array(repeating: "iPhone", count: 33),
    ] {
      peer.connectedDeviceNames = invalid
      XCTAssertThrowsError(try DebagrPeer.decode(JSONEncoder().encode(peer)))
    }
    let phone = USBIPDevice(
      serial: "secret", name: "iPhone\nUSB", vendorID: 0x05ac, productID: 1, locationID: 1)
    XCTAssertTrue(phone.isAppleMobileDevice)
    XCTAssertEqual(phone.inventoryName, "iPhone USB")
    XCTAssertFalse(
      USBIPDevice(
        serial: "mouse", name: "Apple Mouse", vendorID: 0x05ac, productID: 2, locationID: 2
      ).isAppleMobileDevice)
  }

  func testDiscoveryRunsOnlyWhileThePairingScreenIsOpenOrARoleIsSaved() {
    XCTAssertFalse(DebagrPeerDiscovery.shouldRun(screenOpen: false, roleSaved: false))
    XCTAssertTrue(DebagrPeerDiscovery.shouldRun(screenOpen: true, roleSaved: false))
    XCTAssertTrue(DebagrPeerDiscovery.shouldRun(screenOpen: false, roleSaved: true))
    XCTAssertTrue(DebagrPeerDiscovery.shouldRun(screenOpen: true, roleSaved: true))
  }

  @MainActor
  func testStoppedDiscoveryReportsNoPeersWithoutScanning() throws {
    let suite = "StoppedDiscoveryTest-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let keyFolder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { try? FileManager.default.removeItem(at: keyFolder) }
    let discovery = DebagrPeerDiscovery(
      defaults: defaults, identityURL: keyFolder.appendingPathComponent("key"))
    defer { discovery.stop() }
    var reports: [(rows: Int, status: String)] = []
    discovery.onChange = { rows, status in reports.append((rows.count, status)) }
    // No role is saved and the screen is closed, so neither call may start a scan.
    discovery.updateRunning()
    discovery.refresh()
    let deadline = Date().addingTimeInterval(5)
    while reports.isEmpty, Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    XCTAssertEqual(reports.first?.rows, 0)
    XCTAssertEqual(reports.first?.status, "", "A running scan reports that it is looking")
  }

  func testOnlyThisMacAndTheSameTailscaleUserReceiveSIPStatusAndDeviceNames() throws {
    var snapshot = DebagrPeer(
      protocolVersion: 1, nodeID: "mac", name: "Build Mac", roles: ["app", "client"])
    snapshot.machineRole = .builder
    snapshot.pairedNodeID = "other"
    snapshot.roleSyncPublicKey = Data(repeating: 1, count: 32).base64EncodedString()
    snapshot.connectedDeviceNames = ["iPhone"]
    snapshot.sipStatus = .disabled
    var minimal = snapshot
    minimal.connectedDeviceNames = nil
    minimal.sipStatus = nil
    func reply(_ remote: String, own: Bool) throws -> DebagrPeer {
      // Decode the bytes a requester receives, not the value before encoding.
      try DebagrPeer.decode(
        JSONEncoder().encode(
          DebagrPeerDiscovery.reply(snapshot, to: remote, ownTailnetDevice: own)))
    }
    XCTAssertEqual(try reply("127.0.0.1", own: false), snapshot)
    XCTAssertEqual(try reply("100.64.0.2", own: true), snapshot)
    for (remote, own) in [
      ("192.168.1.20", false), ("10.0.0.5", false), ("100.64.0.2", false),
      ("192.168.1.20", true),
    ] {
      XCTAssertEqual(try reply(remote, own: own), minimal, "\(remote) verified: \(own)")
    }
    let sent = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(
          DebagrPeerDiscovery.reply(snapshot, to: "192.168.1.20", ownTailnetDevice: false)))
        as? [String: Any])
    XCTAssertEqual(
      Set(sent.keys),
      [
        "protocolVersion", "nodeID", "name", "roles", "machineRole", "pairedNodeID",
        "roleSyncPublicKey",
      ])
  }
}
