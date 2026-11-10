import XCTest

@testable import Debagr

@MainActor
final class USBPairingTests: XCTestCase {
  private let serial = "00008101000A0B123456001E"

  func testInventoryIsScopedToTunnelAndRejectsEntities() throws {
    let commands = FakeUSBCommands()
    let inventory = try VirtualHereState.decode(commands.xml, port: 45001)
    XCTAssertEqual(inventory.devices.map(\.serial), [serial])
    XCTAssertTrue(inventory.devices[0].isAvailable)
    XCTAssertTrue(try VirtualHereState.decode(commands.xml, port: 45002).devices.isEmpty)
    XCTAssertTrue(
      try VirtualHereState.decode(
        commands.xml.replacingOccurrences(of: "host=\"127.0.0.1\"", with: "host=\"192.168.1.9\""),
        port: 45001
      ).devices.isEmpty)
    XCTAssertTrue(
      try VirtualHereState.decode(
        commands.xml.replacingOccurrences(of: "idVendor=\"1452\"", with: "idVendor=\"1\""),
        port: 45001
      ).devices.isEmpty)
    XCTAssertThrowsError(
      try VirtualHereState.decode(
        "<!DOCTYPE state [<!ENTITY file SYSTEM 'file:///etc/passwd'>]><state>&file;</state>",
        port: 45001))
    XCTAssertThrowsError(try VirtualHereState.decode("<state>", port: 45001))
  }

  func testOwnershipUsesConnectionUUIDNotMachineName() throws {
    let commands = FakeUSBCommands()
    commands.inUse = true
    XCTAssertTrue(try VirtualHereState.decode(commands.xml, port: 45001).devices[0].isOwnedByClient)
    commands.boundConnection = "another-client"
    XCTAssertFalse(
      try VirtualHereState.decode(commands.xml, port: 45001).devices[0].isOwnedByClient)
  }

  func testHostValidationAndShellArgumentsCannotAddCommands() throws {
    for host in ["nearby-mac", "me@macbook.local", "100.64.2.3"] {
      XCTAssertNoThrow(try USBSSHTunnel.validateHost(host))
    }
    for host in [
      "", "-oProxyCommand=bad", "mac;touch /tmp/bad", "mac\nnext", "two hosts", "u@@host",
    ] {
      XCTAssertThrowsError(try USBSSHTunnel.validateHost(host))
    }
    XCTAssertEqual(
      USBPairingSession.shellQuote("phone's $(command); service"),
      "'phone'\\''s $(command); service'")
    XCTAssertTrue(USBSSHTunnel.sshOptions.contains("StrictHostKeyChecking=yes"))
    XCTAssertTrue(USBSSHTunnel.sshOptions.contains("ForwardAgent=no"))
  }

  func testServerMustListenOnlyOnLoopback() {
    let local = "tcp4 0 0 127.0.0.1.7575 *.* LISTEN\n"
    XCTAssertNoThrow(try USBPairingSession.validateServerListeners(local))
    XCTAssertThrowsError(try USBPairingSession.validateServerListeners(""))
    XCTAssertThrowsError(
      try USBPairingSession.validateServerListeners(local + "tcp6 0 0 *.7575 *.* LISTEN\n"))
    XCTAssertThrowsError(
      try USBPairingSession.validateServerListeners("tcp4 0 0 100.64.1.2.7575 *.* LISTEN\n"))
  }

  func testCompleteUSBPairingAndWirelessHandoffReleasesOnlySelectedDevice() throws {
    let commands = FakeUSBCommands()
    let tunnel = FakeUSBTunnel()
    let session = makeSession(commands, tunnel)
    let devices = try session.prepare(host: "nearby-mac")
    try session.attach(XCTUnwrap(devices.first))
    let device = try session.pair()
    XCTAssertEqual(device.identity.value, "00008101-000A0B123456001E")
    let configuration = try session.finish(
      provider: .wireguard, address: "10.20.0.2", serviceHost: "iphone.local.")
    XCTAssertEqual(configuration.deviceIdentifier, device.identity.value)
    XCTAssertEqual(configuration.profile.peerIP, "10.20.0.2")
    XCTAssertFalse(tunnel.isRunning)
    XCTAssertFalse(commands.inUse)
    XCTAssertTrue(commands.apiCommands.contains("STOP USING,usb-hub.1"))
    XCTAssertTrue(commands.apiCommands.contains("MANUAL HUB REMOVE,127.0.0.1:45001"))
    XCTAssertFalse(commands.apiCommands.contains { $0.contains("ALL") && $0 != "LIST" })
  }

  func testPairingCannotPassFromCachedInventoryWithoutUSB() throws {
    let commands = FakeUSBCommands()
    let session = makeSession(commands, FakeUSBTunnel())
    let device = try XCTUnwrap(session.prepare(host: "nearby").first)
    try session.attach(device)
    commands.attached = false
    XCTAssertThrowsError(try session.pair())
    XCTAssertEqual(commands.appleCommands.count, 0)
    try session.stop()
  }

  func testLockedDeviceDoesNotCompletePairing() throws {
    let commands = FakeUSBCommands()
    commands.locked = true
    let session = makeSession(commands, FakeUSBTunnel())
    let device = try XCTUnwrap(session.prepare(host: "nearby").first)
    try session.attach(device)
    XCTAssertThrowsError(try session.pair()) { XCTAssertTrue($0 is DeviceDeploymentError) }
    XCTAssertThrowsError(
      try session.finish(provider: .wireguard, address: "10.20.0.2", serviceHost: "iphone.local."))
    XCTAssertTrue(commands.inUse)
    try session.stop()
  }

  func testDeviceOwnershipChangeDoesNotStopAnotherClient() throws {
    let commands = FakeUSBCommands()
    let tunnel = FakeUSBTunnel()
    let session = makeSession(commands, tunnel)
    let device = try XCTUnwrap(session.prepare(host: "nearby").first)
    try session.attach(device)
    commands.boundConnection = "another-client"
    XCTAssertThrowsError(try session.stop())
    XCTAssertFalse(commands.apiCommands.contains("STOP USING,usb-hub.1"))
    XCTAssertFalse(tunnel.isRunning)
  }

  func testFailedUseStillReleasesAnAcceptedClaim() throws {
    let commands = FakeUSBCommands()
    commands.failUseAfterClaim = true
    let session = makeSession(commands, FakeUSBTunnel())
    let device = try XCTUnwrap(session.prepare(host: "nearby").first)
    XCTAssertThrowsError(try session.attach(device))
    try session.stop()
    XCTAssertTrue(commands.apiCommands.contains("STOP USING,usb-hub.1"))
    XCTAssertFalse(commands.inUse)
  }

  func testProfileFailureKeepsUSBForRecoveryAndCannotSaveWrongEndpoint() throws {
    let commands = FakeUSBCommands()
    let tunnel = FakeUSBTunnel()
    let session = makeSession(commands, tunnel)
    let device = try XCTUnwrap(session.prepare(host: "nearby").first)
    try session.attach(device)
    _ = try session.pair()
    XCTAssertThrowsError(
      try session.finish(provider: .wireguard, address: "10.20.0.3", serviceHost: "iphone.local."))
    XCTAssertTrue(commands.inUse)
    XCTAssertTrue(tunnel.isRunning)
    try session.stop()
  }

  func testHandoffWaitsForUSBRemoval() throws {
    let commands = FakeUSBCommands()
    commands.delayedRemoval = true
    let session = makeSession(commands, FakeUSBTunnel())
    let device = try XCTUnwrap(session.prepare(host: "nearby").first)
    try session.attach(device)
    _ = try session.pair()
    XCTAssertThrowsError(
      try session.finish(provider: .wireguard, address: "10.20.0.2", serviceHost: "iphone.local."))
    commands.attached = false
    XCTAssertNoThrow(
      try session.finish(provider: .wireguard, address: "10.20.0.2", serviceHost: "iphone.local."))
  }

  func testTunnelIsStoppedEvenWhenClientCleanupFails() throws {
    let commands = FakeUSBCommands()
    let tunnel = FakeUSBTunnel()
    let session = makeSession(commands, tunnel)
    _ = try session.prepare(host: "nearby")
    commands.failRemove = true
    XCTAssertThrowsError(try session.stop())
    XCTAssertFalse(tunnel.isRunning)
  }

  func testWirelessHandoffCanRetryCleanupAfterTunnelCloses() throws {
    let commands = FakeUSBCommands()
    let tunnel = FakeUSBTunnel()
    let session = makeSession(commands, tunnel)
    try session.attach(XCTUnwrap(session.prepare(host: "nearby").first))
    _ = try session.pair()
    commands.failRemove = true
    XCTAssertThrowsError(
      try session.finish(provider: .wireguard, address: "10.20.0.2", serviceHost: "iphone.local."))
    XCTAssertFalse(tunnel.isRunning)
    XCTAssertFalse(commands.inUse)
    commands.failRemove = false
    XCTAssertNoThrow(
      try session.finish(provider: .wireguard, address: "10.20.0.2", serviceHost: "iphone.local."))
    XCTAssertThrowsError(
      try session.finish(provider: .wireguard, address: "10.20.0.3", serviceHost: "iphone.local."))
  }

  func testPrivateProfileHelpersRequireExplicitJSONAndCorrectArguments() throws {
    XCTAssertEqual(
      try CommandLineOptions.parse(["--usb-services", "--json"]).agentCommand, "usb-services")
    XCTAssertEqual(
      try CommandLineOptions.parse([
        "--usb-profile", "--json", "--provider", "wireguard", "--peer", "10.20.0.2",
        "--bonjour-host", "iphone.local.",
      ]).agentCommand, "usb-profile")
    for arguments in [
      ["--usb-services"], ["--usb-profile", "--json"],
      ["--usb-services", "--json", "--device", "x"], ["--usb-services", "--json", "--status"],
      ["--usb-services", "--json", "--profile", "/tmp/x"],
      ["--usb-services", "--json", "--provider", "wireguard"],
    ] {
      XCTAssertThrowsError(try CommandLineOptions.parse(arguments))
    }
  }

  func testCommandTimeoutIsBoundedAndCancellationPreventsNewCommands() {
    let runner = USBCommandRunner()
    let start = Date()
    XCTAssertThrowsError(try runner.run("/bin/sleep", ["5"], timeout: 0.1))
    XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    runner.cancel()
    XCTAssertThrowsError(try runner.run("/usr/bin/true", [], timeout: 1)) {
      XCTAssertTrue($0 is CancellationError)
    }
  }

  @MainActor
  func testNativeWorkflowOnlyCompletesAfterPairingAndUSBRelease() async throws {
    let commands = FakeUSBCommands()
    let tunnel = FakeUSBTunnel()
    let session = makeSession(commands, tunnel)
    var saved: ConfiguredDevice?
    var delivered: ConfiguredDevice?
    var failSave = true
    let model = USBPairingModel(
      makeSession: { session },
      saveConfiguration: {
        if failSave { throw USBPairingError("Disk write failed") }
        saved = $0
      })
    model.host = "nearby"
    let advance = { model.advance { delivered = $0 } }
    advance()
    await settle(model)
    XCTAssertEqual(model.stage, .device)
    XCTAssertFalse(model.canAdvance)
    model.selectedID = try XCTUnwrap(model.devices.first).id
    advance()
    await settle(model)
    XCTAssertEqual(model.stage, .trust)
    XCTAssertNil(saved)
    advance()
    await settle(model)
    XCTAssertEqual(model.stage, .wireless)
    model.provider = .wireguard
    model.address = "10.20.0.2"
    model.serviceHost = "iphone.local."
    XCTAssertFalse(model.canAdvance)
    model.confirmsService = true
    advance()
    await settle(model)
    XCTAssertEqual(model.error, "Disk write failed")
    XCTAssertNil(delivered)
    XCTAssertFalse(tunnel.isRunning)
    failSave = false
    advance()
    await settle(model)
    XCTAssertNil(model.error)
    XCTAssertEqual(saved?.deviceIdentifier, delivered?.deviceIdentifier)
    XCTAssertNotNil(delivered)
    XCTAssertFalse(model.hasSession)
    XCTAssertFalse(tunnel.isRunning)
  }

  @MainActor
  func testStoppingIgnoresAnInFlightSetupCompletion() async {
    let commands = FakeUSBCommands()
    let tunnel = FakeUSBTunnel()
    let model = USBPairingModel(
      makeSession: { self.makeSession(commands, tunnel) },
      saveConfiguration: { _ in XCTFail("Cancelled setup must not save") })
    model.host = "nearby"
    model.advance { _ in XCTFail("Cancelled setup must not complete") }
    model.stop()
    await settle(model)
    XCTAssertEqual(model.stage, .setup)
    XCTAssertFalse(model.hasSession)
    XCTAssertFalse(tunnel.isRunning)
  }

  func testShutdownWaitsForCleanupWithoutBlockingTheMainActorOrDeliveringLateSetup() async {
    let commands = FakeUSBCommands()
    let tunnel = FakeUSBTunnel()
    let model = USBPairingModel(
      makeSession: { self.makeSession(commands, tunnel) },
      saveConfiguration: { _ in XCTFail("Shutdown must not save") })
    model.host = "nearby"
    model.advance { _ in XCTFail("Shutdown must not complete setup") }
    let finished = expectation(description: "Cleanup finished")
    model.shutdown { finished.fulfill() }
    XCTAssertTrue(model.hasSession, "Shutdown must return before background cleanup completes")
    await fulfillment(of: [finished], timeout: 3)
    XCTAssertFalse(model.hasSession)
    XCTAssertFalse(model.isBusy)
    XCTAssertFalse(tunnel.isRunning)
    XCTAssertEqual(model.stage, .setup)
  }

  @MainActor
  private func settle(_ model: USBPairingModel) async {
    for _ in 0..<100 where model.isBusy {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertFalse(model.isBusy)
  }

  private func makeSession(_ commands: FakeUSBCommands, _ tunnel: FakeUSBTunnel)
    -> USBPairingSession
  {
    USBPairingSession(runner: commands, makeTunnel: { _ in tunnel }, acquireLease: { NSObject() })
  }
}

private final class FakeUSBTunnel: USBTunnel {
  let port: UInt16 = 45001
  var isRunning = true
  func stop() { isRunning = false }
}

private final class FakeUSBCommands: USBCommandRunning {
  var inUse = false
  var attached = false
  var boundConnection = "this-client"
  var locked = false
  var failUseAfterClaim = false
  var delayedRemoval = false
  var failRemove = false
  var apiCommands: [String] = []
  var appleCommands: [[String]] = []
  var xml: String {
    """
    <state><server><connection host="127.0.0.1" port="45001" hostname="usb-hub" serverSerial="test-server" uuid="this-client" state="3"/>
    <device address="1" idVendor="1452" product="iPhone" deviceSerial="00008101000A0B123456001E" state="\(inUse ? 3 : 1)" boundConnectionUUID="\(inUse ? boundConnection : "")"/>
    </server></state>
    """
  }
  func cancel() {}
  func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> String {
    if executable == USBPairingSession.clientPath {
      let command = arguments[1]
      apiCommands.append(command)
      switch command {
      case "LIST": return "Auto-Use All currently off"
      case "GET CLIENT STATE": return xml
      case "USE,usb-hub.1":
        inUse = true
        attached = true
        if failUseAfterClaim { throw USBPairingError("IPC timeout after USE") }
      case "STOP USING,usb-hub.1":
        inUse = false
        if !delayedRemoval { attached = false }
      default:
        if command.hasPrefix("MANUAL HUB REMOVE") && failRemove {
          throw USBPairingError("Client unavailable")
        }
      }
      return "OK"
    }
    if executable == "/usr/bin/ssh" {
      let command = arguments.last!
      if command.contains("netstat") { return "tcp4 0 0 127.0.0.1.7575 *.* LISTEN" }
      if command.contains("--usb-services") {
        return
          "{\"schemaVersion\":1,\"services\":[{\"host\":\"iphone.local.\",\"name\":\"iPhone\"}]}"
      }
      let profile = DeviceProfile(
        bonjourName: "phone", bonjourTXT: ["identity": "fixture"],
        provider: "wireguard", peerIP: "10.20.0.2", remotePort: 49152,
        localPortRange: [55000, 58000])
      return String(data: try JSONEncoder().encode(profile), encoding: .utf8)!
    }
    if executable == "/usr/sbin/ioreg" {
      let values: [[String: Any]] =
        attached ? [["idVendor": 1452, "USB Serial Number": "00008101000A0B123456001E"]] : []
      return String(
        data: try PropertyListSerialization.data(
          fromPropertyList: values, format: .xml, options: 0), encoding: .utf8)!
    }
    if executable == "/usr/bin/xcrun" {
      appleCommands.append(arguments)
      let output = arguments[arguments.firstIndex(of: "--json-output")! + 1]
      let json: String
      if arguments.contains("devices") {
        json =
          "{\"result\":{\"devices\":[{\"properties\":{\"name\":\"Test iPhone\",\"hardware\":{\"udid\":\"00008101-000A0B123456001E\",\"deviceType\":\"iPhone\",\"reality\":\"physical\"}}}]}}"
      } else if arguments.contains("lockState") {
        json = "{\"result\":{\"passcodeRequired\":\(locked),\"unlockedSinceBoot\":true}}"
      } else {
        json = "{\"result\":{}}"
      }
      try Data(json.utf8).write(to: URL(fileURLWithPath: output))
      return ""
    }
    throw USBPairingError("Unexpected command in test")
  }
}
