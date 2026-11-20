import Darwin
import Foundation
import Network

/// Experimental service forwarding for a phone already paired with the Builder.
/// SSH authenticates the control channel; data listeners accept only that Builder's VPN IP.
struct CableSharingError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
  init(_ message: String) { self.message = message }
}

enum CableSharing {
  static let usage = """
    Experimental Mac cable sharing (existing Xcode pairing required):
      debagr --cable connect --ssh user@cable-mac --peer <host-Tailscale-IP> \
        --endpoint <phone-link-local-IPv6%interface> --port <RemotePairing-port> \
        --profile <saved-device-profile> --tool <absolute-debagr-path-on-host>
    Private SSH helper:
      debagr --cable serve --peer <Builder-Tailscale-IP> --endpoint <IPv6%interface>
    No raw USB, new pairing, automatic endpoint discovery or reconnect is provided.
    """

  struct Options {
    let mode: String
    let values: [String: String]

    init(_ arguments: [String]) throws {
      guard let mode = arguments.first, ["serve", "connect"].contains(mode) else {
        throw CableSharingError(usage)
      }
      var values: [String: String] = [:]
      var index = 1
      let allowed: Set<String> =
        mode == "serve"
        ? ["--peer", "--endpoint"]
        : ["--peer", "--endpoint", "--port", "--profile", "--ssh", "--tool"]
      while index < arguments.count {
        let key = arguments[index]
        guard allowed.contains(key), values[key] == nil, index + 1 < arguments.count else {
          throw CableSharingError("Invalid or duplicate cable option.\n" + usage)
        }
        let value = arguments[index + 1]
        guard !value.isEmpty, !value.hasPrefix("-"),
          value.rangeOfCharacter(from: .controlCharacters) == nil
        else { throw CableSharingError("Invalid cable option value.") }
        values[key] = value
        index += 2
      }
      guard Set(values.keys) == allowed,
        NetworkSupport.isAllowedTailscaleIPv4(values["--peer"]!),
        Self.isCableEndpoint(values["--endpoint"]!)
      else {
        throw CableSharingError(
          "Cable sharing requires a VPN peer and scoped link-local IPv6 endpoint.")
      }
      if mode == "connect" {
        guard let port = UInt16(values["--port"]!), port >= 1024,
          Self.isSSHHost(values["--ssh"]!),
          values["--tool"]!.hasPrefix("/")
        else { throw CableSharingError("Invalid cable port, SSH host or absolute helper path.") }
      }
      self.mode = mode
      self.values = values
    }

    static func isCableEndpoint(_ value: String) -> Bool {
      let parts = value.split(separator: "%", omittingEmptySubsequences: false)
      guard parts.count == 2,
        parts[1].range(of: "^en[0-9]+$", options: .regularExpression) != nil
      else { return false }
      var address = in6_addr()
      guard String(parts[0]).withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else {
        return false
      }
      return withUnsafeBytes(of: address) { $0[0] == 0xfe && ($0[1] & 0xc0) == 0x80 }
    }

    static func isSSHHost(_ value: String) -> Bool {
      value.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.@-]*$", options: .regularExpression) != nil
    }
  }

  static func run(_ arguments: [String]) throws {
    if arguments == ["help"] {
      print(usage)
      return
    }
    let options = try Options(arguments)
    if options.mode == "serve" {
      try serve(options)
      return
    }
    let values = options.values
    guard let saved = try ProfileStore(url: URL(fileURLWithPath: values["--profile"]!)).load()
    else {
      throw CableSharingError(
        "No saved device profile. Capture it while the paired phone is nearby.")
    }
    try saved.validate()
    let binding = try NetworkSupport.resolveTailscaleInterface()
    guard binding.ipv4Address != values["--peer"] else {
      throw CableSharingError("The cable host must be another Mac.")
    }
    let profile = DeviceProfile(
      bonjourName: saved.bonjourName, bonjourTXT: saved.bonjourTXT,
      provider: "tailscale", peerIP: values["--peer"]!, remotePort: UInt16(values["--port"]!)!,
      localPortRange: saved.localPortRange, tunnelPortRange: saved.tunnelPortRange)
    let control = CableHostControl()
    defer { control.stop() }
    let cancelled = LockedValue(false)
    let stopped = DispatchSemaphore(value: 0)
    let signals = SignalHandler {
      cancelled.set(true)
      control.stop()
      stopped.signal()
    }
    defer { signals.stop() }
    try control.start(options: options, builderIP: binding.ipv4Address)
    var directOptions = try CommandLineOptions.parse(["--direct-device", "--peer", profile.peerIP])
    directOptions.profileURL = URL(fileURLWithPath: values["--profile"]!)
    let bridge = DirectDeviceApplication(
      options: directOptions, profile: profile, isCancelled: { cancelled.get() },
      prepareRemotePort: { port in try control.open(port: port) })
    defer { bridge.stop() }
    control.onExit = { stopped.signal() }
    try bridge.start()
    print(
      "Cable service bridge started. Verify --status and a real app install/launch with phone Wi-Fi off."
    )
    stopped.wait()
    if !cancelled.get(), !control.isRunning {
      throw CableSharingError(
        "Cable host disconnected. Restart after checking the cable and SSH connection.")
    }
  }

  /// Requests contain only ports. The remote destination is fixed for this entire session.
  static func requestedPort(_ line: String) -> UInt16? {
    guard line.hasPrefix("open "), let port = UInt16(line.dropFirst(5)), port >= 1024 else {
      return nil
    }
    return port
  }

  private static func serve(_ options: Options) throws {
    let binding = try NetworkSupport.resolveTailscaleInterface()
    var limit = rlimit()
    if getrlimit(RLIMIT_NOFILE, &limit) == 0 {
      limit.rlim_cur = min(4096, limit.rlim_max)
      guard setrlimit(RLIMIT_NOFILE, &limit) == 0 else {
        throw CableSharingError("Unable to reserve cable relay file descriptors.")
      }
    }
    guard binding.ipv4Address != options.values["--peer"] else {
      throw CableSharingError("Builder and cable host must differ.")
    }
    var pairs: [UInt16: RelayPair] = [:]
    defer { for pair in pairs.values { pair.stop() } }
    func reply(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
    reply("ready " + binding.ipv4Address)
    var line = Data()
    var byte: UInt8 = 0
    while Darwin.read(STDIN_FILENO, &byte, 1) == 1 {
      if byte != 10 {
        guard line.count < 64 else { throw CableSharingError("Oversized cable control request.") }
        line.append(byte)
        continue
      }
      let request = String(data: line, encoding: .utf8) ?? ""
      line.removeAll(keepingCapacity: true)
      guard let port = requestedPort(request) else {
        reply("error invalid port")
        continue
      }
      if pairs[port]?.isHealthy == true {
        reply("ok \(port)")
        continue
      }
      pairs.removeValue(forKey: port)?.stop()
      guard pairs.count < 256 else {
        reply("error session port limit; restart bridge")
        continue
      }
      do {
        let pair = try RelayPair(
          bindInterface: binding.networkInterface,
          remoteHost: NWEndpoint.Host(options.values["--endpoint"]!),
          remotePort: port, localPort: port, localInterfaceAddress: binding.ipv4Address,
          accessPolicy: RelayAccessPolicy(allowedSourceAddresses: [options.values["--peer"]!]))
        let ready = DispatchSemaphore(value: 0)
        let result = LockedValue<Result<Void, Error>?>(nil)
        pair.start {
          result.set($0)
          ready.signal()
        }
        guard ready.wait(timeout: .now() + 5) == .success, let value = result.get() else {
          pair.stop()
          throw RelayError.startupTimedOut
        }
        do { try value.get() } catch {
          pair.stop()
          throw error
        }
        pairs[port] = pair
        reply("ok \(port)")
      } catch { reply("error listener unavailable") }
    }
  }
}

/// One request at a time, bounded replies/deadlines, and no shell interpolation of untrusted values.
// Buffer access belongs to queue; lifecycle mutation uses processLock; replies/callbacks use LockedValue.
final class CableHostControl: @unchecked Sendable {
  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  private let queue = DispatchQueue(label: "debagr.cable-control")
  private let response = LockedValue<String?>(nil)
  private let received = DispatchSemaphore(value: 0)
  private var buffer = Data()
  private let exitCallback = LockedValue<(() -> Void)?>(nil)
  private let processLock = NSLock()
  private var stopped = false
  var onExit: (() -> Void)? {
    get { exitCallback.get() }
    set {
      exitCallback.set(newValue)
      if !isRunning { newValue?() }
    }
  }
  var isRunning: Bool { process.isRunning }

  static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  func start(options: CableSharing.Options, builderIP: String) throws {
    let values = options.values
    let remote = [
      values["--tool"]!, "--cable", "serve", "--peer", builderIP,
      "--endpoint", values["--endpoint"]!,
    ].map(Self.shellQuote).joined(separator: " ")
    try startProcess(
      executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
      arguments: [
        "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
        "-o", "ConnectTimeout=5", "-o", "ServerAliveInterval=5",
        "-o", "ServerAliveCountMax=2", "--", values["--ssh"]!, remote,
      ],
      expectedPeerIP: values["--peer"]!)
  }

  func startProcess(executableURL: URL, arguments: [String], expectedPeerIP: String) throws {
    processLock.lock()
    process.executableURL = executableURL
    process.arguments = arguments
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.standardError
    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if data.isEmpty { handle.readabilityHandler = nil }
      self?.queue.async { [weak self] in self?.consume(data) }
    }
    process.terminationHandler = { [weak self] _ in
      self?.received.signal()
      self?.exitCallback.get()?()
    }
    do {
      guard !stopped else { throw CancellationError() }
      // A disappearing SSH child must produce EPIPE rather than terminate Debagr.
      guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
        throw CableSharingError("Unable to protect the SSH control pipe.")
      }
      try process.run()
      processLock.unlock()
    } catch {
      processLock.unlock()
      throw error
    }
    guard try readReply(timeout: 10) == "ready " + expectedPeerIP else {
      throw CableSharingError("SSH cable host did not confirm the selected VPN address.")
    }
  }

  func open(port: UInt16) throws {
    processLock.lock()
    do {
      guard !stopped, isRunning else { throw CableSharingError("Cable host is not running.") }
      try input.fileHandleForWriting.write(contentsOf: Data("open \(port)\n".utf8))
      processLock.unlock()
    } catch {
      processLock.unlock()
      throw error
    }
    guard try readReply(timeout: 7) == "ok \(port)" else {
      throw CableSharingError(
        "Cable host could not open port \(port). Check occupied ports or restart the session.")
    }
  }

  private func readReply(timeout: TimeInterval) throws -> String {
    guard received.wait(timeout: .now() + timeout) == .success,
      let reply = response.withValue({ value in
        defer { value = nil }
        return value
      })
    else {
      stop()
      throw CableSharingError("Cable host reply timed out or SSH ended.")
    }
    return reply
  }

  private func consume(_ data: Data) {
    guard !data.isEmpty, buffer.count + data.count <= 1024 else {
      response.set("error invalid host response")
      received.signal()
      return
    }
    buffer.append(data)
    while let newline = buffer.firstIndex(of: 10) {
      response.set(String(data: buffer[..<newline], encoding: .utf8))
      buffer.removeSubrange(...newline)
      received.signal()
    }
  }

  func stop() {
    processLock.lock()
    defer { processLock.unlock() }
    guard !stopped else { return }
    stopped = true
    output.fileHandleForReading.readabilityHandler = nil
    try? input.fileHandleForWriting.close()
    if process.isRunning { process.terminate() }
    received.signal()
    let child = process
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.75) {
      if child.isRunning { _ = kill(child.processIdentifier, SIGKILL) }
    }
  }
}
