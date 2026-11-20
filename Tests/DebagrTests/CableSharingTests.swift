import Darwin
import Network
import XCTest

@testable import Debagr

final class CableSharingTests: XCTestCase {
  func testExactAddressBindingDoesNotRequirePathInterface() throws {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return XCTFail("Unable to reserve a test port") }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    var size = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
    }
    close(fd)
    XCTAssertEqual(bound, 0)
    XCTAssertEqual(named, 0)
    let pair = try RelayPair(
      bindInterface: nil, remoteHost: NWEndpoint.Host("127.0.0.1"), remotePort: 9,
      localPort: UInt16(bigEndian: address.sin_port), localInterfaceAddress: "127.0.0.1",
      accessPolicy: RelayAccessPolicy(allowedSourceAddresses: ["127.0.0.1"]))
    defer { pair.stop() }
    let ready = expectation(description: "TCP and UDP bound without interface lookup")
    pair.start { result in
      if case .failure(let error) = result { XCTFail(error.localizedDescription) }
      ready.fulfill()
    }
    wait(for: [ready], timeout: 5)
    XCTAssertTrue(pair.isHealthy)
  }

  func testControlChannelOpensPortsAndStopsItsChild() throws {
    let control = CableHostControl()
    defer { control.stop() }
    try control.startProcess(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: [
        "-c",
        "printf 'ready 100.64.0.2\\n'; while IFS= read -r line; do printf 'ok %s\\n' \"${line#open }\"; done",
      ],
      expectedPeerIP: "100.64.0.2")
    try control.open(port: 50000)
    try control.open(port: 50001)
    let ended = expectation(description: "owned control child exited")
    control.onExit = { ended.fulfill() }
    control.stop()
    wait(for: [ended], timeout: 3)
    XCTAssertFalse(control.isRunning)
    XCTAssertThrowsError(try control.open(port: 50002))
  }

  func testControlRejectsWrongPeerAndEarlyEOF() {
    for script in ["printf 'ready 100.64.0.3\\n'", "exit 0"] {
      let control = CableHostControl()
      defer { control.stop() }
      XCTAssertThrowsError(
        try control.startProcess(
          executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script],
          expectedPeerIP: "100.64.0.2"))
    }
  }

  func testCancellationStopsBeforeDiscoveryOrListeners() throws {
    let options = try CommandLineOptions.parse(["--direct-device", "--peer", "100.64.0.2"])
    let bridge = DirectDeviceApplication(options: options, isCancelled: { true })
    XCTAssertThrowsError(try bridge.start()) { XCTAssertTrue($0 is CancellationError) }
    bridge.stop()
    let control = CableHostControl()
    control.stop()
    control.stop()
    XCTAssertThrowsError(try control.open(port: 50000))
  }
  func testCableEndpointRequiresScopedLinkLocalAddress() {
    for value in ["fe80::1%en9", "FE80::1234%en12", "febf::1%en0"] {
      XCTAssertTrue(CableSharing.Options.isCableEndpoint(value), value)
    }
    for value in [
      "fe80::1", "::1%en0", "2001:db8::1%en0", "fec0::1%en0",
      "fe80::1%utun4", "fe80::1%en0%en1", "fe80::xyz%en0", "phone.local",
    ] {
      XCTAssertFalse(CableSharing.Options.isCableEndpoint(value), value)
    }
  }

  func testOptionsRejectUnsafeOrAmbiguousTargets() throws {
    let serve = ["serve", "--peer", "100.64.0.2", "--endpoint", "fe80::1%en9"]
    XCTAssertEqual(try CableSharing.Options(serve).mode, "serve")
    let connect = [
      "connect", "--peer", "100.64.0.2", "--endpoint", "fe80::1%en9",
      "--port", "50000", "--profile", "/tmp/profile.json",
      "--ssh", "user@mac.local", "--tool", "/Applications/Debagr.app/Contents/MacOS/Debagr",
    ]
    XCTAssertEqual(try CableSharing.Options(connect).mode, "connect")
    for arguments in [
      serve + ["--peer", "100.64.0.3"], serve + ["--allow-lan", "yes"],
      ["serve", "--peer", "8.8.8.8", "--endpoint", "fe80::1%en9"],
      Array(connect.dropLast(2)), ["connect"],
    ] {
      XCTAssertThrowsError(try CableSharing.Options(arguments))
    }
    for host in ["-oProxyCommand=evil", "user@mac;evil", "$(evil)", "mac\nother"] {
      XCTAssertFalse(CableSharing.Options.isSSHHost(host))
    }
  }

  func testControlCannotSelectOtherDestinationsOrPrivilegedPorts() {
    XCTAssertEqual(CableSharing.requestedPort("open 49152"), 49152)
    XCTAssertEqual(CableSharing.requestedPort("open 65535"), 65535)
    for request in [
      "open 22", "open 0", "open 65536", "open -1", "open 1234 host",
      "open 1234\nopen 2345", "OPEN 1234", "open 1.2.3.4:5000",
    ] {
      XCTAssertNil(CableSharing.requestedPort(request), request)
    }
  }

  func testSSHCommandArgumentsAreIndividuallyQuoted() {
    XCTAssertEqual(CableHostControl.shellQuote("/a b/debagr"), "'/a b/debagr'")
    XCTAssertEqual(CableHostControl.shellQuote("a'b"), "'a'\\''b'")
    XCTAssertEqual(CableHostControl.shellQuote("$(touch /tmp/no)"), "'$(touch /tmp/no)'")
  }
}
