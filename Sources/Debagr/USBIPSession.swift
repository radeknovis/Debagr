import AppKit
import Darwin
import Foundation

struct USBIPSessionState: Codable {
  let supervisorPID: Int32
  let phase: String
  let message: String
}

struct USBIPSessionRequest: Codable {
  let arguments: [String]

  func validate() throws {
    let command = try USBIPCommand(arguments)
    guard ["serve", "attach"].contains(command.action) else {
      throw USBIPError.invalid("A connection session must export or import one USB device.")
    }
  }
}

/// A transient administrator-approved supervisor owns exactly one backend process.
enum USBIPSessionSupervisor {
  static func run(requestURL: URL) throws {
    guard geteuid() == 0 else {
      throw USBIPError.invalid("The connection supervisor requires administrator approval.")
    }
    let directory = requestURL.deletingLastPathComponent()
    let request = try JSONDecoder().decode(
      USBIPSessionRequest.self, from: Data(contentsOf: requestURL))
    try request.validate()
    let lockFD = open(
      directory.appendingPathComponent("session.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard lockFD >= 0 else { throw USBIPError.invalid("Cannot lock the connection session.") }
    defer { close(lockFD) }
    guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
      throw USBIPError.invalid("This connection session is already running.")
    }
    let logFD = open(
      directory.appendingPathComponent("output.log").path,
      O_CREAT | O_WRONLY | O_APPEND | O_NOFOLLOW, 0o600)
    guard logFD >= 0 else { throw USBIPError.invalid("Cannot open the connection log.") }
    guard
      let owner = try FileManager.default.attributesOfItem(atPath: directory.path)[.ownerAccountID]
        as? NSNumber
    else {
      close(logFD)
      throw USBIPError.invalid("Cannot identify the connection session owner.")
    }
    _ = fchown(logFD, owner.uint32Value, gid_t.max)
    let log = FileHandle(fileDescriptor: logFD, closeOnDealloc: true)
    defer { try? log.close() }
    func state(_ phase: String, _ message: String) throws {
      let url = directory.appendingPathComponent("state.json")
      try JSONEncoder().encode(
        USBIPSessionState(supervisorPID: getpid(), phase: phase, message: message)
      ).write(to: url, options: .atomic)
      _ = chown(url.path, owner.uint32Value, gid_t.max)
      _ = chmod(url.path, 0o600)
    }
    let child = Process()
    child.executableURL =
      Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["--usbip"] + request.arguments
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
    do {
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

  static func stop(requestURL: URL) throws {
    guard geteuid() == 0 else {
      throw USBIPError.invalid("Stopping this connection requires administrator approval.")
    }
    let stateURL = requestURL.deletingLastPathComponent().appendingPathComponent("state.json")
    let state = try JSONDecoder().decode(USBIPSessionState.self, from: Data(contentsOf: stateURL))
    guard state.phase == "running", state.supervisorPID > 1 else { return }
    guard try matchesSupervisor(pid: state.supervisorPID, requestURL: requestURL) else {
      throw USBIPError.invalid(
        "The original connection supervisor is no longer running. No other process was stopped.")
    }
    guard kill(state.supervisorPID, SIGINT) == 0 else {
      throw USBIPError.invalid("Could not stop the connection supervisor.")
    }
  }

  static func matchesSupervisor(pid: Int32, requestURL: URL) throws -> Bool {
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
    let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    return command == "\(executable) --usbip run-session --request \(requestURL.path)"
  }
}

final class USBIPSessionController {
  private(set) var diagnostics = ""
  private let defaults: UserDefaults
  private let supervisorMatches: (Int32, URL) throws -> Bool
  private let approvalExecutablePath: String
  private var approvalProcess: Process?
  private var approvalCancelled = false
  private var timer: Timer?
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
    approvalExecutablePath: String = "/usr/bin/osascript"
  ) {
    self.defaults = defaults
    self.supervisorMatches = supervisorMatches
    self.approvalExecutablePath = approvalExecutablePath
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll()
    }
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

  static func executable(for role: DebagrMachineRole) -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let paths =
      role == .client
      ? [
        "\(home)/src/longcable/.build/release/longcable-server",
        "/opt/homebrew/bin/longcable-server", "/usr/local/bin/longcable-server",
      ]
      : [
        "\(home)/src/usbip-macos/usbip-macos", "/opt/homebrew/bin/usbip-macos",
        "/usr/local/bin/usbip-macos",
      ]
    return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  var isRunning: Bool {
    guard let url = requestURL,
      let data = try? Data(
        contentsOf: url.deletingLastPathComponent().appendingPathComponent("state.json")),
      let state = try? JSONDecoder().decode(USBIPSessionState.self, from: data),
      state.phase == "running"
    else { return false }
    return
      (try? supervisorMatches(state.supervisorPID, url))
      == true
  }

  func start(arguments: [String]) throws {
    guard !busy, !isRunning else {
      throw USBIPError.invalid("Stop the current connection before starting another.")
    }
    let request = USBIPSessionRequest(arguments: arguments)
    try request.validate()
    ignoredRequestPath = nil
    diagnostics = ""
    let directory = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Application Support/Debagr/USBIPSessions/\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let url = directory.appendingPathComponent("request.json")
    try JSONEncoder().encode(request).write(to: url, options: .atomic)
    defaults.set(url.path, forKey: "usbip-session-request")
    defaults.set(feedbackContext, forKey: "usbip-session-context")
    let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    let command =
      ([executable, "--usbip", "run-session", "--request", url.path].map(Self.shellQuote).joined(
        separator: " ")) + " </dev/null >/dev/null 2>&1 &"
    authorize(command: command, starting: true)
  }

  func stop() {
    guard !busy, let url = requestURL, isRunning else { return }
    let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    let command = [executable, "--usbip", "stop-session", "--request", url.path].map(
      Self.shellQuote
    ).joined(separator: " ")
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
