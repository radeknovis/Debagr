import XCTest

@testable import Debagr

final class CommandLineTests: XCTestCase {
  func testAgentCommandsAreExplicitAndCannotStartCompetingRelays() throws {
    let status = try CommandLineOptions.parse([
      "--status", "--device", "udid", "--timeout", "30", "--json",
    ])
    XCTAssertEqual(status.agentCommand, "status")
    XCTAssertTrue(status.json)
    XCTAssertEqual(status.interfaceName, "auto")
    XCTAssertEqual(try CommandLineOptions.parse(["--devices", "--json"]).agentCommand, "devices")
    for arguments in [
      ["--status", "--json"], ["--json"], ["--devices", "--status", "--device", "udid"],
      ["--devices", "--deploy-app", "/tmp/Test.app", "--device", "udid"],
      ["--deploy-app", "/tmp/Test.app", "--device", "udid", "--menu-bar"],
      ["--status", "--device", "udid", "--direct-device", "--peer", "phone"],
    ] { XCTAssertThrowsError(try CommandLineOptions.parse(arguments)) }
  }

  func testDirectDeviceModesRejectConflictingOperations() throws {
    let capture = try CommandLineOptions.parse([
      "--capture-device-profile", "--peer", "iphone", "--bonjour-host", "phone.local",
    ])
    XCTAssertTrue(capture.captureDeviceProfile)
    XCTAssertFalse(capture.directDevice)
    let direct = try CommandLineOptions.parse(["--direct-device", "--peer", "iphone"])
    XCTAssertTrue(direct.directDevice)
    for arguments in [
      ["--capture-device-profile", "--peer", "iphone"],
      ["--direct-device"],
      ["--direct-device", "--peer", "iphone", "--forward-remote"],
      ["--direct-device", "--peer", "iphone", "--discover"],
      ["--direct-device", "--peer", "iphone", "--remote-port", "49152"],
      [
        "--direct-device", "--peer", "iphone", "--capture-device-profile", "--bonjour-host",
        "phone.local",
      ],
    ] {
      XCTAssertThrowsError(try CommandLineOptions.parse(arguments))
    }
  }

  func testDeployOptionsRequireAnAppAndExplicitDevice() throws {
    let options = try CommandLineOptions.parse([
      "--deploy-app", "/tmp/Test.app",
      "--device", "device-udid",
      "--launch",
    ])

    XCTAssertEqual(options.deployAppURL?.path, "/tmp/Test.app")
    XCTAssertEqual(options.deviceIdentifier, "device-udid")
    XCTAssertTrue(options.launchAfterInstall)
    XCTAssertThrowsError(try CommandLineOptions.parse(["--launch"]))
    XCTAssertThrowsError(try CommandLineOptions.parse(["--deploy-app", "/tmp/Test.app"]))
  }

  func testMenuBarOptionDoesNotRequirePeerOrPortConfiguration() throws {
    let options = try CommandLineOptions.parse(["--menu-bar"])

    XCTAssertTrue(options.menuBar)
    XCTAssertNil(options.peerName)
    XCTAssertNil(options.remotePort)
    XCTAssertFalse(options.forwardRemote)
  }
}
