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

  private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "USBIPConnection-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    return folder
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
    let digest = String(repeating: "a", count: 64)
    let attach = ["attach", "--tool", "/tmp/client", "--remote", "10.0.0.2", "--busid", "1-1"]
    try USBIPSessionRequest(arguments: attach, toolSHA256: digest).validate()
    try USBIPSessionRequest(
      arguments: [
        "serve", "--tool", "/tmp/server", "--listen", "10.0.0.1", "--peer", "10.0.0.2", "--serial",
        "phone",
      ], toolSHA256: digest
    ).validate()
    for args in [
      ["help"], ["probe"], ["run-session", "--session", "/tmp/another", "--approved", "e30="],
      ["attach", "--tool", "/tmp/client", "--remote", "8.8.8.8", "--busid", "1-1"],
    ] {
      XCTAssertThrowsError(try USBIPSessionRequest(arguments: args, toolSHA256: digest).validate())
    }
    for digest in [
      "", String(repeating: "a", count: 63), String(repeating: "A", count: 64), digest + "\n",
    ] {
      XCTAssertThrowsError(
        try USBIPSessionRequest(arguments: attach, toolSHA256: digest).validate(), digest)
    }
  }

  @MainActor
  func testApprovedCommandLineCarriesTheWholeRequestAndPinsTheToolBytes() throws {
    let folder = try temporaryFolder()
    let tool = folder.appendingPathComponent("tool 'quoted' $(id) \"x\"")
    try Data("abc".utf8).write(to: tool)
    let arguments = ["attach", "--tool", tool.path, "--remote", "10.0.0.2", "--busid", "1-1"]
    let request = try USBIPSessionRequest(approving: arguments)
    XCTAssertEqual(
      request.toolSHA256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    let approved = try request.approvedArgument
    XCTAssertNil(approved.rangeOfCharacter(from: CharacterSet(charactersIn: "'\"\\$` \n")))
    let received = try USBIPSessionRequest(approvedArgument: approved)
    XCTAssertEqual(received.arguments, arguments)
    XCTAssertEqual(received.toolSHA256, request.toolSHA256)

    // The root-side parser accepts exactly what the app asks the administrator to approve.
    let session = folder.appendingPathComponent("session")
    let command = try USBIPCommand(
      Array(USBIPSessionSupervisor.commandPrefix(sessionURL: session).dropFirst(2)) + [approved])
    XCTAssertEqual(command.action, "run-session")
    XCTAssertEqual(command.values, ["--session": session.path, "--approved": approved])

    func encoded(_ json: String) -> String { Data(json.utf8).base64EncodedString() }
    for tampered in [
      "not base64!", encoded("[]"),
      encoded(#"{"arguments":["help"],"toolSHA256":"\#(request.toolSHA256)"}"#),
      encoded(#"{"arguments":["attach","--tool","/t","--remote","10.0.0.2","--busid","1-1"]}"#),
      encoded(
        #"{"arguments":["attach","--tool","/t","--remote","8.8.8.8","--busid","1-1"],"toolSHA256":"\#(request.toolSHA256)"}"#
      ),
    ] {
      XCTAssertThrowsError(try USBIPSessionRequest(approvedArgument: tampered), tampered)
    }

    for missing in [folder.appendingPathComponent("absent").path, folder.path] {
      XCTAssertThrowsError(
        try USBIPSessionRequest(approving: [
          "serve", "--tool", missing, "--listen", "10.0.0.1", "--peer", "10.0.0.2", "--serial",
          "phone",
        ])
      ) { XCTAssertTrue($0.localizedDescription.contains("patched longcable-server"), "\($0)") }
    }
    XCTAssertThrowsError(try USBIPSessionRequest(approving: ["help"]))
  }

  @MainActor
  func testRootRunsOnlyAPrivateCopyOfTheApprovedToolBytes() throws {
    let folder = try temporaryFolder()
    let parent = folder.appendingPathComponent("root-only")
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    // Homebrew installs tools as links, so the selected path may itself be a link.
    let installed = folder.appendingPathComponent("usbip-macos-1.0")
    try Data("approved".utf8).write(to: installed)
    let tool = folder.appendingPathComponent("usbip-macos")
    try FileManager.default.createSymbolicLink(at: tool, withDestinationURL: installed)
    let request = try USBIPSessionRequest(approving: [
      "attach", "--tool", tool.path, "--remote", "10.0.0.2", "--busid", "1-1",
    ])

    let verified = try request.installVerifiedTool(in: parent.path)
    let copy = verified.folder.appendingPathComponent("usbip-macos")
    XCTAssertEqual(verified.folder.deletingLastPathComponent().path, parent.path)
    XCTAssertEqual(
      verified.arguments, ["attach", "--tool", copy.path, "--remote", "10.0.0.2", "--busid", "1-1"])
    for path in [verified.folder.path, copy.path] {
      let attributes = try FileManager.default.attributesOfItem(atPath: path)
      XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o700, path)
    }

    func assertRejected(_ reason: String) throws {
      XCTAssertThrowsError(try request.installVerifiedTool(in: parent.path), reason) {
        XCTAssertTrue($0.localizedDescription.contains("changed after it was approved"), "\($0)")
      }
      XCTAssertEqual(try Data(contentsOf: copy), Data("approved".utf8), reason)
      XCTAssertEqual(
        try FileManager.default.contentsOfDirectory(atPath: parent.path),
        [verified.folder.lastPathComponent], reason)
    }
    try Data("replaced".utf8).write(to: installed)
    try assertRejected("changed bytes")
    try FileManager.default.removeItem(at: tool)
    try FileManager.default.createSymbolicLink(
      at: tool, withDestinationURL: URL(fileURLWithPath: "/bin/sh"))
    try assertRejected("link to another program")
    try FileManager.default.removeItem(at: tool)
    try FileManager.default.createDirectory(at: tool, withIntermediateDirectories: false)
    try assertRejected("not a file")
    try FileManager.default.removeItem(at: tool)
    try assertRejected("removed")
  }

  @MainActor
  func testRootStateNeverFollowsPlantedLinks() throws {
    let folder = try temporaryFolder()
    let session = folder.appendingPathComponent("session")
    try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
    let victim = folder.appendingPathComponent("victim")
    try Data("untouched".utf8).write(to: victim)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: victim.path)
    func assertVictimUntouched(_ reason: String) throws {
      XCTAssertEqual(try Data(contentsOf: victim), Data("untouched".utf8), reason)
      let attributes = try FileManager.default.attributesOfItem(atPath: victim.path)
      XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o644, reason)
    }
    let (directory, owner) = try USBIPSessionSupervisor.openDirectory(session)
    defer { close(directory) }
    XCTAssertEqual(owner, getuid())

    let stateURL = session.appendingPathComponent("state.json")
    for (name, pid) in [("state.json", Int32(41)), ("state.json.new", Int32(42))] {
      try FileManager.default.createSymbolicLink(
        at: session.appendingPathComponent(name), withDestinationURL: victim)
      try USBIPSessionSupervisor.writeState(
        USBIPSessionState(supervisorPID: pid, phase: "running", message: "Running"),
        in: directory, owner: owner)
      try assertVictimUntouched(name)
      let attributes = try FileManager.default.attributesOfItem(atPath: stateURL.path)
      XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular, name)
      XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o600, name)
      XCTAssertEqual(
        try JSONDecoder().decode(USBIPSessionState.self, from: Data(contentsOf: stateURL))
          .supervisorPID, pid)
      XCTAssertFalse(
        FileManager.default.fileExists(
          atPath: session.appendingPathComponent("state.json.new").path))
    }

    // The log and lock are opened in place: links and pipes are refused, not followed.
    try FileManager.default.createSymbolicLink(
      at: session.appendingPathComponent("output.log"), withDestinationURL: victim)
    try FileManager.default.linkItem(at: victim, to: session.appendingPathComponent("session.lock"))
    XCTAssertEqual(mkfifo(session.appendingPathComponent("pipe").path, 0o600), 0)
    for name in ["output.log", "session.lock", "pipe"] {
      XCTAssertThrowsError(
        try USBIPSessionSupervisor.openFile(name, in: directory, O_CREAT | O_WRONLY | O_APPEND),
        name)
      XCTAssertThrowsError(try USBIPSessionSupervisor.openFile(name, in: directory, O_RDONLY), name)
    }
    try assertVictimUntouched("log and lock")
    try FileManager.default.removeItem(at: session.appendingPathComponent("output.log"))
    let log = try USBIPSessionSupervisor.openFile(
      "output.log", in: directory, O_CREAT | O_WRONLY | O_APPEND)
    close(log)
    XCTAssertEqual(
      try FileManager.default.attributesOfItem(
        atPath: session.appendingPathComponent("output.log").path)[.posixPermissions] as? NSNumber,
      0o600)

    let link = folder.appendingPathComponent("linked-session")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: session)
    XCTAssertThrowsError(try USBIPSessionSupervisor.openDirectory(link))
    XCTAssertThrowsError(try USBIPSessionSupervisor.openDirectory(victim))
  }

  @MainActor
  func testDefaultToolLookupUsesOnlyInstallLocations() throws {
    let folder = try temporaryFolder()
    let directories = ["first", "second"].map { folder.appendingPathComponent($0) }
    for directory in directories {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func lookup(_ role: DebagrMachineRole) -> String? {
      USBIPSessionController.executable(for: role, in: directories.map(\.path))
    }
    XCTAssertNil(lookup(.builder))
    let client = directories[1].appendingPathComponent("usbip-macos")
    try Data("#!/bin/sh\n".utf8).write(to: client)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: client.path)
    // A folder that has the tool's name is not a tool.
    try FileManager.default.createDirectory(
      at: directories[0].appendingPathComponent("usbip-macos"), withIntermediateDirectories: true)
    XCTAssertEqual(lookup(.builder), client.path)
    XCTAssertNil(lookup(.client))
    let server = directories[0].appendingPathComponent("longcable-server")
    try Data("#!/bin/sh\n".utf8).write(to: server)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: server.path)
    XCTAssertNil(lookup(.client))
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: server.path)
    XCTAssertEqual(lookup(.client), server.path)

    for role in [DebagrMachineRole.builder, .client] {
      if let found = USBIPSessionController.executable(for: role) {
        XCTAssertTrue(
          found.hasPrefix("/opt/homebrew/bin/") || found.hasPrefix("/usr/local/bin/"), found)
      }
    }
  }

  @MainActor
  func testStopRefusesAnUnrelatedLiveProcess() throws {
    XCTAssertFalse(
      try USBIPSessionSupervisor.matchesSupervisor(
        pid: getpid(), sessionURL: URL(fileURLWithPath: "/tmp/not-our-session")))
    XCTAssertFalse(
      try USBIPSessionSupervisor.matchesSupervisor(
        pid: 1, sessionURL: URL(fileURLWithPath: "/tmp")))
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
  func testSecondStartWaitsForApprovedSupervisorToPublishState() throws {
    let suite = "USBIPStartup-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { try? FileManager.default.removeItem(at: folder) }
    let session = USBIPSessionController(
      defaults: defaults, approvalExecutablePath: "/usr/bin/true", sessionsDirectory: folder)
    let approved = expectation(description: "approval finished")
    session.onChange = { message, _ in
      if message == "Starting connection process…" { approved.fulfill() }
    }
    let args = ["attach", "--tool", "/usr/bin/true", "--remote", "10.0.0.2", "--busid", "1-1"]
    try session.start(arguments: args)
    wait(for: [approved], timeout: 3)
    XCTAssertTrue(session.busy)
    XCTAssertFalse(session.waitingForApproval)
    XCTAssertThrowsError(try session.start(arguments: args))
    let request = try XCTUnwrap(defaults.string(forKey: "usbip-session-request"))
    let stateURL = URL(fileURLWithPath: request).deletingLastPathComponent()
      .appendingPathComponent("state.json")
    try JSONEncoder().encode(
      USBIPSessionState(supervisorPID: 0, phase: "failed", message: "Stopped")
    )
    .write(to: stateURL)
    session.poll()
    XCTAssertFalse(session.busy)
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
    let session = USBIPSessionController(
      defaults: defaults, approvalExecutablePath: helper.path,
      sessionsDirectory: folder.appendingPathComponent("USBIPSessions"))
    let cancelled = expectation(description: "approval cancelled")
    session.onChange = { message, _ in
      if message.contains("approval cancelled") { cancelled.fulfill() }
    }
    // The tool is hashed before approval is requested, so it has to exist.
    try session.start(arguments: [
      "attach", "--tool", helper.path, "--remote", "10.0.0.2", "--busid", "1-1",
    ])
    // The session folder must stay out of the real Application Support directory.
    XCTAssertTrue(
      try XCTUnwrap(defaults.string(forKey: "usbip-session-request")).hasPrefix(folder.path))
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
