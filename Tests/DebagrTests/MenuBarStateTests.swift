import XCTest

@testable import Debagr

final class MenuBarStateTests: XCTestCase {
  func testMenuBarStateUsesHonestVisibilityLanguage() {
    let device = TargetDevice(
      identity: .apple(pairedMacNodeID: "mac", identifier: "phone"),
      displayName: "Test iPhone",
      kind: .iPhone,
      service: nil
    )

    XCTAssertEqual(MenuBarViewState.discovering.statusTitle, "Looking for Target Devices…")
    XCTAssertEqual(MenuBarViewState.empty.statusTitle, "No Target Devices found")
    XCTAssertEqual(MenuBarViewState.loaded([device]).statusTitle, "1 Target Device found")
    XCTAssertEqual(
      MenuBarViewState.loaded([device, device]).accessibilityLabel,
      "Debagr. 2 Target Devices found"
    )
    XCTAssertEqual(
      MenuBarViewState.failed("Local network access denied").accessibilityLabel,
      "Debagr. Device discovery unavailable. Local network access denied"
    )
  }

  func testDiagnosticsExcludeBonjourTXTValues() {
    let service = BonjourDevice(
      instanceName: "Test iPhone",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "iphone.local",
      port: 49_152,
      txt: ["pairing_tag": "secret"]
    )
    let device = TargetDevice(
      identity: .provisional(pairedMacNodeID: "mac", service: service),
      displayName: "Test iPhone",
      kind: .iPhone,
      service: service
    )

    let report = ProductSupport.diagnostics(devices: [device])

    XCTAssertTrue(report.contains("Test iPhone"))
    XCTAssertTrue(report.contains("iphone.local:49152"))
    XCTAssertFalse(report.contains("secret"))
    XCTAssertFalse(report.contains("pairing_tag"))
  }
}
