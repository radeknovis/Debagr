import AppKit
import XCTest

@testable import Debagr

final class MenuPresentationTests: XCTestCase {
  func testStatusIconsAreDistinctTemplateArtwork() throws {
    var artwork = Set<Data>()
    for state in MenuBarIconState.allCases {
      let image = state.image
      XCTAssertTrue(image.isTemplate)
      XCTAssertEqual(image.size, NSSize(width: 22, height: 18))
      artwork.insert(try XCTUnwrap(image.tiffRepresentation))
    }
    XCTAssertEqual(artwork.count, MenuBarIconState.allCases.count)
    if ProcessInfo.processInfo.environment["DEBAGR_CAPTURE_MENU"] == "1" {
      let sheet = NSImage(size: NSSize(width: 360, height: 60))
      sheet.lockFocus()
      NSColor.white.setFill()
      NSRect(x: 0, y: 0, width: 360, height: 60).fill()
      for (index, state) in MenuBarIconState.allCases.enumerated() {
        state.image.draw(in: NSRect(x: index * 60 + 19, y: 25, width: 22, height: 18))
        "\(state)".draw(
          at: NSPoint(x: index * 60 + 8, y: 5),
          withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black])
      }
      sheet.unlockFocus()
      let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(sheet.tiffRepresentation)))
      try bitmap.representation(using: .png, properties: [:])?.write(
        to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
          .appendingPathComponent(".build/menu-icons.png"))
    }
  }

  private var configured: ConfiguredDevice {
    ConfiguredDevice(
      deviceIdentifier: "fixture-phone", displayName: "Example iPhone",
      peerName: "phone",
      profile: DeviceProfile(
        bonjourName: "fixture", bonjourTXT: ["identity": "private-payload"],
        provider: "wireguard", peerIP: "10.20.0.2", remotePort: 49152,
        localPortRange: [55000, 58000]))
  }

  func testSetupAndUSBActivityCannotClaimReadiness() {
    let setup = MenuConnectionPresentation(
      configured: nil, selection: nil, usbActive: false,
      readiness: .ready, receipt: nil)
    XCTAssertEqual(setup.status, "No device configured")
    XCTAssertEqual(setup.actionTitle, "Open Debagr")
    XCTAssertEqual(setup.tone, .neutral)
    XCTAssertEqual(setup.iconState, .idle)
    let importing = MenuConnectionPresentation(
      configured: configured, selection: nil, usbActive: true,
      readiness: .ready, receipt: nil)
    XCTAssertEqual(importing.status, "Temporary USB import")
    XCTAssertEqual(importing.tone, .neutral)
    XCTAssertEqual(importing.iconState, .usb)
    let client = MachineRoleSelection(role: .client, peerID: "builder", peerName: "Build Mac")
    let sharing = MenuConnectionPresentation(
      configured: configured, selection: client, usbActive: true,
      readiness: .ready, receipt: nil)
    XCTAssertEqual(sharing.status, "Temporary USB sharing")
    XCTAssertEqual(sharing.tone, .neutral)
  }

  func testReadyStatusAndReceiptRemainSeparate() {
    let installed = DeploymentReceipt(
      deviceIdentifier: "fixture-phone", bundleIdentifier: "example.app",
      launched: false, completedAt: Date())
    let ready = MenuConnectionPresentation(
      configured: configured, selection: nil, usbActive: false,
      readiness: .ready, receipt: installed)
    XCTAssertEqual(ready.status, "Ready for deployment")
    XCTAssertEqual(ready.tone, .good)
    XCTAssertEqual(ready.iconState, .ready)
    XCTAssertTrue(ready.history.contains("Installed"))
    XCTAssertFalse(ready.history.contains("launched"))
    let other = DeploymentReceipt(
      deviceIdentifier: "other-phone", bundleIdentifier: "other.app",
      launched: true, completedAt: Date())
    let unrelated = MenuConnectionPresentation(
      configured: configured, selection: nil, usbActive: false,
      readiness: .checking, receipt: other)
    XCTAssertEqual(unrelated.history, "No deployment recorded for this device")
  }

  func testPausedAttentionAndClientStatesHaveUsefulNextSteps() {
    var paused = configured
    paused.enabled = false
    let summary = MenuConnectionPresentation(
      configured: paused, selection: nil, usbActive: false,
      readiness: .ready, receipt: nil)
    XCTAssertEqual(summary.status, "Connection paused")
    XCTAssertNotEqual(summary.tone, .good)
    let recovery = MenuConnectionPresentation(
      configured: configured, selection: nil, usbActive: false,
      readiness: .attention("Unlock the phone, then try again."), receipt: nil)
    XCTAssertEqual(recovery.detail, "Unlock the phone, then try again.")
    XCTAssertEqual(recovery.tone, .attention)
    let client = MenuConnectionPresentation(
      configured: configured,
      selection: MachineRoleSelection(role: .client, peerID: "builder", peerName: "Other Mac"),
      usbActive: false, readiness: .ready, receipt: nil)
    XCTAssertEqual(client.status, "Client Mac")
    XCTAssertNotEqual(client.tone, .good)
    XCTAssertTrue(client.detail.contains("Other Mac"))
  }

  func testNativeMenuKeepsFrequentActionsAtTheTopAndToolsInSubmenus() throws {
    _ = NSApplication.shared
    let application = MenuBarApplication()
    let menu = application.makeMenu()
    XCTAssertTrue(menu.items.first?.view is MenuConnectionSummaryView)
    XCTAssertFalse(menu.autoenablesItems)
    XCTAssertEqual(
      menu.items.first { $0.title == "Open Debagr" }?.action, NSSelectorFromString("openDebagr"))
    let prompt = try XCTUnwrap(menu.items.first { $0.title == "Copy Deployment Prompt" })
    XCTAssertNotNil(prompt.target)
    XCTAssertNotNil(prompt.action)
    XCTAssertFalse(prompt.isEnabled)
    XCTAssertFalse(menu.items.contains { $0.title == "Wireless Deployment" })
    let devices = try XCTUnwrap(menu.items.first { $0.title == "Devices" }?.submenu)
    XCTAssertEqual(devices.items.first { $0.title == "Refresh Target Devices" }?.keyEquivalent, "r")
    XCTAssertNotNil(menu.items.first { $0.title == "Agent Tools…" }?.action)
    XCTAssertNotNil(menu.items.first { $0.title == "Help & Diagnostics" }?.submenu)
    let launch = try XCTUnwrap(menu.items.first { $0.title == "Launch at Login" })
    XCTAssertEqual(launch.action, NSSelectorFromString("toggleLaunchAtLogin"))
    XCTAssertTrue(launch.target === application)
    XCTAssertEqual(menu.items.last?.keyEquivalent, "q")
  }

  @MainActor
  func testSummaryHasABoundedAccessibleNativeLayout() async throws {
    _ = NSApplication.shared
    let view = MenuConnectionSummaryView()
    view.update(
      MenuConnectionPresentation(
        configured: configured, selection: nil, usbActive: false,
        readiness: .attention(
          "Unlock your iPhone and keep Wi-Fi and your VPN connected, then open Connections to retry."
        ), receipt: nil))
    XCTAssertEqual(view.frame.height, 164)
    XCTAssertFalse(view.accessibilityLabel()?.contains("private-payload") == true)
    let window = NSWindow(
      contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    defer { window.close() }
    window.orderFront(nil)
    try await Task.sleep(nanoseconds: 100_000_000)
    view.layoutSubtreeIfNeeded()
    let stack = try XCTUnwrap(view.subviews.first as? NSStackView)
    for child in stack.arrangedSubviews {
      XCTAssertTrue(view.bounds.contains(child.convert(child.bounds, to: view)))
    }
    if ProcessInfo.processInfo.environment["DEBAGR_CAPTURE_MENU"] == "1" {
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
        to:
          URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
            ".build/menu-summary.png"))
    }
  }
}
