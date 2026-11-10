import AppKit
import XCTest

@testable import Debagr

final class ConnectionUXTests: XCTestCase {
  private var suite: String!
  private var defaults: UserDefaults!
  private var folder: URL!

  override func setUpWithError() throws {
    suite = "ConnectionUXTests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)!
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: folder)
  }

  @MainActor
  func testDiagramOffersAvailableMacsWithoutAnEditOrConfirmationStep() throws {
    _ = NSApplication.shared
    let discovery = DebagrPeerDiscovery(
      defaults: defaults, identityURL: folder.appendingPathComponent("key"))
    defer { discovery.stop() }
    let controller = InitialPairingCoordinator(
      discovery: discovery, session: USBIPSessionController(defaults: defaults))
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    window.setContentSize(NSSize(width: 720, height: 518))
    @MainActor
    func descendants(_ view: NSView) -> [NSView] {
      [view] + ((view as? NSStackView)?.views ?? view.subviews).flatMap { descendants($0) }
    }
    let content = try XCTUnwrap(window.contentView)
    let views = descendants(content)
    let fields = views.compactMap { $0 as? NSTextField }
    let buttons = views.compactMap { $0 as? NSButton }
    XCTAssertFalse(
      buttons.contains {
        ["Change Roles…", "Cancel Changes", "Update Roles", "Pair Macs"].contains($0.title)
      })
    XCTAssertTrue(views.compactMap { $0 as? NSSegmentedControl }.isEmpty)
    let builder = try XCTUnwrap(
      buttons.first { $0.accessibilityIdentifier() == "builderMacPicker" })
    let client = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier() == "clientMacPicker" })
    XCTAssertNotNil(builder.action)
    XCTAssertNotNil(client.action)
    XCTAssertTrue(builder.isEnabled)
    XCTAssertTrue(client.isEnabled)
    XCTAssertEqual(fields.filter { $0.stringValue == "Choose a Mac" }.count, 1)
    var remote = DebagrPeer(
      protocolVersion: 1, nodeID: "other", name: "MacBook Air", roles: ["app"])
    var unavailable = DebagrPeer(
      protocolVersion: 1, nodeID: "busy", name: "Shared Mac", roles: ["app"])
    unavailable.pairedNodeID = "someone-else"
    discovery.onChange?(
      [
        DiscoveredDebagrPeer(peer: remote, address: "10.0.0.2", source: "Test"),
        DiscoveredDebagrPeer(peer: unavailable, address: "10.0.0.3", source: "Test"),
      ], "Found")
    let menu = controller.machineMenu(for: .client)
    XCTAssertEqual(menu.items.filter { $0.action != nil }.count, 3)
    XCTAssertTrue(try XCTUnwrap(menu.items.first { $0.title == "MacBook Air" }).isEnabled)
    XCTAssertFalse(try XCTUnwrap(menu.items.first { $0.title.contains("Shared Mac") }).isEnabled)
    XCTAssertNil(
      try discovery.localSelection, "Discovery must not pair automatically before a choice")
    try MachineRoleStore(defaults: defaults).save(
      MachineRoleSelection(role: .builder, peerID: "other", peerName: "MacBook Air"),
      localNodeID: discovery.localNodeID)
    remote.machineRole = .client
    remote.pairedNodeID = discovery.localNodeID
    discovery.onChange?(
      [DiscoveredDebagrPeer(peer: remote, address: "10.0.0.2", source: "Test")], "Confirmed")
    content.layoutSubtreeIfNeeded()
    let stage = try XCTUnwrap(views.first { $0.accessibilityIdentifier() == "pairStage" })
    let frames = [builder, client].map { $0.convert($0.bounds, to: stage) }
    XCTAssertEqual(frames[0].maxY, frames[1].maxY, accuracy: 1)
    XCTAssertLessThan(frames[0].maxX, frames[1].minX)
    for frame in frames { XCTAssertTrue(stage.bounds.contains(frame)) }
    let start = try XCTUnwrap(
      buttons.first { ["Set Up USB Support…", "Start Setup Connection"].contains($0.title) })
    XCTAssertTrue(start.isEnabled)
    XCTAssertEqual(start.keyEquivalent, "\r")
    XCTAssertTrue(content.bounds.contains(start.convert(start.bounds, to: content)))
    XCTAssertEqual(
      controller.machineMenu(for: .client).items.first { $0.title == "MacBook Air" }?.state, .on)
  }

  @MainActor
  func testChosenBackendsPersistPerRoleAndAreRevalidated() throws {
    let path = folder.appendingPathComponent("custom USB support")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: path)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    let controller = USBIPSessionController(defaults: defaults)
    try controller.rememberBackend(path.path, for: .builder)
    let reopened = USBIPSessionController(defaults: defaults)
    XCTAssertEqual(reopened.backendPath(for: .builder), path.path)
    XCTAssertNotEqual(reopened.backendPath(for: .client), path.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    XCTAssertNil(reopened.backendPath(for: .builder))
    XCTAssertTrue(reopened.hasMissingSavedBackend(for: .builder))
    XCTAssertThrowsError(try reopened.rememberBackend(folder.path, for: .client))
    XCTAssertThrowsError(try reopened.rememberBackend("relative/tool", for: .client))
  }

  @MainActor
  func testSetupHandoffRequiresAnIdleBuilderAndKeepsBackendsSeparate() throws {
    _ = NSApplication.shared
    let discovery = DebagrPeerDiscovery(
      defaults: defaults, identityURL: folder.appendingPathComponent("key"))
    defer { discovery.stop() }
    let request = folder.appendingPathComponent("request.json")
    defaults.set(request.path, forKey: "usbip-session-request")
    let stateURL = folder.appendingPathComponent("state.json")
    let session = USBIPSessionController(defaults: defaults, supervisorMatches: { _, _ in true })
    let controller = InitialPairingCoordinator(
      discovery: discovery, session: session, connectedDevices: { [] })
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    var wireless = 0
    var alternative = 0
    controller.onWirelessSetup = { wireless += 1 }
    controller.onVirtualHereSetup = { alternative += 1 }
    @MainActor
    func descendants(_ view: NSView) -> [NSView] {
      [view] + ((view as? NSStackView)?.views ?? view.subviews).flatMap { descendants($0) }
    }
    let buttons = descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? NSButton }
    let handoff = try XCTUnwrap(buttons.first { $0.title == "Set up wireless deployment…" })
    let other = try XCTUnwrap(buttons.first { $0.title == "Use VirtualHere instead…" })
    for role in [DebagrMachineRole.builder, .client] {
      try MachineRoleStore(defaults: defaults).save(
        MachineRoleSelection(role: role, peerID: "other", peerName: "Other Mac"),
        localNodeID: discovery.localNodeID)
      discovery.onChange?([], "Offline")
      XCTAssertEqual(handoff.isEnabled, role == .builder)
      XCTAssertEqual(other.isEnabled, role == .builder)
      handoff.performClick(nil)
      other.performClick(nil)
    }
    XCTAssertEqual(wireless, 1)
    XCTAssertEqual(alternative, 1)
    try MachineRoleStore(defaults: defaults).save(
      MachineRoleSelection(role: .builder, peerID: "other", peerName: "Other Mac"),
      localNodeID: discovery.localNodeID)
    try JSONEncoder().encode(
      USBIPSessionState(supervisorPID: 42, phase: "running", message: "Import running")
    ).write(to: stateURL)
    discovery.onChange?([], "Offline")
    XCTAssertFalse(controller.canOpenOtherSetup)
    XCTAssertFalse(handoff.isEnabled)
    XCTAssertFalse(other.isEnabled)
    try FileManager.default.removeItem(at: stateURL)
    discovery.onChange?([], "Offline")
    XCTAssertTrue(controller.canOpenOtherSetup)
    XCTAssertTrue(handoff.isEnabled)
    handoff.performClick(nil)
    XCTAssertEqual(wireless, 2)
  }

  @MainActor
  func testOldInactiveSessionFeedbackDoesNotReturnAfterResetOrPairChange() throws {
    let request = folder.appendingPathComponent("request.json")
    defaults.set(request.path, forKey: "usbip-session-request")
    defaults.set("builder:old-peer", forKey: "usbip-session-context")
    try JSONEncoder().encode(
      USBIPSessionState(supervisorPID: 42, phase: "failed", message: "Old failure")
    )
    .write(to: folder.appendingPathComponent("state.json"))
    let session = USBIPSessionController(defaults: defaults)
    var messages: [String] = []
    session.onChange = { message, _ in messages.append(message) }
    session.setFeedbackContext("builder:old-peer")
    session.poll()
    XCTAssertEqual(messages.count, 1)
    session.resetFeedback()
    session.poll()
    XCTAssertEqual(messages.count, 1)
    let reopened = USBIPSessionController(defaults: defaults)
    reopened.onChange = { message, _ in messages.append(message) }
    reopened.setFeedbackContext("builder:new-peer")
    reopened.poll()
    reopened.setFeedbackContext(nil)
    reopened.poll()
    XCTAssertEqual(messages.count, 1)
  }

  @MainActor
  func testReadinessRequiresTheSelectedDeviceToPassVerification() throws {
    let phone = TargetDevice(
      identity: .apple(pairedMacNodeID: "local", identifier: "phone-123456"),
      displayName: "My iPhone", kind: .iPhone, service: nil, status: .paired)
    let checked = LockedValue<[String]>([])
    let checker = ConnectionDeviceCheck(
      inventory: { [phone] }, verify: { identifier in checked.withValue { $0.append(identifier) } })
    XCTAssertEqual(try checker.devices(), [phone])
    XCTAssertTrue(checked.get().isEmpty)
    XCTAssertTrue(try checker.check(phone).contains("Ready through CoreDevice: My iPhone"))
    XCTAssertEqual(checked.get(), ["phone-123456"])
    let locked = ConnectionDeviceCheck(
      inventory: { [phone] }, verify: { _ in throw DeviceDeploymentError.deviceLocked })
    XCTAssertThrowsError(try locked.check(phone))
    XCTAssertTrue(
      ConnectionDeviceCheck.recovery(for: DeviceDeploymentError.deviceLocked).contains("Unlock"))
    XCTAssertTrue(
      ConnectionDeviceCheck.recovery(for: DeviceDeploymentError.invalidResult).contains(
        "could not confirm"))
    XCTAssertTrue(
      ConnectionDeviceCheck.recovery(for: DeviceDeploymentError.timedOut).contains("timed out"))
  }

  @MainActor
  func testRunningBuilderOffersReadOnlyCheckAndPreservesItsResult() throws {
    _ = NSApplication.shared
    let discovery = DebagrPeerDiscovery(
      defaults: defaults, identityURL: folder.appendingPathComponent("key"))
    defer { discovery.stop() }
    try MachineRoleStore(defaults: defaults).save(
      MachineRoleSelection(role: .builder, peerID: "other", peerName: "Air"),
      localNodeID: discovery.localNodeID)
    let request = folder.appendingPathComponent("request.json")
    defaults.set(request.path, forKey: "usbip-session-request")
    try JSONEncoder().encode(
      USBIPSessionState(supervisorPID: 42, phase: "running", message: "USB import running")
    )
    .write(to: folder.appendingPathComponent("state.json"))
    let session = USBIPSessionController(defaults: defaults, supervisorMatches: { _, _ in true })
    let phone = TargetDevice(
      identity: .apple(pairedMacNodeID: "local", identifier: "phone-123456"),
      displayName: "My iPhone", kind: .iPhone, service: nil, status: .paired)
    let verifiedIDs = LockedValue<[String]>([])
    let checker = ConnectionDeviceCheck(
      inventory: { [phone] },
      verify: { identifier in verifiedIDs.withValue { $0.append(identifier) } })
    let controller = InitialPairingCoordinator(
      discovery: discovery, session: session, deviceCheck: checker)
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    @MainActor
    func descendants(_ view: NSView) -> [NSView] {
      [view] + ((view as? NSStackView)?.views ?? view.subviews).flatMap { descendants($0) }
    }
    let views = descendants(try XCTUnwrap(window.contentView))
    let check = try XCTUnwrap(
      views.compactMap { $0 as? NSButton }.first { $0.title == "Check Device" })
    XCTAssertTrue(
      views.compactMap { $0 as? NSButton }.filter {
        ["builderMacPicker", "clientMacPicker"].contains($0.accessibilityIdentifier())
      }.allSatisfy { !$0.isEnabled })
    XCTAssertEqual(check.keyEquivalent, "\r")
    XCTAssertFalse(check.isHidden)
    XCTAssertTrue(check.isEnabled)
    check.performClick(nil)
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        views.compactMap { $0 as? NSTextField }.contains {
          $0.stringValue.contains("Ready through CoreDevice: My iPhone")
        }
      }, object: nil)
    wait(for: [ready], timeout: 3)
    XCTAssertEqual(verifiedIDs.get(), ["phone-123456"])
    XCTAssertTrue(
      views.compactMap { $0 as? NSTextField }.contains {
        $0.stringValue == "Device ready"
      })
    session.poll()
    XCTAssertTrue(
      views.compactMap { $0 as? NSTextField }.contains {
        $0.stringValue.contains("Ready through CoreDevice: My iPhone")
      })
    try JSONEncoder().encode(
      USBIPSessionState(supervisorPID: 42, phase: "stopped", message: "Connection process stopped.")
    )
    .write(to: folder.appendingPathComponent("state.json"))
    session.poll()
    XCTAssertTrue(check.isHidden)
    XCTAssertTrue(
      views.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Not connected" })
    XCTAssertFalse(
      views.compactMap { $0 as? NSTextField }.contains {
        $0.stringValue.contains("Ready through CoreDevice: My iPhone")
      })
  }

  @MainActor
  func testRunningClientNamesTheBuilderAsTheNextStep() throws {
    _ = NSApplication.shared
    let discovery = DebagrPeerDiscovery(
      defaults: defaults, identityURL: folder.appendingPathComponent("key"))
    defer { discovery.stop() }
    try MachineRoleStore(defaults: defaults).save(
      MachineRoleSelection(role: .client, peerID: "other", peerName: "Build Mac"),
      localNodeID: discovery.localNodeID)
    defaults.set(
      folder.appendingPathComponent("request.json").path, forKey: "usbip-session-request")
    try JSONEncoder().encode(
      USBIPSessionState(supervisorPID: 42, phase: "running", message: "Export process")
    )
    .write(to: folder.appendingPathComponent("state.json"))
    let session = USBIPSessionController(defaults: defaults, supervisorMatches: { _, _ in true })
    let controller = InitialPairingCoordinator(discovery: discovery, session: session)
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    session.poll()
    @MainActor
    func descendants(_ view: NSView) -> [NSView] {
      [view] + ((view as? NSStackView)?.views ?? view.subviews).flatMap { descendants($0) }
    }
    XCTAssertTrue(
      descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? NSTextField }.contains {
        $0.stringValue.contains(
          "Temporary USB sharing is running. Start Setup Connection on Build Mac next.")
      })
    XCTAssertTrue(
      descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? NSTextField }.contains {
        $0.stringValue == "Temporary USB sharing running"
      })
  }

  @MainActor
  func testSignedPreflightUsesTheBackendTargetAndCancellationPreventsStarting() throws {
    _ = NSApplication.shared
    let discovery = DebagrPeerDiscovery(
      defaults: defaults, identityURL: folder.appendingPathComponent("key"))
    defer { discovery.stop() }
    try MachineRoleStore(defaults: defaults).save(
      MachineRoleSelection(role: .builder, peerID: "other", peerName: "Air"),
      localNodeID: discovery.localNodeID)
    let session = USBIPSessionController(defaults: defaults)
    var checkedPeer: DiscoveredDebagrPeer?
    var reply: ((Result<Void, Error>) -> Void)?
    let controller = InitialPairingCoordinator(
      discovery: discovery, session: session,
      peerVerifier: { peer, completion in
        checkedPeer = peer
        reply = completion
      })
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    var peer = DebagrPeer(protocolVersion: 1, nodeID: "other", name: "Air", roles: ["app"])
    peer.machineRole = .client
    peer.pairedNodeID = discovery.localNodeID
    discovery.onChange?(
      [DiscoveredDebagrPeer(peer: peer, address: "10.0.0.2:49388", source: "Test")], "Found")
    @MainActor
    func descendants(_ view: NSView) -> [NSView] {
      [view] + ((view as? NSStackView)?.views ?? view.subviews).flatMap { descendants($0) }
    }
    let views = descendants(try XCTUnwrap(window.contentView))
    let start = try XCTUnwrap(
      views.compactMap { $0 as? NSButton }.first {
        ["Start Setup Connection", "Set Up USB Support…"].contains($0.title)
      })
    start.performClick(nil)
    XCTAssertEqual(checkedPeer?.address, "10.0.0.2")
    XCTAssertFalse(start.isEnabled)
    let cancel = try XCTUnwrap(
      views.compactMap { $0 as? NSButton }.first { $0.title == "Cancel Check" })
    XCTAssertTrue(cancel.isEnabled)
    cancel.performClick(nil)
    try XCTUnwrap(reply)(.success(()))
    XCTAssertNil(defaults.string(forKey: "usbip-session-request"))
    XCTAssertTrue(start.isEnabled)
    XCTAssertTrue(
      views.compactMap { $0 as? NSTextField }.contains {
        $0.stringValue.contains("Mac check cancelled")
      })
  }
}
