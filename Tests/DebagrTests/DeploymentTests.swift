import XCTest

@testable import Debagr

final class DeploymentTests: XCTestCase {
  func testReadinessRequiresAnExplicitUnlockedAppleResult() throws {
    let ready = Data(#"{"result":{"passcodeRequired":false,"unlockedSinceBoot":true}}"#.utf8)
    var commands: [[String]] = []
    let deployer = DeviceDeployer(run: { args, _ in
      commands.append(args)
      return ready
    })
    try deployer.checkReady(deviceIdentifier: "udid")
    XCTAssertTrue(commands[0].contains("lockState"))
    XCTAssertTrue(commands[0].contains("udid"))
    for data in [
      Data(#"{"result":{}}"#.utf8),
      Data(#"{"result":{"passcodeRequired":true,"unlockedSinceBoot":true}}"#.utf8),
    ] {
      XCTAssertThrowsError(
        try DeviceDeployer(run: { _, _ in data }).checkReady(deviceIdentifier: "udid"))
    }
  }

  func testDeploymentFlowConfirmsInstallAndReportsPartialLaunchFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AgentTest-\(UUID().uuidString).app")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    try PropertyListSerialization.data(
      fromPropertyList: [
        "CFBundleIdentifier": "com.example.agent", "CFBundleSupportedPlatforms": ["iPhoneOS"],
      ],
      format: .xml, options: 0
    ).write(to: directory.appendingPathComponent("Info.plist"))
    var calls: [[String]] = []
    let run: ([String], TimeInterval) throws -> Data = { arguments, _ in
      calls.append(arguments)
      if arguments.contains("lockState") {
        return Data(#"{"result":{"passcodeRequired":false,"unlockedSinceBoot":true}}"#.utf8)
      }
      if arguments.contains("install") {
        return Data(#"{"result":{"installedApplication":{"bundleID":"com.example.agent"}}}"#.utf8)
      }
      throw DeviceDeploymentError.commandFailed(arguments: arguments, status: 1)
    }
    do {
      _ = try DeviceDeployer(run: run).deploy(
        appURL: directory, deviceIdentifier: "udid", launch: true)
      XCTFail("Launch failure must not report success")
    } catch {
      let failure = AgentCLI.failure(error, operation: "deploy")
      XCTAssertEqual(failure.exitCode, 1)
      let detail = try XCTUnwrap(failure.object["error"] as? [String: Any])
      XCTAssertEqual(detail["code"] as? String, "launch_failed")
      XCTAssertEqual(detail["installed"] as? Bool, true)
      XCTAssertEqual(detail["bundleIdentifier"] as? String, "com.example.agent")
    }
    XCTAssertEqual(calls.count, 3)
    calls.removeAll()
    let result = try DeviceDeployer(run: run).deploy(
      appURL: directory, deviceIdentifier: "udid", launch: false)
    XCTAssertFalse(result.launched)
    XCTAssertEqual(calls.count, 2)
    let wrongResult = DeviceDeployer(run: { args, _ in
      if args.contains("lockState") {
        return Data(#"{"result":{"passcodeRequired":false,"unlockedSinceBoot":true}}"#.utf8)
      }
      return Data(#"{"info":{"bundleID":"com.example.agent"},"result":{}}"#.utf8)
    })
    XCTAssertThrowsError(
      try wrongResult.deploy(appURL: directory, deviceIdentifier: "udid", launch: false))
  }

  func testAgentWaitIsBoundedAndStructuredErrorsAreActionable() throws {
    var count = 0
    XCTAssertThrowsError(
      try AgentCLI.waitUntilReady(
        deviceIdentifier: "udid", timeout: 0.01, now: { 0 },
        sleep: { _ in XCTFail("No sleep expected") },
        check: { _, _ in
          count += 1
          throw DeviceDeploymentError.deviceLocked
        }))
    XCTAssertEqual(count, 1)
    let result = AgentCLI.failure(DeviceDeploymentError.deviceLocked, operation: "status")
    XCTAssertEqual(result.exitCode, 2)
    XCTAssertEqual((result.object["error"] as? [String: Any])?["code"] as? String, "device_locked")
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: result.object))
  }

  func testDeviceDeploymentReadsBundleIdentifierAndConfirmsResult() throws {
    let appURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("DebagrTests-\(UUID().uuidString).app")
    try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: appURL) }

    let plist = try PropertyListSerialization.data(
      fromPropertyList: [
        "CFBundleIdentifier": "com.example.test", "CFBundleSupportedPlatforms": ["iPhoneOS"],
      ],
      format: .xml,
      options: 0
    )
    try plist.write(to: appURL.appendingPathComponent("Info.plist"))

    XCTAssertEqual(try DeviceDeployer.bundleIdentifier(at: appURL), "com.example.test")
    XCTAssertTrue(
      DeviceDeployer.contains(
        "com.example.test",
        in: ["result": ["installedApplication": ["bundleID": "com.example.test"]]]
      ))
    XCTAssertFalse(
      DeviceDeployer.contains("com.example.other", in: ["result": ["bundleID": "com.example.test"]])
    )
  }
}
