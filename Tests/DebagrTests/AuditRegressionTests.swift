import Network
import XCTest

@testable import Debagr

final class AuditRegressionTests: XCTestCase {
  func testNativeBonjourRegistrationAppearsAndStops() throws {
    try verifyNativeRegistration(allInterfaces: false)
  }

  func testNativeBonjourRegistrationMatchesProductionShape() throws {
    try verifyNativeRegistration(allInterfaces: true)
  }

  private func verifyNativeRegistration(allInterfaces: Bool) throws {
    let binding: InterfaceBinding
    do { binding = try NetworkSupport.resolveInterface(named: "auto") } catch {
      throw XCTSkip("Bonjour integration needs an active network interface")
    }
    let name = "Debagr-test-\(UUID().uuidString)"
    let found = expectation(description: "native Bonjour service visible")
    found.assertForOverFulfill = false
    let capture = BonjourCapture()
    try capture.startBrowsing { instance in
      if instance.contains(name) { found.fulfill() }
    }
    defer { capture.stop() }
    let proxy = try BonjourProxy(
      interfaceName: allInterfaces ? "0" : binding.name, instanceName: name,
      localPort: 45678, localHost: "\(name.lowercased()).local" + (allInterfaces ? "" : "."),
      localIP: binding.ipv4Address,
      txt: ["test": "native"])
    try proxy.start()
    defer { proxy.stop() }
    wait(for: [found], timeout: 5)
    XCTAssertTrue(proxy.isHealthy)
    proxy.stop()
    XCTAssertFalse(proxy.isHealthy)
  }

  func testSimulatorAndMacArtifactsAreRejectedBeforeAppleCommand() throws {
    let app = FileManager.default.temporaryDirectory.appendingPathComponent(
      "WrongPlatform-\(UUID()).app")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: app) }
    for platform in ["iPhoneSimulator", "MacOSX"] {
      let info: [String: Any] = [
        "CFBundleIdentifier": "com.example.test", "CFBundleSupportedPlatforms": [platform],
      ]
      try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Info.plist"))
      XCTAssertThrowsError(try DeviceDeployer.bundleIdentifier(at: app), platform)
    }
  }

  func testTCPRelayForwardsBytes() throws { try checkRelay(udp: false) }
  func testUDPRelayForwardsDatagrams() throws { try checkRelay(udp: true) }

  private func checkRelay(udp: Bool) throws {
    let binding: InterfaceBinding
    do { binding = try NetworkSupport.resolveInterface(named: "auto") } catch {
      throw XCTSkip("Relay integration needs an active Wi-Fi/Ethernet interface: \(error)")
    }
    let queue = DispatchQueue(label: "test.echo")
    let echo = try NWListener(using: udp ? .udp : .tcp)
    let listening = expectation(description: "echo ready")
    echo.stateUpdateHandler = { if case .ready = $0 { listening.fulfill() } }
    var accepted: [NWConnection] = []
    echo.newConnectionHandler = { connection in
      accepted.append(connection)
      connection.start(queue: queue)
      let reply: (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void = { data, _, _, _ in
        connection.send(content: data, completion: .contentProcessed { _ in })
      }
      if udp {
        connection.receiveMessage(completion: reply)
      } else {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096, completion: reply)
      }
    }
    echo.start(queue: queue)
    defer {
      echo.cancel()
      queue.sync { for connection in accepted { connection.cancel() } }
    }
    wait(for: [listening], timeout: 3)
    let remotePort = try XCTUnwrap(echo.port).rawValue
    let localPort = UInt16.random(in: 40000...60000)
    let pair = try RelayPair(
      bindInterface: binding.networkInterface, remoteHost: "127.0.0.1",
      remotePort: remotePort, localPort: localPort, localInterfaceAddress: binding.ipv4Address,
      accessPolicy: RelayAccessPolicy(
        localInterfaceAddress: binding.ipv4Address, allowLANClients: false))
    defer { pair.stop() }
    let started = expectation(description: "relay ready")
    var startup: Result<Void, Error>?
    pair.start {
      startup = $0
      started.fulfill()
    }
    wait(for: [started], timeout: 3)
    try XCTUnwrap(startup).get()
    let client = NWConnection(
      host: NWEndpoint.Host(binding.ipv4Address),
      port: NWEndpoint.Port(rawValue: localPort)!, using: udp ? .udp : .tcp)
    defer { client.cancel() }
    let received = expectation(description: "echo through relay")
    let payload = Data("relay regression".utf8)
    client.stateUpdateHandler = { state in
      if case .ready = state {
        client.send(
          content: payload, completion: .contentProcessed { error in XCTAssertNil(error) })
      }
    }
    client.start(queue: queue)
    let verify: (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void = {
      data, _, _, error in
      XCTAssertNil(error)
      XCTAssertEqual(data, payload)
      received.fulfill()
    }
    if udp {
      client.receiveMessage(completion: verify)
    } else {
      client.receive(
        minimumIncompleteLength: payload.count, maximumLength: 4096, completion: verify)
    }
    wait(for: [received], timeout: 5)
  }

  func testLineReaderKeepsSplitUTF8AndCRLF() {
    let received = expectation(description: "complete Unicode lines")
    received.expectedFulfillmentCount = 2
    var lines: [String] = []
    let process = OwnedLineProcess(
      executablePath: "/usr/bin/true", arguments: [], label: "test.lines"
    ) { line in
      lines.append(line)
      received.fulfill()
    }
    let bytes = Array("Příliš\r\nlast".utf8)
    for byte in bytes { process.appendOutput(Data([byte])) }
    process.flushOutput()
    wait(for: [received], timeout: 2)
    XCTAssertEqual(lines, ["Příliš", "last"])
  }

  func testShortOuterDeadlinesKeepValidAppleTimeout() throws {
    for timeout in [0.3, 3, 4.99, 5, 5.1] {
      var receivedTimeout: TimeInterval = 0
      var arguments: [String] = []
      let deployer = DeviceDeployer(run: { args, deadline in
        arguments = args
        receivedTimeout = deadline
        return Data(#"{"result":{"passcodeRequired":false,"unlockedSinceBoot":true}}"#.utf8)
      })
      try deployer.checkReady(deviceIdentifier: "test", timeout: timeout)
      let index = try XCTUnwrap(arguments.firstIndex(of: "--timeout"))
      XCTAssertEqual(arguments[index + 1], String(max(5, Int(timeout.rounded(.up)))))
      XCTAssertEqual(receivedTimeout, timeout)
    }
  }

  func testAppleErrorPreservesCodeDomainAndDescription() throws {
    let data = Data(
      #"{"error":{"code":1000,"domain":"com.apple.dt.CoreDeviceError","localizedDescription":"Device not found"}}"#
        .utf8)
    let error = try XCTUnwrap(DeviceDeployer.appleError(from: data))
    let failure = AgentCLI.failure(error, operation: "status")
    let detail = try XCTUnwrap(failure.object["error"] as? [String: Any])
    XCTAssertEqual(detail["underlyingCode"] as? Int, 1000)
    XCTAssertEqual(detail["underlyingDomain"] as? String, "com.apple.dt.CoreDeviceError")
    XCTAssertEqual(detail["message"] as? String, "Device not found")
    XCTAssertEqual(failure.exitCode, 2)
  }

  func testUnknownDeviceFailsWithoutRetrying() {
    var calls = 0
    XCTAssertThrowsError(
      try AgentCLI.waitUntilReady(
        deviceIdentifier: "missing", timeout: 30,
        check: { _, _ in
          calls += 1
          throw DeviceDeploymentError.appleError(
            code: 1000, domain: "com.apple.dt.CoreDeviceError", message: "Missing")
        }))
    XCTAssertEqual(calls, 1)
  }

  func testInstallTimeoutReportsUnknownOutcome() throws {
    let failure = AgentCLI.failure(DeviceDeploymentError.installationTimedOut, operation: "deploy")
    let detail = try XCTUnwrap(failure.object["error"] as? [String: Any])
    XCTAssertEqual(detail["code"] as? String, "installation_timed_out")
    XCTAssertEqual(detail["installationOutcome"] as? String, "unknown")
    XCTAssertEqual(detail["installationConfirmed"] as? Bool, false)
    XCTAssertEqual(failure.exitCode, 1)
  }

  func testRejectedDuplicateAndIgnoredDeploymentOptions() {
    for args in [
      ["--status", "--device", "one", "--device", "two"],
      ["--deploy-app", "/tmp/App.app", "--device", "one", "--timeout", "30"],
      ["--status", "--device", "one", "--timeout", "5", "--timeout", "10"],
    ] { XCTAssertThrowsError(try CommandLineOptions.parse(args), args.joined(separator: " ")) }
  }

  func testAccessPolicyAllowsOnlyExplicitSource() {
    let policy = RelayAccessPolicy(allowedSourceAddresses: ["192.168.1.5"])
    XCTAssertTrue(policy.allows(NWConnection(host: "192.168.1.5", port: 1234, using: .tcp)))
    XCTAssertFalse(policy.allows(NWConnection(host: "192.168.1.6", port: 1234, using: .tcp)))
    XCTAssertFalse(policy.allows(NWConnection(host: "example.com", port: 1234, using: .tcp)))
  }

  func testPeerSelectionRejectsAmbiguousAndOfflineMatches() throws {
    let json = Data(
      #"{"BackendState":"Running","Peer":{"a":{"HostName":"phone","DNSName":"phone.one.ts.net.","TailscaleIPs":["100.64.0.1"],"Online":true},"b":{"HostName":"phone","DNSName":"phone.two.ts.net.","TailscaleIPs":["100.64.0.2"],"Online":false}}}"#
        .utf8)
    XCTAssertThrowsError(try TailscaleClient.selectPeer(named: "phone", from: json))
    XCTAssertThrowsError(try TailscaleClient.selectPeer(named: "100.64.0.2", from: json))
    XCTAssertEqual(
      try TailscaleClient.selectPeer(named: "PHONE.ONE.TS.NET.", from: json).ipAddress, "100.64.0.1"
    )
  }
}
