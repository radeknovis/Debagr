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

}
