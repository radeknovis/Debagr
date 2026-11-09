import AppKit
import XCTest

@testable import Debagr

final class SystemIntegrityStatusTests: XCTestCase {
  func testSIPParserNeverTreatsCustomFailedOrUnrecognizedOutputAsOff() {
    XCTAssertEqual(
      SystemIntegrityStatus.parse("System Integrity Protection status: disabled.\n"), .disabled)
    XCTAssertEqual(
      SystemIntegrityStatus.parse("System Integrity Protection status: enabled.\n"), .enabled)
    XCTAssertEqual(
      SystemIntegrityStatus.parse(
        "System Integrity Protection status: enabled.\nConfiguration:\nDebugging Restrictions: disabled"
      ), .enabled)
    XCTAssertEqual(
      SystemIntegrityStatus.parse(
        "System Integrity Protection status: unknown (Custom Configuration).\nConfiguration:\nDebugging Restrictions: disabled"
      ), .custom)
    XCTAssertEqual(
      SystemIntegrityStatus.parse(
        "System Integrity Protection status: disabled (Custom Configuration)."), .custom)
    XCTAssertEqual(
      SystemIntegrityStatus.parse("System Integrity Protection status: disabled.", exitStatus: 1),
      .unknown)
    XCTAssertEqual(SystemIntegrityStatus.parse(""), .unknown)
    XCTAssertEqual(SystemIntegrityStatus.parse("csrutil: failed to read status"), .unknown)
  }

  func testOptionalSIPSummaryRoundTripsAndRejectsInvalidStates() throws {
    var peer = DebagrPeer(protocolVersion: 1, nodeID: "other", name: "Air", roles: ["app"])
    XCTAssertNil(try DebagrPeer.decode(JSONEncoder().encode(peer)).sipStatus)
    peer.sipStatus = .disabled
    XCTAssertEqual(try DebagrPeer.decode(JSONEncoder().encode(peer)).sipStatus, .disabled)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(peer)) as? [String: Any])
    object["sipStatus"] = "definitely-safe"
    XCTAssertThrowsError(try DebagrPeer.decode(JSONSerialization.data(withJSONObject: object)))
  }

  func testAnnotationFollowsTheBuilderAndDiscardsStaleRemoteStatus() throws {
    _ = NSApplication.shared
    let suite = "SIPAnnotation-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { try? FileManager.default.removeItem(at: folder) }
    let discovery = DebagrPeerDiscovery(
      defaults: defaults, identityURL: folder.appendingPathComponent("key"))
    defer { discovery.stop() }
    let session = USBIPSessionController(defaults: defaults)
    let controller = InitialPairingCoordinator(
      discovery: discovery, session: session, connectedDevices: { [] })
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    func descendants(_ view: NSView) -> [NSView] {
      [view] + ((view as? NSStackView)?.views ?? view.subviews).flatMap { descendants($0) }
    }
    let annotation = try XCTUnwrap(
      descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? NSButton }.first {
        $0.accessibilityIdentifier() == "builderSIPAnnotation"
      })
    var local = DebagrPeer(
      protocolVersion: 1, nodeID: discovery.localNodeID, name: "Mini", roles: ["app"])
    local.sipStatus = .disabled
    var remote = DebagrPeer(protocolVersion: 1, nodeID: "other", name: "Air", roles: ["app"])
    remote.sipStatus = .enabled
    try MachineRoleStore(defaults: defaults).save(
      MachineRoleSelection(role: .builder, peerID: "other", peerName: "Air"),
      localNodeID: discovery.localNodeID)
    func update(lastSeen: Date = Date()) {
      discovery.onChange?(
        [
          DiscoveredDebagrPeer(peer: local, address: "This Mac", source: "Local processes"),
          DiscoveredDebagrPeer(
            peer: remote, address: "10.0.0.2", source: "Test", lastSeen: lastSeen),
        ], "Found")
    }
    update()
    XCTAssertEqual(annotation.title, SystemIntegrityStatus.disabled.annotation)
    XCTAssertEqual(annotation.contentTintColor, NSColor.systemGreen)
    XCTAssertTrue(annotation.toolTip?.contains("System protections are reduced") == true)
    try MachineRoleStore(defaults: defaults).save(
      MachineRoleSelection(role: .client, peerID: "other", peerName: "Air"),
      localNodeID: discovery.localNodeID)
    update()
    XCTAssertEqual(annotation.title, SystemIntegrityStatus.enabled.annotation)
    XCTAssertEqual(annotation.contentTintColor, NSColor.systemOrange)
    XCTAssertTrue(annotation.toolTip?.contains("Apple-approved") == true)
    update(lastSeen: Date().addingTimeInterval(-30))
    XCTAssertEqual(annotation.title, SystemIntegrityStatus.unknown.annotation)
    XCTAssertEqual(annotation.contentTintColor, NSColor.secondaryLabelColor)
    XCTAssertFalse(session.busy)
    XCTAssertNil(defaults.string(forKey: "usbip-session-request"))
  }
}
