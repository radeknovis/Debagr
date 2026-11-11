import AppKit
import XCTest

@testable import Debagr

final class MachineRoleWindowTests: XCTestCase {
  @MainActor
  func testDiagramSelectionRejectsLegacyPeerAndPreservesSavedPairOnFailure() throws {
    _ = NSApplication.shared
    let suite = "RoleWindowTest-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let keyFolder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { try? FileManager.default.removeItem(at: keyFolder) }
    let discovery = DebagrPeerDiscovery(
      defaults: defaults, identityURL: keyFolder.appendingPathComponent("key"))
    defer { discovery.stop() }
    let session = USBIPSessionController(defaults: defaults)
    let controller = InitialPairingCoordinator(discovery: discovery, session: session)
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    @MainActor
    func descendants(_ view: NSView) -> [NSView] {
      [view] + ((view as? NSStackView)?.views ?? view.subviews).flatMap { descendants($0) }
    }
    // Results arrive asynchronously; a fixed delay is too short on a loaded machine.
    @MainActor
    func wait(until condition: () -> Bool) {
      let deadline = Date().addingTimeInterval(5)
      while !condition(), Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      }
    }
    let views = descendants(try XCTUnwrap(window.contentView))
    let remote = DebagrPeer(
      protocolVersion: 1, nodeID: "other", name: "MacBook Air", roles: ["app"])
    let row = DiscoveredDebagrPeer(peer: remote, address: "10.0.0.2", source: "Test")
    discovery.onChange?([row], "Found")
    let choice = try XCTUnwrap(
      controller.machineMenu(for: .client).items.first { $0.title == "MacBook Air" })
    NSApp.sendAction(try XCTUnwrap(choice.action), to: choice.target, from: choice)
    wait {
      views.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Update Debagr") }
    }
    XCTAssertNil(try discovery.localSelection)
    XCTAssertTrue(
      views.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Update Debagr") })
    let saved = MachineRoleSelection(role: .builder, peerID: "other", peerName: "MacBook Air")
    try MachineRoleStore(defaults: defaults).save(saved, localNodeID: discovery.localNodeID)
    var confirmed = remote
    confirmed.machineRole = .client
    confirmed.pairedNodeID = discovery.localNodeID
    discovery.onChange?(
      [DiscoveredDebagrPeer(peer: confirmed, address: "10.0.0.2", source: "Test")], "Confirmed")
    let swap = try XCTUnwrap(
      controller.machineMenu(for: .builder).items.first { $0.title == "MacBook Air" })
    NSApp.sendAction(try XCTUnwrap(swap.action), to: swap.target, from: swap)
    let builder = try XCTUnwrap(
      views.compactMap { $0 as? NSButton }.first {
        $0.accessibilityIdentifier() == "builderMacPicker"
      })
    wait { (builder.accessibilityValue() as? String)?.contains("this Mac") == true }
    XCTAssertEqual(
      try discovery.localSelection, saved, "A failed direct choice must keep the working pair")
    XCTAssertTrue((builder.accessibilityValue() as? String)?.contains("this Mac") == true)
    let clear = try XCTUnwrap(
      views.compactMap { $0 as? NSButton }.first { $0.title == "Unpair This Mac" })
    clear.performClick(nil)
    wait { (try? discovery.localSelection) == nil }
    XCTAssertNil(try discovery.localSelection)
    session.onChange?("Old USB failure that belongs to the previous pair", false)
    XCTAssertFalse(
      views.compactMap { $0 as? NSTextField }.contains {
        $0.stringValue.contains("Old USB failure")
      })
  }
}
