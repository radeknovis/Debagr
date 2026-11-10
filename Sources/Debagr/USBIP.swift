import Darwin
import Foundation
import IOKit

struct USBIPDevice: Codable, Equatable {
  let serial: String
  let name: String
  let vendorID: UInt16
  let productID: UInt16
  let locationID: UInt32

  var isAppleMobileDevice: Bool {
    vendorID == 0x05ac
      && ["iphone", "ipad", "ipod", "vision"].contains(where: name.lowercased().contains)
  }

  var inventoryName: String {
    let value = String(name.prefix(80)).components(separatedBy: .newlines).joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "Apple mobile device" : value
  }

  static func connected() throws -> [USBIPDevice] {
    var iterator: io_iterator_t = 0
    let status = IOServiceGetMatchingServices(
      kIOMainPortDefault,
      IOServiceMatching("IOUSBHostDevice"), &iterator)
    guard status == KERN_SUCCESS else {
      throw USBIPError.invalid("USB inventory failed: \(status)")
    }
    defer { IOObjectRelease(iterator) }
    var devices: [USBIPDevice] = []
    while case let service = IOIteratorNext(iterator), service != 0 {
      defer { IOObjectRelease(service) }
      func property(_ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
          .takeRetainedValue()
      }
      guard let serial = property("USB Serial Number") as? String, !serial.isEmpty,
        let vendor = property("idVendor") as? NSNumber,
        let product = property("idProduct") as? NSNumber,
        let location = property("locationID") as? NSNumber
      else { continue }
      devices.append(
        USBIPDevice(
          serial: serial,
          name: property("USB Product Name") as? String ?? "USB device",
          vendorID: vendor.uint16Value, productID: product.uint16Value,
          locationID: location.uint32Value))
    }
    return devices.sorted { $0.serial < $1.serial }
  }
}

enum USBIPError: LocalizedError {
  case invalid(String)
  var errorDescription: String? {
    switch self {
    case .invalid(let message): return message
    }
  }
}

/// Explicit foreground commands only. No PATH lookup or implicit privilege elevation.
struct USBIPCommand {
  let action: String
  let values: [String: String]

  init(_ arguments: [String]) throws {
    guard let action = arguments.first,
      [
        "help", "devices", "probe", "list", "attach", "serve", "discover", "advertise",
        "run-session", "stop-session",
      ].contains(
        action)
    else {
      throw USBIPError.invalid(
        "Use --usbip help, devices, probe, list, attach, serve, discover, or advertise.")
    }
    self.action = action
    var values: [String: String] = [:]
    var index = 1
    while index < arguments.count {
      let key = arguments[index]
      guard index + 1 < arguments.count, key.hasPrefix("--"), values[key] == nil,
        !arguments[index + 1].hasPrefix("--"), !arguments[index + 1].isEmpty
      else {
        throw USBIPError.invalid("Missing or duplicate USB/IP option: \(key)")
      }
      values[key] = arguments[index + 1]
      index += 2
    }
    let required: Set<String>
    switch action {
    case "run-session", "stop-session": required = ["--request"]
    case "list": required = ["--tool", "--remote"]
    case "attach": required = ["--tool", "--remote", "--busid"]
    case "serve": required = ["--tool", "--listen", "--peer", "--serial"]
    default: required = []
    }
    guard Set(values.keys) == required else {
      throw USBIPError.invalid(
        "\(action) requires exactly: \(required.sorted().joined(separator: " "))")
    }
    for key in ["--remote", "--listen", "--peer"] {
      if let address = values[key], !NetworkSupport.isAllowedPrivateVPNIPv4(address) {
        throw USBIPError.invalid("\(key) requires an explicit private VPN IPv4 address.")
      }
    }
    if let bus = values["--busid"],
      bus.range(of: #"^[0-9]+-[0-9]+(\.[0-9]+)*$"#, options: .regularExpression) == nil
    {
      throw USBIPError.invalid("Invalid USB/IP bus ID.")
    }
    if let tool = values["--tool"], !tool.hasPrefix("/") {
      throw USBIPError.invalid("--tool must be an absolute executable path.")
    }
    self.values = values
  }

  func backendArguments(devices: [USBIPDevice] = [], savedExports: Data? = nil) throws -> [String] {
    switch action {
    case "list": return ["-r", values["--remote"]!, "list"]
    case "attach": return ["-r", values["--remote"]!, "attach", "--busid", values["--busid"]!]
    case "serve":
      let matches = devices.filter { $0.serial == values["--serial"] }
      guard matches.count == 1, let device = matches.first else {
        throw USBIPError.invalid("Select exactly one connected USB serial from --usbip devices.")
      }
      guard device.vendorID == 0x05ac else {
        throw USBIPError.invalid(
          "This pairing fallback only exports explicitly selected Apple devices.")
      }
      if let savedExports {
        guard
          let catalog = try JSONSerialization.jsonObject(with: savedExports) as? [[String: Any]],
          catalog.count == 1, let saved = catalog.first,
          (saved["vendor"] as? NSNumber)?.uint16Value == device.vendorID,
          (saved["product"] as? NSNumber)?.uint16Value == device.productID,
          (saved["location"] as? NSNumber)?.uint32Value == device.locationID
        else {
          throw USBIPError.invalid(
            "Longcable's saved device catalog differs from this device or USB port. Reconnect at the original port or review its saved configuration. Debagr has not changed it."
          )
        }
        // Reuse the single verified target, including its label and optional metadata.
        return [values["--listen"]!, values["--peer"]!]
      }
      return [
        values["--listen"]!, values["--peer"]!,
        String(format: "%04x", device.vendorID), String(format: "%04x", device.productID),
        String(format: "%08x", device.locationID), "debagr",
      ]
    default: return []
    }
  }

  static var probeURL: URL {
    URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
      .deletingLastPathComponent().appendingPathComponent("USBIPProbe")
  }

  func run() throws {
    switch action {
    case "run-session":
      try USBIPSessionSupervisor.run(requestURL: URL(fileURLWithPath: values["--request"]!))
    case "stop-session":
      try USBIPSessionSupervisor.stop(requestURL: URL(fileURLWithPath: values["--request"]!))
    case "help": print(Self.help)
    case "discover", "advertise":
      let discovery = DebagrPeerDiscovery()
      discovery.start()
      if action == "advertise" {
        RunLoop.main.run()
      } else {
        let found = LockedValue<[DiscoveredDebagrPeer]>([])
        discovery.onChange = { peers, _ in found.set(peers) }
        discovery.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(9))
        discovery.stop()
        let result = found.get().map {
          [
            "name": $0.peer.name, "roles": $0.peer.roles.joined(separator: ","),
            "machineRole": $0.peer.machineRole?.rawValue ?? "unconfigured",
            "nodeID": $0.peer.nodeID, "pairedNodeID": $0.peer.pairedNodeID ?? "",
            "address": $0.address, "source": $0.source,
          ]
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
      }
    case "devices":
      let data = try JSONEncoder().encode(USBIPDevice.connected())
      print(String(decoding: data, as: UTF8.self))
    case "probe": try Self.replaceProcess(path: Self.probeURL.path, arguments: [])
    default:
      if action == "attach" || action == "serve" {
        guard geteuid() == 0 else {
          throw USBIPError.invalid(
            "\(action) requires root. Run this explicit command with sudo in Terminal.")
        }
      }
      if action == "attach" {
        let probe = Process()
        probe.executableURL = Self.probeURL
        // Keep the capability result on stderr; stdout belongs to the backend.
        probe.standardOutput = FileHandle.standardError
        try probe.run()
        probe.waitUntilExit()
        guard probe.terminationStatus == 0 else {
          throw USBIPError.invalid(
            "USB host controller unavailable. Inspect --usbip probe as root on this Mac.")
        }
      }
      let catalogURL = URL(fileURLWithPath: "/Library/Application Support/Longcable/targets.json")
      let savedExports =
        action == "serve" && FileManager.default.fileExists(atPath: catalogURL.path)
        ? try Data(contentsOf: catalogURL) : nil
      let arguments = try backendArguments(
        devices: action == "serve" ? USBIPDevice.connected() : [], savedExports: savedExports)
      try Self.replaceProcess(path: values["--tool"]!, arguments: arguments)
    }
  }

  private static func replaceProcess(path: String, arguments: [String]) throws {
    guard FileManager.default.isExecutableFile(atPath: path) else {
      throw USBIPError.invalid("Executable not found: \(path)")
    }
    // exec preserves foreground signals and the backend exit code; no orphan root child.
    let strings = ([path] + arguments).map { strdup($0) }
    defer { for string in strings { free(string) } }
    var argv = strings + [nil]
    argv.withUnsafeMutableBufferPointer { _ = execv(path, $0.baseAddress!) }
    throw USBIPError.invalid("Unable to execute \(path): \(String(cString: strerror(errno)))")
  }

  static let help = """
    Experimental USB/IP pairing fallback:
      debagr --usbip devices
      debagr --usbip discover
      debagr --usbip advertise
      sudo debagr --usbip probe
      debagr --usbip list --tool /absolute/path/usbip-macos --remote <VPN-IPv4>
      sudo debagr --usbip attach --tool /absolute/path/usbip-macos --remote <VPN-IPv4> --busid <ID-from-list>
      sudo debagr --usbip serve --tool /absolute/path/longcable-server --listen <local-VPN-IPv4> --peer <client-VPN-IPv4> --serial <USB-serial>

    Install the backends separately. The server requires the SET_CONFIGURATION fix.
    Both run in the foreground; Ctrl-C detaches/releases the device.
    USB/IP has no encryption: use VPN addresses and a peer restricted by your VPN ACL.
    The client capability probe requires root and does not prove device readiness.
    After attaching, verify wired/connected CoreDevice transport and --status.
    """
}
