import XCTest

@testable import Debagr

@MainActor
final class ConnectionPresentationTests: XCTestCase {
  func testCableTabUsesExistingTrustAndCannotSaveWirelessConfiguration() {
    let model = DeviceSetupModel(configured: nil)
    model.selectPath(.usb)
    XCTAssertEqual(model.path, .usb)
    XCTAssertFalse(model.canContinue)
    XCTAssertFalse(model.canSave)
    model.advance()
    XCTAssertEqual(model.page, .setup)
    model.selectPath(.existing)
    XCTAssertEqual(model.path, .existing)
  }

  func testCableDiagramDescribesServiceForwardingAndExistingTrust() {
    let diagram = ConnectionDiagram(path: .usb)
    XCTAssertTrue(diagram.topologyDescription.contains("already paired Builder"))
    XCTAssertTrue(diagram.topologyDescription.contains("Keep the USB cable connected"))
    XCTAssertEqual(ConnectionPath.usb.title, "USB via Mac")
    XCTAssertTrue(ConnectionPath.usbRequirements.contains("existing Xcode pairing"))
    XCTAssertTrue(ConnectionPath.usbRequirements.contains("trusted SSH"))
    XCTAssertTrue(ConnectionPath.usb.accessibilityLabel.contains("Experimental"))
  }

  func testFirstRunAndReopenDoNotUseSavedLegacyRoles() {
    XCTAssertEqual(DeviceSetupModel(configured: nil).path, .existing)
  }

  func testRemovedUSBCommandsAreRejected() {
    for arguments in [
      ["--usbip", "help"], ["--usb-services", "--json"],
      ["--usb-profile", "--peer", "phone", "--bonjour-host", "phone.local", "--json"],
    ] {
      XCTAssertThrowsError(try CommandLineOptions.parse(arguments))
    }
  }
}
