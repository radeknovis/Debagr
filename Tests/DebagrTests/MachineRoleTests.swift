import XCTest

@testable import Debagr

final class MachineRoleTests: XCTestCase {
  func testProductRolesMapToTheCorrectUSBIPBackend() {
    XCTAssertEqual(DebagrMachineRole.builder.backend, "usbip-macos")
    XCTAssertEqual(DebagrMachineRole.client.backend, "longcable-server")
    XCTAssertEqual(DebagrMachineRole.builder.opposite, .client)
    XCTAssertEqual(DebagrMachineRole.client.opposite, .builder)
  }

  func testSelectionPersistsWithoutMarkingAnyProcessAsRunning() throws {
    let suite = "MachineRoleTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = MachineRoleStore(defaults: defaults)
    let choice = MachineRoleSelection(role: .builder, peerID: "air", peerName: "Air")
    XCTAssertNil(try store.load())
    try store.save(choice, localNodeID: "mini")
    XCTAssertEqual(try MachineRoleStore(defaults: defaults).load(), choice)
    XCTAssertEqual(DebagrPeer.roles(in: "/Applications/Debagr.app/Contents/MacOS/Debagr"), ["app"])
    store.clear()
    XCTAssertNil(try store.load())
    for id in ["", "mini", "usbip:10.0.0.2", String(repeating: "x", count: 129)] {
      XCTAssertThrowsError(
        try store.save(
          MachineRoleSelection(role: .client, peerID: id, peerName: "Other"), localNodeID: "mini"))
    }
  }

  func testRoleSelectionRoundTripsAndOlderAnnouncementsStillDecode() throws {
    var peer = DebagrPeer(protocolVersion: 1, nodeID: "air", name: "Air", roles: ["app"])
    peer.machineRole = .client
    peer.pairedNodeID = "mini"
    XCTAssertEqual(try DebagrPeer.decode(JSONEncoder().encode(peer)), peer)
    let old = try DebagrPeer.decode(
      Data(#"{"protocolVersion":1,"nodeID":"old","name":"Older Mac","roles":["app"]}"#.utf8))
    XCTAssertNil(old.machineRole)
    XCTAssertNil(old.pairedNodeID)
    peer.pairedNodeID = "air"
    XCTAssertThrowsError(try DebagrPeer.decode(JSONEncoder().encode(peer)))
  }

  func testPairStatusRequiresOppositeRolesAndReciprocalSelection() {
    let choice = MachineRoleSelection(role: .builder, peerID: "air", peerName: "Air")
    var peer = DebagrPeer(protocolVersion: 1, nodeID: "air", name: "Air", roles: ["app"])
    XCTAssertTrue(
      choice.status(with: nil, localNodeID: "mini").contains("not currently discovered"))
    XCTAssertTrue(choice.status(with: peer, localNodeID: "mini").contains("select Client"))
    peer.machineRole = .builder
    XCTAssertTrue(choice.status(with: peer, localNodeID: "mini").contains("Role conflict"))
    peer.machineRole = .client
    peer.pairedNodeID = "different-build-mac"
    XCTAssertTrue(choice.status(with: peer, localNodeID: "mini").contains("choose this Mac"))
    peer.pairedNodeID = "mini"
    XCTAssertTrue(choice.status(with: peer, localNodeID: "mini").contains("Roles configured"))
  }

  func testConnectionRequiresAnOnlineReciprocalPairWithOppositeRoles() {
    let selection = MachineRoleSelection(role: .builder, peerID: "air", peerName: "Air")
    var peer = DebagrPeer(protocolVersion: 1, nodeID: "air", name: "Air", roles: ["app"])
    XCTAssertFalse(selection.isConfirmed(with: nil, localNodeID: "mini"))
    XCTAssertFalse(selection.isConfirmed(with: peer, localNodeID: "mini"))
    peer.machineRole = .client
    peer.pairedNodeID = "someone-else"
    XCTAssertFalse(selection.isConfirmed(with: peer, localNodeID: "mini"))
    peer.pairedNodeID = "mini"
    XCTAssertTrue(selection.isConfirmed(with: peer, localNodeID: "mini"))
    peer.machineRole = .builder
    XCTAssertFalse(selection.isConfirmed(with: peer, localNodeID: "mini"))
  }
}
