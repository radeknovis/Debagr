import AppKit
import SwiftUI
import XCTest

@testable import Debagr

@MainActor
final class RestoredPairingLayoutTests: XCTestCase {
  @MainActor
  func testBothPathsUseOneRootContentAndPreserveTheWindowFrame() async throws {
    _ = NSApplication.shared
    let suite = "UnifiedPairing-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { try? FileManager.default.removeItem(at: folder) }
    let discovery = DebagrPeerDiscovery(
      defaults: defaults, identityURL: folder.appendingPathComponent("key"))
    defer { discovery.stop() }
    let initial = InitialPairingCoordinator(
      embedded: true, discovery: discovery,
      session: USBIPSessionController(defaults: defaults), connectedDevices: { [] })
    let controller = DeviceSetupWindowController(configured: nil)
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    controller.present(page: .setup)
    let root = try XCTUnwrap(window.contentView)
    XCTAssertTrue(root is NSHostingView<DeviceSetupView>)
    let presentation = initial.activate(in: window)
    controller.model.initialPairing = presentation
    controller.model.onInitialPairing = { controller.model.path = .usb }
    window.setContentSize(NSSize(width: 1010, height: 870))
    let frame = window.frame
    for path in [ConnectionPath.usb, .existing, .usb, .existing] {
      controller.model.selectPath(path)
      try await Task.sleep(nanoseconds: 100_000_000)
      XCTAssertTrue(window.contentView === root)
      XCTAssertEqual(window.frame, frame)
      XCTAssertEqual(controller.model.isInitialPairing, path == .usb)
      XCTAssertTrue(initial.window === window, "Native sheets must use the same window")
    }
    controller.model.selectPath(.usb)
    try await Task.sleep(nanoseconds: 200_000_000)
    if ProcessInfo.processInfo.environment["DEBAGR_CAPTURE_RESTORED"] == "1" {
      let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/design-restoration/screens")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        window.appearance = NSAppearance(named: appearance)
        for (sizeName, size) in [
          ("regular", NSSize(width: 980, height: 860)),
          ("minimum", NSSize(width: 880, height: 740)),
        ] {
          window.setContentSize(size)
          for path in [ConnectionPath.usb, .existing] {
            controller.model.selectPath(path)
            if path == .existing { controller.model.step = .review }
            try await Task.sleep(nanoseconds: 150_000_000)
            root.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
              to: folder.appendingPathComponent("\(path.rawValue)-\(name)-\(sizeName).png"))
          }
        }
      }
    }
  }

  func testInitialActionsFollowCoordinatorState() throws {
    _ = NSApplication.shared
    let suite = "UnifiedActions-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { try? FileManager.default.removeItem(at: folder) }
    let discovery = DebagrPeerDiscovery(
      defaults: defaults, identityURL: folder.appendingPathComponent("key"))
    defer { discovery.stop() }
    try MachineRoleStore(defaults: defaults).save(
      MachineRoleSelection(role: .client, peerID: "other", peerName: "Builder"),
      localNodeID: discovery.localNodeID)
    let initial = InitialPairingCoordinator(
      embedded: true, discovery: discovery,
      session: USBIPSessionController(defaults: defaults), connectedDevices: { [] })
    let window = try XCTUnwrap(initial.window)
    defer { window.close() }
    let presentation = initial.activate(in: window)
    var peer = DebagrPeer(protocolVersion: 1, nodeID: "other", name: "Builder", roles: ["app"])
    peer.machineRole = .builder
    peer.pairedNodeID = discovery.localNodeID
    discovery.onChange?(
      [DiscoveredDebagrPeer(peer: peer, address: "10.0.0.2", source: "Test")], "Found")
    let start = try XCTUnwrap(presentation.actions.first { $0.id == "start" })
    XCTAssertTrue(start.enabled)
    start.perform()
    XCTAssertTrue(presentation.status.contains("Plug in"))
    XCTAssertEqual(presentation.actions.filter(\.primary).count, 1)
  }
  @MainActor
  func testSharedFooterChecksTheRunningDeviceAndKeepsStopAvailable() async throws {
    _ = NSApplication.shared
    let suite = "UnifiedRunning-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let discovery = DebagrPeerDiscovery(
      defaults: defaults, identityURL: folder.appendingPathComponent("key"))
    defer { discovery.stop() }
    try MachineRoleStore(defaults: defaults).save(
      MachineRoleSelection(role: .builder, peerID: "other", peerName: "Client"),
      localNodeID: discovery.localNodeID)
    defaults.set(
      folder.appendingPathComponent("request.json").path, forKey: "usbip-session-request")
    try JSONEncoder().encode(
      USBIPSessionState(supervisorPID: 42, phase: "running", message: "Import running")
    )
    .write(to: folder.appendingPathComponent("state.json"))
    let session = USBIPSessionController(defaults: defaults, supervisorMatches: { _, _ in true })
    let device = TargetDevice(
      identity: .apple(pairedMacNodeID: "local", identifier: "test-phone"),
      displayName: "Example iPhone", kind: .iPhone, service: nil, status: .paired)
    let checked = LockedValue<[String]>([])
    let coordinator = InitialPairingCoordinator(
      embedded: true, discovery: discovery, session: session,
      deviceCheck: ConnectionDeviceCheck(
        inventory: { [device] },
        verify: { identifier in checked.withValue { $0.append(identifier) } }),
      connectedDevices: { [] })
    let window = try XCTUnwrap(coordinator.window)
    defer { window.close() }
    let presentation = coordinator.activate(in: window)
    let model = DeviceSetupModel(configured: nil)
    model.initialPairing = presentation
    model.path = .usb
    model.selectPath(.existing)
    XCTAssertEqual(model.path, .usb, "An active transport must block navigation")
    XCTAssertNotNil(model.error)
    XCTAssertNil(presentation.actions.first { $0.id == "start" })
    XCTAssertTrue(try XCTUnwrap(presentation.actions.first { $0.id == "stop" }).enabled)
    let check = try XCTUnwrap(presentation.actions.first { $0.id == "check" })
    XCTAssertTrue(check.enabled)
    check.perform()
    for _ in 0..<100 where checked.get().isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertEqual(checked.get(), ["test-phone"])
    XCTAssertEqual(presentation.step, .review)
    XCTAssertTrue(presentation.status.contains("Ready through CoreDevice"))
    XCTAssertTrue(try XCTUnwrap(presentation.actions.first { $0.id == "stop" }).enabled)
  }

}
