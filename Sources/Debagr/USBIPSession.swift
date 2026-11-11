import AppKit
import CryptoKit
import Darwin
import Foundation

struct USBIPSessionState: Codable {
  let supervisorPID: Int32
  let phase: String
  let message: String
}

struct USBIPSessionRequest: Codable {
  let arguments: [String]
  /// SHA-256 of the tool the user approved. Root runs only a private copy with these bytes.
  let toolSHA256: String

  private static func command(_ arguments: [String]) throws -> USBIPCommand {
    let command = try USBIPCommand(arguments)
    guard ["serve", "attach"].contains(command.action) else {
      throw USBIPError.invalid("A connection session must export or import one USB device.")
    }
    return command
  }

  @discardableResult
  func validate() throws -> USBIPCommand {
    let command = try Self.command(arguments)
    guard toolSHA256.utf8.count == 64,
      toolSHA256.utf8.allSatisfy("0123456789abcdef".utf8.contains)
    else {
      throw USBIPError.invalid("The connection request does not identify its USB support tool.")
    }
    return command
  }
}

extension USBIPSessionRequest {
  /// Pins the selected tool's current bytes before administrator approval is requested.
  init(approving arguments: [String]) throws {
    let command = try Self.command(arguments)
    let tool = command.values["--tool"]!
    guard let data = Self.readTool(tool) else {
      throw USBIPError.invalid(USBIPCommand.missingTool(tool, action: command.action))
    }
    self.init(arguments: arguments, toolSHA256: Self.sha256(data))
  }

  /// The whole request travels in the approved command line, so root never reads it from a
  /// file the user account can change. Base64 needs no shell or AppleScript escaping.
  var approvedArgument: String {
    get throws { try JSONEncoder().encode(self).base64EncodedString() }
  }

  init(approvedArgument: String) throws {
    guard let data = Data(base64Encoded: approvedArgument) else {
      throw USBIPError.invalid("The approved connection request is unreadable.")
    }
    self = try JSONDecoder().decode(Self.self, from: data)
    try validate()
  }

  /// Root only. The selected path (for example under /opt/homebrew) can be replaced without
  /// privileges, so the approved bytes run from a new folder that only root can reach.
  /// Returns that folder and the child arguments that point --tool at the copy.
  func installVerifiedTool(in parent: String = "/private/tmp") throws -> (
    folder: URL, arguments: [String]
  ) {
    let tool = try validate().values["--tool"]!
    guard let data = Self.readTool(tool), Self.sha256(data) == toolSHA256 else {
      throw USBIPError.invalid(
        "The USB support tool at \(tool) changed after it was approved. Start the connection again."
      )
    }
    // mkdir never follows or reuses an existing entry, and /private/tmp is sticky.
    let folder = URL(fileURLWithPath: "\(parent)/debagr-usbip-\(UUID().uuidString)")
    // Role detection reads the process name, so the copy keeps the tool's file name.
    let copy = folder.appendingPathComponent(URL(fileURLWithPath: tool).lastPathComponent)
    guard mkdir(folder.path, 0o700) == 0 else {
      throw USBIPError.invalid("Cannot create a private folder for the USB support tool.")
    }
    guard
      FileManager.default.createFile(
        atPath: copy.path, contents: data, attributes: [.posixPermissions: 0o700])
    else {
      try? FileManager.default.removeItem(at: folder)
      throw USBIPError.invalid("Cannot copy the USB support tool for this connection.")
    }
    var arguments = arguments
    arguments[arguments.firstIndex(of: "--tool")! + 1] = copy.path
    return (folder, arguments)
  }

  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// Reads through one descriptor so the bytes that are hashed are the bytes that are used.
  private static func readTool(_ path: String) -> Data? {
    let descriptor = open(path, O_RDONLY | O_NONBLOCK)
    guard descriptor >= 0 else { return nil }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? file.close() }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
    return try? file.readToEnd() ?? Data()
  }
}

/// A transient administrator-approved supervisor owns exactly one backend process.
enum USBIPSessionSupervisor {
  /// One definition for the approved command line and for recognising its process later.
  static func commandPrefix(sessionURL: URL) -> [String] {
    [
      Bundle.main.executableURL?.path ?? CommandLine.arguments[0], "--usbip", "run-session",
      "--session", sessionURL.path, "--approved",
    ]
  }

  /// The session folder belongs to the user account. Root opens the folder itself, never a
  /// link planted in its place, and reaches its files only through this descriptor.
  static func openDirectory(_ url: URL) throws -> (descriptor: Int32, owner: uid_t) {
    let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    var info = stat()
    guard descriptor >= 0, fstat(descriptor, &info) == 0 else {
      if descriptor >= 0 { close(descriptor) }
      throw USBIPError.invalid("Cannot open the connection session folder.")
    }
    return (descriptor, info.st_uid)
  }

  /// Accepts only a plain file with no other name, so a planted symbolic link, hard link or
  /// pipe cannot redirect what root reads, writes or hands over to the user.
  static func openFile(_ name: String, in directory: Int32, _ flags: Int32) throws -> Int32 {
    let descriptor = openat(directory, name, flags | O_NOFOLLOW | O_NONBLOCK, 0o600)
    var info = stat()
    guard descriptor >= 0, fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
      info.st_nlink == 1
    else {
      if descriptor >= 0 { close(descriptor) }
      throw USBIPError.invalid("Cannot safely open \(name) in the connection session folder.")
    }
    return descriptor
  }

  /// Publishes state by renaming a newly created file over state.json. A link planted under
  /// that name is replaced, never written through and never given a new owner.
  static func writeState(_ state: USBIPSessionState, in directory: Int32, owner: uid_t) throws {
    unlinkat(directory, "state.json.new", 0)
    let descriptor = try openFile("state.json.new", in: directory, O_CREAT | O_EXCL | O_WRONLY)
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try file.write(contentsOf: JSONEncoder().encode(state))
    _ = fchown(descriptor, owner, gid_t.max)
    try file.close()
    guard renameat(directory, "state.json.new", directory, "state.json") == 0 else {
      throw USBIPError.invalid("Cannot record the connection state.")
    }
  }

  static func run(sessionURL: URL, approved: String) throws {
    guard geteuid() == 0 else {
      throw USBIPError.invalid("The connection supervisor requires administrator approval.")
    }
    let request = try USBIPSessionRequest(approvedArgument: approved)
    let (directory, owner) = try openDirectory(sessionURL)
    defer { close(directory) }
    let lockFD = try openFile("session.lock", in: directory, O_CREAT | O_RDWR)
    defer { close(lockFD) }
    guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
      throw USBIPError.invalid("This connection session is already running.")
    }
    let logFD = try openFile("output.log", in: directory, O_CREAT | O_WRONLY | O_APPEND)
    _ = fchown(logFD, owner, gid_t.max)
    let log = FileHandle(fileDescriptor: logFD, closeOnDealloc: true)
    defer { try? log.close() }
    func state(_ phase: String, _ message: String) throws {
      try writeState(
        USBIPSessionState(supervisorPID: getpid(), phase: phase, message: message),
        in: directory, owner: owner)
    }
    let child = Process()
    child.executableURL =
      Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    child.standardInput = FileHandle.nullDevice
    child.standardOutput = log
    child.standardError = log
    let stopping = LockedValue(false)
    let signals = SignalHandler {
      stopping.set(true)
      if child.isRunning {
        _ = kill(child.processIdentifier, SIGINT)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
          if child.isRunning { child.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
          if child.isRunning { _ = kill(child.processIdentifier, SIGKILL) }
        }
      }
    }
    defer { signals.stop() }
    var toolFolder: URL?
    defer { if let toolFolder { try? FileManager.default.removeItem(at: toolFolder) } }
    do {
      let tool = try request.installVerifiedTool()
      toolFolder = tool.folder
      child.arguments = ["--usbip"] + tool.arguments
      try child.run()
      try state(
        "running",
        "USB \(request.arguments.first == "serve" ? "export" : "import") process running. Device readiness is not yet verified."
      )
      child.waitUntilExit()
      if stopping.get() || child.terminationStatus == 0 {
        try state("stopped", "Connection process stopped.")
      } else {
        try state("failed", "Connection process exited with status \(child.terminationStatus).")
      }
    } catch {
      if child.isRunning {
        _ = kill(child.processIdentifier, SIGKILL)
        child.waitUntilExit()
      }
      try? state("failed", error.localizedDescription)
      throw error
    }
  }

  static func stop(sessionURL: URL) throws {
    guard geteuid() == 0 else {
      throw USBIPError.invalid("Stopping this connection requires administrator approval.")
    }
    let (directory, _) = try openDirectory(sessionURL)
    defer { close(directory) }
    let file = FileHandle(
      fileDescriptor: try openFile("state.json", in: directory, O_RDONLY), closeOnDealloc: true)
    defer { try? file.close() }
    let state = try JSONDecoder().decode(
      USBIPSessionState.self, from: file.readToEnd() ?? Data())
    guard state.phase == "running", state.supervisorPID > 1 else { return }
    guard try matchesSupervisor(pid: state.supervisorPID, sessionURL: sessionURL) else {
      throw USBIPError.invalid(
        "The original connection supervisor is no longer running. No other process was stopped.")
    }
    guard kill(state.supervisorPID, SIGINT) == 0 else {
      throw USBIPError.invalid("Could not stop the connection supervisor.")
    }
  }

  static func matchesSupervisor(pid: Int32, sessionURL: URL) throws -> Bool {
    guard pid > 1 else { return false }
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-ww", "-p", String(pid), "-o", "command="]
    let pipe = Pipe()
    ps.standardOutput = pipe
    try ps.run()
    let command = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    ps.waitUntilExit()
    return command.hasPrefix(commandPrefix(sessionURL: sessionURL).joined(separator: " ") + " ")
  }
}

@MainActor
final class USBIPSessionController {
  private(set) var diagnostics = ""
  private let defaults: UserDefaults
  private let supervisorMatches: (Int32, URL) throws -> Bool
  private let approvalExecutablePath: String
  private let sessionsDirectory: URL
  private var approvalProcess: Process?
  private var approvalCancelled = false
  // Main-thread polling; Timer.invalidate is also safe during nonisolated destruction.
  nonisolated(unsafe) private var timer: Timer?
  private(set) var busy = false
  private var waitingSince: Date?
  private var feedbackContext: String?
  private var filtersFeedback = false
  private var ignoredRequestPath: String?
  private var observedActiveRequestPath: String?
  var onChange: ((String, Bool) -> Void)?
  private var requestURL: URL? {
    defaults.string(forKey: "usbip-session-request").map { URL(fileURLWithPath: $0) }
  }

  init(
    defaults: UserDefaults = .standard,
    supervisorMatches: @escaping (Int32, URL) throws -> Bool = USBIPSessionSupervisor
      .matchesSupervisor,
    approvalExecutablePath: String = "/usr/bin/osascript",
    sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Debagr/USBIPSessions")
  ) {
    self.defaults = defaults
    self.supervisorMatches = supervisorMatches
    self.approvalExecutablePath = approvalExecutablePath
    self.sessionsDirectory = sessionsDirectory
    timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
    if let timer { RunLoop.main.add(timer, forMode: .common) }
  }

  deinit {
    timer?.invalidate()
    if approvalProcess?.isRunning == true { approvalProcess?.terminate() }
  }

  func setFeedbackContext(_ context: String?) {
    if feedbackContext != context { observedActiveRequestPath = nil }
    filtersFeedback = true
    feedbackContext = context
  }

  func resetFeedback() {
    ignoredRequestPath = requestURL?.path
    observedActiveRequestPath = nil
    diagnostics = ""
    waitingSince = nil
  }

  func backendPath(for role: DebagrMachineRole) -> String? {
    if let saved = defaults.string(forKey: "usbip-backend-\(role.rawValue)") {
      return Self.validExecutable(saved) ? saved : nil
    }
    return Self.executable(for: role)
  }

  func hasMissingSavedBackend(for role: DebagrMachineRole) -> Bool {
    defaults.string(forKey: "usbip-backend-\(role.rawValue)") != nil
      && backendPath(for: role) == nil
  }

  func rememberBackend(_ path: String, for role: DebagrMachineRole) throws {
    guard Self.validExecutable(path) else {
      throw USBIPError.invalid("Choose an existing executable file for USB support.")
    }
    defaults.set(path, forKey: "usbip-backend-\(role.rawValue)")
  }

  private static func validExecutable(_ path: String) -> Bool {
    var directory: ObjCBool = false
    return path.hasPrefix("/") && !path.contains(where: { $0.isNewline })
      && FileManager.default.fileExists(atPath: path, isDirectory: &directory)
      && !directory.boolValue && FileManager.default.isExecutableFile(atPath: path)
  }

  static func shellQuote(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func administratorScript(command: String) -> String {
    let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
      of: "\"", with: "\\\"")
    return "do shell script \"\(escaped)\" with administrator privileges"
  }

  static func executable(
    for role: DebagrMachineRole, in directories: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]
  ) -> String? {
    directories.map { "\($0)/\(role.backend)" }.first(where: validExecutable)
  }

  var isRunning: Bool {
    guard let url = requestURL,
      let data = try? Data(
        contentsOf: url.deletingLastPathComponent().appendingPathComponent("state.json")),
      let state = try? JSONDecoder().decode(USBIPSessionState.self, from: data),
      state.phase == "running"
    else { return false }
    return
      (try? supervisorMatches(state.supervisorPID, url.deletingLastPathComponent()))
      == true
  }

  func start(arguments: [String]) throws {
    guard !busy, !isRunning else {
      throw USBIPError.invalid("Stop the current connection before starting another.")
    }
    let request = try USBIPSessionRequest(approving: arguments)
    ignoredRequestPath = nil
    diagnostics = ""
    let directory = sessionsDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let url = directory.appendingPathComponent("request.json")
    // A record for the user and for support. Root acts only on the approved command line.
    try ManagedDeviceStore.writePrivate(try JSONEncoder().encode(request), to: url)
    defaults.set(url.path, forKey: "usbip-session-request")
    defaults.set(feedbackContext, forKey: "usbip-session-context")
    let command =
      (USBIPSessionSupervisor.commandPrefix(sessionURL: directory) + [try request.approvedArgument])
      .map(Self.shellQuote).joined(separator: " ") + " </dev/null >/dev/null 2>&1 &"
    authorize(command: command, starting: true)
  }

  func stop() {
    guard !busy, let url = requestURL, isRunning else { return }
    let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    let command = [
      executable, "--usbip", "stop-session", "--session", url.deletingLastPathComponent().path,
    ].map(Self.shellQuote).joined(separator: " ")
    authorize(command: command, starting: false)
  }

  private func authorize(command: String, starting: Bool) {
    busy = true
    approvalCancelled = false
    onChange?("Waiting for administrator approval…", true)
    // The system helper owns the blocking authentication request; AppKit stays responsive.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: approvalExecutablePath)
    process.arguments = ["-e", Self.administratorScript(command: command)]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    let errors = Pipe()
    process.standardError = errors
    process.terminationHandler = { [weak self] process in
      let data = errors.fileHandleForReading.readDataToEndOfFile()
      let detail = String(decoding: data.suffix(1600), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.approvalProcess === process else { return }
        self.approvalProcess = nil
        self.busy = false
        if self.approvalCancelled || process.terminationStatus != 0 {
          self.diagnostics = detail
          self.onChange?(
            self.approvalCancelled || detail.contains("(-128)")
              ? "Administrator approval cancelled. Start Setup Connection when you are ready."
              : "Administrator approval did not complete. Check Diagnostics, then retry.",
            self.isRunning)
        } else {
          self.waitingSince = starting ? Date() : nil
          self.onChange?(
            starting ? "Starting connection process…" : "Stopping connection process…", true)
        }
      }
    }
    approvalProcess = process
    do { try process.run() } catch {
      approvalProcess = nil
      busy = false
      diagnostics = error.localizedDescription
      onChange?("Unable to open administrator approval. Check Diagnostics, then retry.", isRunning)
    }
  }

  func cancelApproval() {
    guard busy, let process = approvalProcess, process.isRunning else { return }
    approvalCancelled = true
    process.terminate()
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
      if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
    }
  }

  func poll() {
    guard !busy, let url = requestURL else { return }
    let active = isRunning
    if active { observedActiveRequestPath = url.path }
    if !active {
      guard ignoredRequestPath != url.path else { return }
      if filtersFeedback {
        guard let feedbackContext,
          defaults.string(forKey: "usbip-session-context") == feedbackContext
            || observedActiveRequestPath == url.path
        else { return }
      }
    }
    let directory = url.deletingLastPathComponent()
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("state.json")),
      let state = try? JSONDecoder().decode(USBIPSessionState.self, from: data)
    else {
      if let waitingSince, Date().timeIntervalSince(waitingSince) > 10 {
        self.waitingSince = nil
        onChange?(
          "The connection supervisor could not start. Check the installed app and retry.", false)
      }
      return
    }
    waitingSince = nil
    var message = state.message
    diagnostics = state.message
    if state.phase == "failed",
      let log = try? FileHandle(forReadingFrom: directory.appendingPathComponent("output.log"))
    {
      defer { try? log.close() }
      if let size = try? log.seekToEnd() {
        try? log.seek(toOffset: size > 1600 ? size - 1600 : 0)
        if let data = try? log.read(upToCount: 1600) {
          diagnostics += "\n" + String(decoding: data, as: UTF8.self)
        }
      }
    }
    if state.phase == "failed" {
      message =
        "The USB connection could not start. Open Diagnostics for the error, then retry Start Setup Connection."
    }
    if state.phase == "running", !active {
      message = "Connection supervisor exited unexpectedly. Start again to reconnect."
    }
    onChange?(message, active)
  }
}
