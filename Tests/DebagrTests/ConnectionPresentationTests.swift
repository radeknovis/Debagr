import XCTest

@testable import Debagr

@MainActor
final class ConnectionPresentationTests: XCTestCase {
  func testBackendLogsStayInDiagnosticsRatherThanThePrimaryStatus() throws {
    let name = "ConnectionPresentationTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let request = folder.appendingPathComponent("request.json")
    defaults.set(request.path, forKey: "usbip-session-request")
    try JSONEncoder().encode(
      USBIPSessionState(supervisorPID: 0, phase: "failed", message: "Exit status 13")
    )
    .write(to: folder.appendingPathComponent("state.json"))
    try Data("TECHNICAL_BACKEND_LOG".utf8).write(to: folder.appendingPathComponent("output.log"))
    let session = USBIPSessionController(defaults: defaults)
    var message = ""
    session.onChange = { text, active in
      message = text
      XCTAssertFalse(active)
    }
    session.poll()
    XCTAssertTrue(message.contains("Diagnostics"))
    XCTAssertFalse(message.contains("TECHNICAL_BACKEND_LOG"))
    XCTAssertTrue(session.diagnostics.contains("TECHNICAL_BACKEND_LOG"))
  }
  func testDiagramAccessibilityDescribesTheSelectedUSBRoute() {
    let usbip = ConnectionDiagram(path: .usb, usbLinkLabel: "USB over VPN")
    XCTAssertTrue(usbip.topologyDescription.contains("USB over VPN"))
    XCTAssertFalse(usbip.topologyDescription.contains("VirtualHere"))
    let alternative = ConnectionDiagram(path: .usb)
    XCTAssertTrue(alternative.topologyDescription.contains("USB over SSH"))
    XCTAssertTrue(
      ConnectionDiagram(path: .existing).topologyDescription.contains("No Client Mac is required"))
  }

  func testFirstRunWithoutASavedDeviceOpensTheExistingPairingForm() {
    XCTAssertEqual(ConnectionPath.start(role: nil, open: nil), .existing)
    XCTAssertEqual(ConnectionPath.start(role: .builder, open: nil), .existing)
    XCTAssertEqual(ConnectionPath.start(role: nil, open: .existing), .existing)
    XCTAssertEqual(
      ConnectionPath.start(role: .client, open: nil), .usb,
      "A Client Mac keeps opening the USB screen")
    XCTAssertEqual(
      ConnectionPath.start(role: nil, open: .usb), .usb, "An open USB screen is not replaced")
    let model = DeviceSetupModel(configured: nil)
    XCTAssertEqual(model.path, .existing)
    XCTAssertFalse(model.isInitialPairing)
  }

  func testUSBPathIsLabelledExperimentalAndStatesItsRequirements() {
    XCTAssertEqual(ConnectionPath.experimentalLabel, "Experimental")
    XCTAssertTrue(ConnectionPath.usb.accessibilityLabel.contains("Experimental"))
    XCTAssertFalse(ConnectionPath.existing.accessibilityLabel.contains("Experimental"))
    for requirement in [
      "two Macs running Debagr", "separately installed USB tool", "Longcable", "usbip-macos",
      "VirtualHere", "administrator password",
      "System Integrity Protection turned off on the Builder",
    ] {
      XCTAssertTrue(ConnectionPath.usbRequirements.contains(requirement), requirement)
    }
  }

}
