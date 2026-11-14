import XCTest

@testable import Debagr

final class CLIRecoveryTests: XCTestCase {
  func testTypedAppleUserInfoDescriptionIsPreserved() throws {
    let data = Data(
      #"{"error":{"code":4016,"domain":"com.apple.dt.CoreDeviceError","userInfo":{"NSLocalizedDescription":{"string":"The device is not able to fulfill the requested usage assertion requirements."}}}}"#
        .utf8)
    let error = try XCTUnwrap(DeviceDeployer.appleError(from: data))
    XCTAssertEqual(
      error.localizedDescription,
      "The device is not able to fulfill the requested usage assertion requirements.")
    let failure = AgentCLI.failure(error, operation: "status")
    XCTAssertEqual((failure.object["error"] as? [String: Any])?["underlyingCode"] as? Int, 4016)
  }

  func testVersionJSONProducesStructuredOutput() throws {
    let options = try CommandLineOptions.parse(["--version", "--json"])
    XCTAssertTrue(options.showVersion)
    XCTAssertTrue(options.json)
    // Verify the JSON structure that --version --json produces is valid and parseable
    let versionObject: [String: Any] = [
      "schemaVersion": 1,
      "version": ProductSupport.version,
      "bundleShortVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
      "buildNumber": Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
    ]
    let data = try JSONSerialization.data(withJSONObject: versionObject, options: [])
    let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(parsed["schemaVersion"] as? Int, 1)
    XCTAssertNotNil(parsed["version"])
  }

  func testHelpJSONProducesStructuredOutput() throws {
    let options = try CommandLineOptions.parse(["--help", "--json"])
    XCTAssertTrue(options.showHelp)
    XCTAssertTrue(options.json)
  }

  func testCommandsRejectOptionsTheyCannotUse() throws {
    for args in [
      ["--devices", "--timeout", "5"], ["--menu-bar", "--peer", "phone"],
      ["--status", "--device", "id", "--interface", "en0"],
      ["--deploy-app", "/tmp/App.app", "--device", "id", "--profile", "/tmp/profile"],
      ["--discover", "--profile", "/tmp/profile"],
      ["--installed-apps"], ["--launch-app", "com.example.app"],
    ] { XCTAssertThrowsError(try CommandLineOptions.parse(args), args.joined(separator: " ")) }
    XCTAssertEqual(
      try CommandLineOptions.parse(["--installed-apps", "--device", "id", "--json"]).agentCommand,
      "installed-apps")
    XCTAssertEqual(
      try CommandLineOptions.parse(["--launch-app", "com.example.app", "--device", "id"])
        .launchBundleIdentifier, "com.example.app")
  }

  func testLaunchOnlyNeverInstallsAndAppListOmitsPrivateFields() throws {
    var calls: [[String]] = []
    let deployer = DeviceDeployer(run: { args, _ in
      calls.append(args)
      if args.contains("lockState") {
        return Data(#"{"result":{"passcodeRequired":false,"unlockedSinceBoot":true}}"#.utf8)
      }
      if args.contains("apps") {
        return Data(
          #"{"result":{"apps":[{"bundleIdentifier":"com.example.app","name":"Test","url":"private-path"}]}}"#
            .utf8)
      }
      return Data("{}".utf8)
    })
    try deployer.launch(bundleIdentifier: "com.example.app", deviceIdentifier: "id")
    XCTAssertFalse(calls.contains { $0.contains("install") })
    XCTAssertTrue(calls.last?.contains("launch") == true)
    let apps = try deployer.installedApps(deviceIdentifier: "id", timeout: 3)
    XCTAssertEqual(apps.first?["bundleIdentifier"] as? String, "com.example.app")
    XCTAssertNil(apps.first?["url"])
    XCTAssertThrowsError(try deployer.launch(bundleIdentifier: "--help", deviceIdentifier: "id"))
  }

  func testReadinessRetriesUseInjectedClock() throws {
    var time: TimeInterval = 0
    var calls = 0
    try AgentCLI.waitUntilReady(
      deviceIdentifier: "id", timeout: 10,
      now: { time }, sleep: { time += $0 },
      check: { _, _ in
        calls += 1
        if calls < 3 { throw DeviceDeploymentError.deviceLocked }
      })
    XCTAssertEqual(calls, 3)
    XCTAssertEqual(time, 2)
  }

  func testDiagnosticFailureKeepsChecksAndOriginalFailureCode() throws {
    let error = DiagnosticFailure(
      underlying: DeviceDeploymentError.deviceLocked,
      checks: ["savedConfiguration": ["status": "failed", "message": "Invalid saved data"]])
    let failure = AgentCLI.failure(error, operation: "diagnose")
    XCTAssertEqual(failure.exitCode, 2)
    XCTAssertEqual((failure.object["error"] as? [String: Any])?["code"] as? String, "device_locked")
    XCTAssertNotNil(failure.object["checks"])
  }

  func testFailureExitCodeContract() {
    let cases: [(Error, String, Int32)] = [
      (CLIError.missingDevice, "missing_device", 64),
      (CLIError.deviceNotFound, "device_not_found", 2),
      (DeviceDeploymentError.invalidApp("test"), "invalid_app", 65),
      (DeviceDeploymentError.deviceLocked, "device_locked", 2),
      (DeviceDeploymentError.installationTimedOut, "installation_timed_out", 1),
      (DeviceDeploymentError.launchFailed("app"), "launch_failed", 1),
      (
        DeviceDeploymentError.commandFailed(arguments: [], status: 64),
        "internal_device_command_error", 1
      ),
      (TailscaleError.notConnected, "tailscale_unavailable", 2),
      (ManagedDeviceError.relayAlreadyRunning, "relay_already_running", 2),
      (NetworkSupportError.noNetworkInterface(interface: "auto"), "network_unavailable", 2),
    ]
    for (error, code, exit) in cases {
      let failure = AgentCLI.failure(error, operation: "deploy")
      XCTAssertEqual(failure.exitCode, exit, code)
      XCTAssertEqual((failure.object["error"] as? [String: Any])?["code"] as? String, code)
    }
  }
}

final class LocalMCPTests: XCTestCase {
  func testInitializationIsRequiredAndToolArgumentsCannotInjectFlags() throws {
    var calls: [[String]] = []
    let server = LocalMCP(execute: { args in
      calls.append(args)
      return Data(#"{"ok":true}"#.utf8)
    })
    func request(_ method: String, _ params: [String: Any] = [:]) -> [String: Any] {
      server.handle(["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        as? [String: Any] ?? [:]
    }
    XCTAssertNotNil(request("tools/list")["error"])
    XCTAssertNotNil(request("initialize")["result"])
    XCTAssertNil(server.handle(["jsonrpc": "2.0", "method": "notifications/initialized"]))
    let list = request("tools/list")["result"] as? [String: Any]
    XCTAssertEqual((list?["tools"] as? [Any])?.count, 6)
    XCTAssertNotNil(
      request(
        "tools/call",
        [
          "name": "launch_app",
          "arguments": ["deviceIdentifier": "id", "bundleIdentifier": "--help"],
        ])["error"])
    XCTAssertTrue(calls.isEmpty)
    let result = request(
      "tools/call",
      [
        "name": "launch_app",
        "arguments": ["deviceIdentifier": "id with space", "bundleIdentifier": "com.example.app"],
      ])
    XCTAssertNotNil(result["result"])
    XCTAssertEqual(
      calls, [["--launch-app", "com.example.app", "--device", "id with space", "--json"]])
    XCTAssertNotNil(
      request(
        "tools/call",
        ["name": "deploy_app", "arguments": ["deviceIdentifier": "id", "appPath": "relative.app"]])[
          "error"])
  }
}
