import AppKit
import XCTest

@testable import Debagr

final class NoDeviceStartTests: XCTestCase {
  func testStartWithoutADeviceExplainsNextStepBeforeNetworkingOrUSBSetup() throws {
    _ = NSApplication.shared
    for role in DebagrMachineRole.allCases {
      let suite = "NoDeviceStart-\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suite)!
      defer { defaults.removePersistentDomain(forName: suite) }
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
      defer { try? FileManager.default.removeItem(at: folder) }
      let discovery = DebagrPeerDiscovery(
        defaults: defaults, identityURL: folder.appendingPathComponent("key"))
      defer { discovery.stop() }
      try MachineRoleStore(defaults: defaults).save(
        MachineRoleSelection(role: role, peerID: "other", peerName: "Other Mac"),
        localNodeID: discovery.localNodeID)
      let session = USBIPSessionController(defaults: defaults)
      // Missing support tools must not obscure the missing-device instruction.
      defaults.set(
        folder.appendingPathComponent("missing-support").path,
        forKey: "usbip-backend-\(role.rawValue)")
      var checks = 0
      let controller = InitialPairingCoordinator(
        discovery: discovery, session: session,
        connectedDevices: { [] }, peerVerifier: { _, _ in checks += 1 })
      let window = try XCTUnwrap(controller.window)
      defer { window.close() }
      var remote = DebagrPeer(
        protocolVersion: 1, nodeID: "other", name: "Other Mac", roles: ["app"])
      remote.machineRole = role.opposite
      remote.pairedNodeID = discovery.localNodeID
      remote.connectedDeviceNames = []
      discovery.onChange?(
        [DiscoveredDebagrPeer(peer: remote, address: "10.0.0.2", source: "Test")], "Found")
      func descendants(_ view: NSView) -> [NSView] {
        [view] + ((view as? NSStackView)?.views ?? view.subviews).flatMap { descendants($0) }
      }
      let views = descendants(try XCTUnwrap(window.contentView))
      let start = try XCTUnwrap(
        views.compactMap { $0 as? NSButton }.first {
          ["Start Setup Connection", "Set Up USB Support…"].contains($0.title)
        })
      XCTAssertTrue(start.isEnabled)
      start.performClick(nil)
      XCTAssertEqual(
        checks, 0, "No device: explain the next step immediately, before waiting on another Mac")
      XCTAssertFalse(start.isHidden, "Start must remain available after the no-device message")
      let labels = views.compactMap { $0 as? NSTextField }.filter {
        !$0.isHiddenOrHasHiddenAncestor
      }.map(\.stringValue)
      XCTAssertTrue(labels.contains { $0 == "No device connected" }, "\(role): \(labels)")
      XCTAssertTrue(
        labels.contains { $0.contains("Plug in") && $0.contains("iPhone or iPad") },
        "\(role): \(labels)")
      XCTAssertNil(defaults.string(forKey: "usbip-session-request"))
    }
  }

  func testDeviceListsUpdateInTheDiagramAndMacPickerWithoutStartingUSB() throws {
    _ = NSApplication.shared
    let suite = "DeviceList-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { try? FileManager.default.removeItem(at: folder) }
    let discovery = DebagrPeerDiscovery(
      defaults: defaults, identityURL: folder.appendingPathComponent("key"))
    defer { discovery.stop() }
    let phone = USBIPDevice(
      serial: "PRIVATE-SERIAL", name: "iPhone", vendorID: 0x05ac, productID: 1, locationID: 1)
    let controller = InitialPairingCoordinator(
      discovery: discovery, session: USBIPSessionController(defaults: defaults),
      connectedDevices: { [phone] })
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    func descendants(_ view: NSView) -> [NSView] {
      [view] + ((view as? NSStackView)?.views ?? view.subviews).flatMap { descendants($0) }
    }
    let views = descendants(try XCTUnwrap(window.contentView))
    let localList = try XCTUnwrap(
      views.compactMap { $0 as? NSTextField }.first {
        $0.accessibilityLabel() == "Builder plugged-in devices"
      })
    XCTAssertEqual(localList.stringValue, "• iPhone")
    var remote = DebagrPeer(protocolVersion: 1, nodeID: "other", name: "Air", roles: ["app"])
    remote.connectedDeviceNames = ["iPad", "iPhone"]
    discovery.onChange?(
      [DiscoveredDebagrPeer(peer: remote, address: "10.0.0.2", source: "Test")], "Found")
    XCTAssertTrue(
      controller.machineMenu(for: .client).items.contains { $0.title == "iPad, iPhone" })
    XCTAssertNil(try discovery.localSelection)
    try MachineRoleStore(defaults: defaults).save(
      MachineRoleSelection(role: .builder, peerID: "other", peerName: "Air"),
      localNodeID: discovery.localNodeID)
    remote.machineRole = .client
    remote.pairedNodeID = discovery.localNodeID
    discovery.onChange?(
      [DiscoveredDebagrPeer(peer: remote, address: "10.0.0.2", source: "Test")], "Confirmed")
    let remoteList = try XCTUnwrap(
      views.compactMap { $0 as? NSTextField }.first {
        $0.accessibilityLabel() == "Client plugged-in devices"
      })
    XCTAssertEqual(remoteList.stringValue, "• iPad\n• iPhone")
    remote.connectedDeviceNames = []
    discovery.onChange?(
      [DiscoveredDebagrPeer(peer: remote, address: "10.0.0.2", source: "Test")], "Unplugged")
    XCTAssertEqual(remoteList.stringValue, "No device connected")
    let start = try XCTUnwrap(
      views.compactMap { $0 as? NSButton }.first { $0.title == "Start Setup Connection" })
    start.performClick(nil)
    XCTAssertTrue(
      views.compactMap { $0 as? NSTextField }.contains {
        $0.stringValue.contains("Plug in and unlock an iPhone or iPad on Air")
      })
    remote.connectedDeviceNames = ["iPhone"]
    discovery.onChange?(
      [DiscoveredDebagrPeer(peer: remote, address: "10.0.0.2", source: "Test")], "Plugged in")
    XCTAssertEqual(remoteList.stringValue, "• iPhone")
    XCTAssertFalse(
      views.compactMap { $0 as? NSTextField }.contains {
        $0.stringValue.contains("Plug in and unlock an iPhone or iPad on Air")
      })
    let stale = DiscoveredDebagrPeer(
      peer: remote, address: "10.0.0.2", source: "Test", lastSeen: Date().addingTimeInterval(-30))
    discovery.onChange?([stale], "Unreachable")
    XCTAssertEqual(remoteList.stringValue, "Device list unavailable — Refresh")
    XCTAssertNil(defaults.string(forKey: "usbip-session-request"))
    XCTAssertFalse(
      views.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("PRIVATE-SERIAL") }
    )
  }

}
