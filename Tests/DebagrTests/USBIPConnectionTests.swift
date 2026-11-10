import Darwin
import XCTest

@testable import Debagr

final class USBIPConnectionTests: XCTestCase {
  @MainActor
  private func reply(bus: String = "1-1", interfaces: UInt8 = 0) -> Data {
    var data = Data([1, 17, 0, 5, 0, 0, 0, 0, 0, 0, 0, 1])
    var device = [UInt8](repeating: 0, count: 312)
    for (index, byte) in bus.utf8.enumerated() { device[256 + index] = byte }
    device[300] = 0x05
    device[301] = 0xac
    device[302] = 0x12
    device[303] = 0xa8
    device[311] = interfaces
    data.append(contentsOf: device)
    data.append(Data(repeating: 0, count: Int(interfaces) * 4))
    return data
  }

  @MainActor
  func testDeviceListSupportsFragmentedUSBIPResponses() throws {
    let data = reply(interfaces: 2)
    for count in 0..<data.count { XCTAssertNil(try USBIPRemoteInventory.parse(data.prefix(count))) }
    XCTAssertEqual(
      try USBIPRemoteInventory.parse(data),
      [USBIPRemoteDevice(busID: "1-1", vendorID: 0x05ac, productID: 0x12a8)])
    XCTAssertEqual(try USBIPRemoteInventory.parse(Data([1, 17, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0])), [])
  }

  @MainActor
  func testDeviceListRejectsMalformedOrOversizedInput() {
    XCTAssertThrowsError(try USBIPRemoteInventory.parse(reply(bus: "--help")))
    XCTAssertThrowsError(try USBIPRemoteInventory.parse(Data(repeating: 1, count: 1_048_577)))
    XCTAssertThrowsError(
      try USBIPRemoteInventory.parse(Data([1, 17, 0, 5, 0, 0, 0, 0, 0, 0, 1, 0])))
    var failure = reply()
    failure[7] = 1
    XCTAssertThrowsError(try USBIPRemoteInventory.parse(failure))
  }

  @MainActor
  func testSessionRequestCanOnlyLaunchValidatedExportOrImport() throws {
    try USBIPSessionRequest(arguments: [
      "attach", "--tool", "/tmp/client", "--remote", "10.0.0.2", "--busid", "1-1",
    ]).validate()
    try USBIPSessionRequest(arguments: [
      "serve", "--tool", "/tmp/server", "--listen", "10.0.0.1", "--peer", "10.0.0.2", "--serial",
      "phone",
    ]).validate()
    for args in [
      ["help"], ["probe"], ["run-session", "--request", "/tmp/another"],
      ["attach", "--tool", "/tmp/client", "--remote", "8.8.8.8", "--busid", "1-1"],
    ] {
      XCTAssertThrowsError(try USBIPSessionRequest(arguments: args).validate())
    }
  }

  @MainActor
  func testStopRefusesAnUnrelatedLiveProcess() throws {
    XCTAssertFalse(
      try USBIPSessionSupervisor.matchesSupervisor(
        pid: getpid(), requestURL: URL(fileURLWithPath: "/tmp/not-our-session/request.json")))
    XCTAssertFalse(
      try USBIPSessionSupervisor.matchesSupervisor(
        pid: 1, requestURL: URL(fileURLWithPath: "/tmp/request.json")))
  }

  @MainActor
  func testShellArgumentsRemainLiteralAcrossAdministratorApproval() throws {
    let hostile = "a'b $(id) `id` \\\"quoted\\\""
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "printf %s " + USBIPSessionController.shellQuote(hostile)]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(String(decoding: data, as: UTF8.self), hostile)
    XCTAssertTrue(
      USBIPSessionController.administratorScript(command: "echo \"a\\b\"").contains(
        "with administrator privileges"))
    let script = try XCTUnwrap(
      NSAppleScript(
        source: USBIPSessionController.administratorScript(
          command: "printf %s " + USBIPSessionController.shellQuote(hostile))))
    var scriptError: NSDictionary?
    XCTAssertTrue(script.compileAndReturnError(&scriptError), "\(String(describing: scriptError))")
  }

  @MainActor
  func testPendingAdministratorApprovalKeepsMainQueueResponsiveAndCanBeCancelled() throws {
    let suite = "ApprovalResponsiveness-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let helper = folder.appendingPathComponent("fake-approval")
    try Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let session = USBIPSessionController(defaults: defaults, approvalExecutablePath: helper.path)
    let cancelled = expectation(description: "approval cancelled")
    session.onChange = { message, _ in
      if message.contains("approval cancelled") { cancelled.fulfill() }
    }
    try session.start(arguments: [
      "attach", "--tool", "/tmp/unused", "--remote", "10.0.0.2", "--busid", "1-1",
    ])
    defer {
      if let path = defaults.string(forKey: "usbip-session-request") {
        try? FileManager.default.removeItem(
          at: URL(fileURLWithPath: path).deletingLastPathComponent())
      }
    }
    XCTAssertTrue(session.busy)
    let responsive = expectation(description: "UI event processed during pending approval")
    DispatchQueue.main.async {
      XCTAssertTrue(session.busy)
      responsive.fulfill()
      session.cancelApproval()
    }
    wait(for: [responsive, cancelled], timeout: 3)
    XCTAssertFalse(session.busy)
    XCTAssertFalse(session.isRunning)
  }

}
