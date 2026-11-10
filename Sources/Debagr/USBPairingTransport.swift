import Darwin
import Foundation

struct USBPairingError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
  init(_ message: String) { self.message = message }
}

struct ForwardedUSBDevice: Equatable, Identifiable {
  let address: String
  let name: String
  let serial: String
  let state: Int
  let serverSerial: String
  let connectionID: String
  let boundConnectionID: String
  var id: String { address }
  var isAvailable: Bool { state == 1 }
  var isOwnedByClient: Bool {
    state == 3 && !connectionID.isEmpty && connectionID == boundConnectionID
  }

  static func normalizedSerial(_ value: String) -> String {
    value.replacingOccurrences(of: "-", with: "").lowercased()
  }
}

/// Parses only the hub reached through our loopback tunnel, never a discovered LAN hub.
struct VirtualHereState {
  let devices: [ForwardedUSBDevice]

  static func decode(_ xml: String, port: UInt16) throws -> Self {
    guard let data = xml.data(using: .utf8), data.count < 2_000_000,
      !xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
      !xml.localizedCaseInsensitiveContains("<!ENTITY")
    else { throw USBPairingError("VirtualHere returned an invalid device inventory.") }
    let delegate = StateParser(port: port)
    let parser = XMLParser(data: data)
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    guard parser.parse(), delegate.hasRoot else {
      throw USBPairingError("VirtualHere returned an unreadable device inventory.")
    }
    guard Set(delegate.devices.map(\.id)).count == delegate.devices.count else {
      throw USBPairingError("The USB device inventory contains ambiguous addresses.")
    }
    return Self(devices: delegate.devices)
  }

  private final class StateParser: NSObject, XMLParserDelegate {
    let port: UInt16
    var hasRoot = false
    var devices: [ForwardedUSBDevice] = []
    private var connection: [String: String] = [:]

    init(port: UInt16) { self.port = port }

    func parser(
      _ parser: XMLParser, didStartElement elementName: String,
      namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]
    ) {
      if elementName == "state" { hasRoot = true }
      if elementName == "server" { connection = [:] }
      if elementName == "connection" { connection = attributes }
      guard elementName == "device",
        connection["host"] == "127.0.0.1", connection["port"] == String(port),
        connection["state"] == "3",
        let hostname = connection["hostname"], Self.safeComponent(hostname),
        let server = connection["serverSerial"], !server.isEmpty,
        attributes["idVendor"] == "1452",
        let product = attributes["product"],
        product.localizedCaseInsensitiveContains("iphone")
          || product.localizedCaseInsensitiveContains("ipad"),
        let address = attributes["address"], UInt32(address) != nil,
        let serial = attributes["deviceSerial"],
        serial.range(of: "^[A-Fa-f0-9-]{16,64}$", options: .regularExpression) != nil,
        let state = Int(attributes["state"] ?? "")
      else { return }
      devices.append(
        ForwardedUSBDevice(
          address: "\(hostname).\(address)", name: product,
          serial: serial, state: state, serverSerial: server,
          connectionID: connection["uuid"] ?? "",
          boundConnectionID: attributes["boundConnectionUUID"] ?? ""))
    }

    private static func safeComponent(_ value: String) -> Bool {
      value.range(of: "^[A-Za-z0-9][A-Za-z0-9._:-]{0,253}$", options: .regularExpression) != nil
    }
  }
}

protocol USBCommandRunning: AnyObject {
  func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> String
  func cancel()
}

/// All output stays in private temporary files; pairing payloads never go to application logs.
final class USBCommandRunner: USBCommandRunning {
  private let active = LockedValue<Process?>(nil)
  private let cancelled = LockedValue(false)

  func cancel() {
    cancelled.set(true)
    if let process = active.get(), process.isRunning { process.terminate() }
  }

  func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> String {
    guard !cancelled.get() else { throw CancellationError() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "debagr-usb-\(UUID())")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("output")
    FileManager.default.createFile(
      atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
    let file = try FileHandle(forWritingTo: output)
    defer { try? file.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = file
    process.standardError = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    active.set(process)
    defer { active.set(nil) }
    try process.run()
    if cancelled.get() { process.terminate() }
    let deadline = Date().addingTimeInterval(timeout)
    while finished.wait(timeout: .now() + 0.1) != .success {
      if cancelled.get() || Date() >= deadline {
        process.terminate()
        if finished.wait(timeout: .now() + 0.75) != .success {
          kill(process.processIdentifier, SIGKILL)
          _ = finished.wait(timeout: .now() + 1)
        }
        if cancelled.get() { throw CancellationError() }
        throw USBPairingError(
          "The connection command timed out. Check the Client Mac and try again.")
      }
    }
    guard !cancelled.get() else { throw CancellationError() }
    guard process.terminationStatus == 0 else {
      throw USBPairingError(
        "\(URL(fileURLWithPath: executable).lastPathComponent) could not complete the request (exit \(process.terminationStatus)). Check its setup, permissions, and connection."
      )
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
    guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max < 2_000_000 else {
      throw USBPairingError("The connection command returned too much output.")
    }
    let data = try Data(contentsOf: output)
    guard data.count < 2_000_000, let text = String(data: data, encoding: .utf8) else {
      throw USBPairingError("The connection command returned invalid output.")
    }
    return text
  }
}

protocol USBTunnel: AnyObject {
  var port: UInt16 { get }
  var isRunning: Bool { get }
  func stop()
}

final class USBSSHTunnel: USBTunnel {
  let port: UInt16
  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  var isRunning: Bool { process.isRunning }

  static func validateHost(_ host: String) throws {
    guard host.range(of: "^[A-Za-z0-9][A-Za-z0-9._@-]{0,199}$", options: .regularExpression) != nil,
      host.filter({ $0 == "@" }).count <= 1, !host.hasSuffix("@")
    else {
      throw USBPairingError(
        "Enter an SSH alias or user@hostname for the Client Mac, without spaces or SSH options.")
    }
  }

  static var sshOptions: [String] {
    [
      "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
      "-o", "ConnectTimeout=8", "-o", "ForwardAgent=no", "-o", "ControlMaster=no",
      "-o", "ControlPath=none", "-o", "RemoteCommand=none",
      "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=2",
    ]
  }

  init(host: String) throws {
    try Self.validateHost(host)
    port = try Self.availablePort()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
    process.arguments =
      Self.sshOptions + [
        "-o", "ExitOnForwardFailure=yes", "-L",
        "127.0.0.1:\(port):127.0.0.1:7575", host,
        "printf 'DEBAGR_USB_READY\\n'; exec /bin/cat",
      ]
    // Keeping stdin open ties the remote command and tunnel to this app's lifetime.
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    let ready = LockedValue(false)
    let buffered = LockedValue(Data())
    let finished = DispatchSemaphore(value: 0)
    output.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
        return
      }
      var accumulated = buffered.get()
      accumulated.append(data)
      buffered.set(accumulated)
      if String(data: accumulated, encoding: .utf8)?.contains("DEBAGR_USB_READY\n") == true {
        ready.set(true)
        finished.signal()
        handle.readabilityHandler = nil
      }
    }
    process.terminationHandler = { _ in finished.signal() }
    do {
      try process.run()
      guard finished.wait(timeout: .now() + 12) == .success, ready.get(), process.isRunning else {
        throw USBPairingError(
          "SSH could not open the USB tunnel. Enable Remote Login on the Client Mac and confirm key-based access and its host key in Terminal first."
        )
      }
    } catch {
      stop()
      throw error
    }
  }

  func stop() {
    try? input.fileHandleForWriting.close()
    output.fileHandleForReading.readabilityHandler = nil
    guard process.isRunning else { return }
    process.terminate()
    let process = process
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.75) {
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
  }

  deinit { stop() }

  private static func availablePort() throws -> UInt16 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw USBPairingError("Could not allocate a local USB tunnel port.") }
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
    }
    guard result == 0, named == 0 else {
      throw USBPairingError("Could not allocate a local USB tunnel port.")
    }
    return UInt16(bigEndian: address.sin_port)
  }
}
