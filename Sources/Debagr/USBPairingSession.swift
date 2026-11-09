import Foundation

struct USBNearbyService: Codable, Equatable, Identifiable {
  let host: String
  let name: String
  var id: String { host }
}

struct USBServiceInventory: Codable {
  var schemaVersion = 1
  let services: [USBNearbyService]
}

/// Serial-queue owned. The UI only cancels the command runner from another queue.
final class USBPairingSession {
  static let clientPath =
    "/Applications/VirtualHereUniversal.app/Contents/MacOS/VirtualHereUniversal"
  static let nearbyDebagr = "/Applications/Debagr.app/Contents/MacOS/Debagr"
  let runner: USBCommandRunning
  private let makeTunnel: (String) throws -> USBTunnel
  private let acquireLease: () throws -> AnyObject
  private var lease: AnyObject?
  private var tunnel: USBTunnel?
  private var host = ""
  private var addedHub: String?
  private var selected: ForwardedUSBDevice?
  private var claimRequested = false
  private var paired: TargetDevice?
  private var wirelessConfiguration: (device: ConfiguredDevice, serviceHost: String)?
  private var port: UInt16 { tunnel?.port ?? 0 }

  init(
    runner: USBCommandRunning = USBCommandRunner(),
    makeTunnel: @escaping (String) throws -> USBTunnel = { try USBSSHTunnel(host: $0) },
    acquireLease: @escaping () throws -> AnyObject = { try RelayLease(port: 0) }
  ) {
    self.runner = runner
    self.makeTunnel = makeTunnel
    self.acquireLease = acquireLease
  }

  func prepare(host: String) throws -> [ForwardedUSBDevice] {
    try USBSSHTunnel.validateHost(host)
    guard tunnel == nil else {
      throw USBPairingError("Stop the current USB session before connecting another Mac.")
    }
    self.host = host
    lease = try acquireLease()
    do {
      let list: String
      do { list = try api("LIST") } catch {
        throw USBPairingError(
          "Install and open VirtualHere Client on this Builder, finish its driver setup, and try again. Debagr could not reach its control interface."
        )
      }
      guard list.contains("Auto-Use All currently off") else {
        throw USBPairingError(
          "Turn off Auto-Use All in VirtualHere before starting a device-specific session.")
      }
      let listeners = try remote(["/usr/sbin/netstat", "-an", "-p", "tcp"], timeout: 10)
      try Self.validateServerListeners(listeners)
      _ = try services()
      tunnel = try makeTunnel(host)
      let hub = "127.0.0.1:\(port)"
      addedHub = hub
      _ = try api("MANUAL HUB ADD,\(hub)")
      return try devices()
    } catch {
      try? stop()
      throw error
    }
  }

  func devices() throws -> [ForwardedUSBDevice] {
    try requireTunnel()
    return try VirtualHereState.decode(api("GET CLIENT STATE"), port: port).devices
  }

  func attach(_ device: ForwardedUSBDevice) throws {
    try requireTunnel()
    guard let current = try devices().first(where: { $0.id == device.id }),
      current.serial == device.serial, current.serverSerial == device.serverSerial,
      current.isAvailable
    else {
      throw USBPairingError(
        "This iPhone is no longer available, or is being used by another client. Refresh the device list."
      )
    }
    selected = current
    // Record the attempt before IPC: a timeout can happen after the backend accepted USE.
    claimRequested = true
    _ = try api("USE,\(current.address)")
  }

  func pair() throws -> TargetDevice {
    try requireTunnel()
    guard let selected,
      let current = try devices().first(where: { $0.id == selected.id }),
      current.serial == selected.serial, current.serverSerial == selected.serverSerial,
      current.isOwnedByClient,
      try locallyAttached(serial: selected.serial)
    else {
      throw USBPairingError(
        "The forwarded iPhone has not appeared as a USB device on this Builder yet. Wait for VirtualHere, keep the phone unlocked, then check again."
      )
    }
    let identifier = selected.serial
    _ = try deviceCommand(
      ["manage", "pair", "--device", identifier, "--timeout", "15"], timeout: 17)
    let inventory = try deviceCommand(["list", "devices", "--timeout", "8"], timeout: 10)
    let devices = try CoreDeviceInventory.decodeDevices(from: inventory, pairedMacNodeID: "local")
    guard
      let device = devices.first(where: {
        ForwardedUSBDevice.normalizedSerial($0.identity.value)
          == ForwardedUSBDevice.normalizedSerial(identifier)
      })
    else {
      throw USBPairingError(
        "Apple has not confirmed this iPhone's identity. Approve Trust on the phone and retry pairing."
      )
    }
    let deployer = DeviceDeployer(run: { [self] arguments, timeout in
      try deviceCommand(arguments, timeout: timeout + 2)
    })
    try deployer.checkReady(deviceIdentifier: device.identity.value)
    paired = device
    return device
  }

  func services() throws -> [USBNearbyService] {
    let text = try remote(
      [Self.nearbyDebagr, "--usb-services", "--json", "--timeout", "3"], timeout: 8)
    let inventory = try JSONDecoder().decode(USBServiceInventory.self, from: Data(text.utf8))
    guard inventory.schemaVersion == 1 else {
      throw USBPairingError("Update Debagr on the Client Mac to use USB pairing.")
    }
    return inventory.services
  }

  func finish(provider: NetworkProvider, address: String, serviceHost: String) throws
    -> ConfiguredDevice
  {
    // A disk-write or hub-removal failure must remain retryable after USB has ended.
    if let completed = wirelessConfiguration {
      guard completed.device.profile.provider == provider.rawValue,
        completed.device.profile.peerIP == address, completed.serviceHost == serviceHost
      else {
        throw USBPairingError(
          "USB has already ended. Restore the previous wireless details to retry saving, or stop this session and set up again."
        )
      }
      try stop()
      return completed.device
    }
    try requireTunnel()
    guard let paired, let selected else {
      throw USBPairingError("Complete Apple pairing before switching to wireless.")
    }
    guard provider.allowsAddress(address), !serviceHost.isEmpty else {
      throw USBPairingError("Choose the iPhone's private VPN address and its wireless service.")
    }
    let output = try remote(
      [
        Self.nearbyDebagr, "--usb-profile", "--json",
        "--provider", provider.rawValue, "--peer", address, "--bonjour-host", serviceHost,
        "--timeout", "8",
      ], timeout: 12)
    let profile = try JSONDecoder().decode(DeviceProfile.self, from: Data(output.utf8))
    try profile.validate()
    guard profile.provider == provider.rawValue, profile.peerIP == address else {
      throw USBPairingError("The Client Mac returned a profile for a different network endpoint.")
    }
    let configuration = ConfiguredDevice(
      deviceIdentifier: paired.identity.value,
      displayName: paired.displayName, peerName: address, profile: profile, kind: paired.kind)
    try configuration.validate()
    try releaseDevice()
    guard try !locallyAttached(serial: selected.serial) else {
      throw USBPairingError(
        "The USB device is still attached to this Builder. Wait for it to disconnect, then try the wireless handoff again."
      )
    }
    wirelessConfiguration = (configuration, serviceHost)
    try stop()
    return configuration
  }

  func stop() throws {
    var firstError: Error?
    do { try releaseDevice() } catch { firstError = error }
    // Removing only our hub also prevents the client from reconnecting to this tunnel.
    if let addedHub {
      do {
        _ = try api("MANUAL HUB REMOVE,\(addedHub)")
        self.addedHub = nil
      } catch { if firstError == nil { firstError = error } }
    }
    tunnel?.stop()
    tunnel = nil
    lease = nil
    if let firstError { throw firstError }
  }

  func cancel() { runner.cancel() }

  /// Cleanup gets a fresh runner after cancellation so STOP/REMOVE can still reach the backend.
  func cleanupAfterCancellation() throws {
    let cleanup = USBPairingSession(runner: USBCommandRunner())
    cleanup.tunnel = tunnel
    cleanup.addedHub = addedHub
    cleanup.selected = selected
    cleanup.claimRequested = claimRequested
    defer {
      tunnel = nil
      addedHub = nil
      lease = nil
    }
    try cleanup.stop()
  }

  private func releaseDevice() throws {
    guard claimRequested, let selected else { return }
    let inventory = try VirtualHereState.decode(api("GET CLIENT STATE"), port: port)
    if let current = inventory.devices.first(where: { $0.id == selected.id }),
      current.serial == selected.serial, current.serverSerial == selected.serverSerial
    {
      if current.isOwnedByClient {
        _ = try api("STOP USING,\(selected.address)")
      } else if current.state != 1 {
        throw USBPairingError(
          "USB ownership changed. Debagr closed its tunnel without stopping another client's device."
        )
      }
    }
    claimRequested = false
  }

  private func requireTunnel() throws {
    guard tunnel?.isRunning == true else {
      throw USBPairingError(
        "The SSH connection to the Client Mac ended. Stop this session and connect again.")
    }
  }

  private func api(_ command: String) throws -> String {
    let result = try runner.run(Self.clientPath, ["-t", command], timeout: 7)
    if command != "LIST" && command != "GET CLIENT STATE",
      result.trimmingCharacters(in: .whitespacesAndNewlines) != "OK"
    {
      throw USBPairingError(
        "VirtualHere did not confirm the USB session change. Check its device status and retry.")
    }
    return result
  }

  private func remote(_ arguments: [String], timeout: TimeInterval) throws -> String {
    try USBSSHTunnel.validateHost(host)
    return try runner.run(
      "/usr/bin/ssh",
      USBSSHTunnel.sshOptions + [
        host,
        arguments.map(Self.shellQuote).joined(separator: " "),
      ], timeout: timeout)
  }

  static func shellQuote(_ argument: String) -> String {
    "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func validateServerListeners(_ output: String) throws {
    let addresses = output.split(separator: "\n").compactMap { line -> String? in
      let fields = line.split(whereSeparator: \.isWhitespace)
      guard fields.count >= 6, fields[0].hasPrefix("tcp"), fields.contains("LISTEN"),
        fields[3].hasSuffix(".7575")
      else { return nil }
      return String(fields[3])
    }
    guard addresses.contains("127.0.0.1.7575"),
      addresses.allSatisfy({ $0 == "127.0.0.1.7575" || $0 == "::1.7575" })
    else {
      throw USBPairingError(
        "On the Client Mac, configure VirtualHere Server with NetworkInterface=127.0.0.1 and restart it. Debagr requires USB port 7575 to listen only on loopback; this VirtualHere setting requires a server license."
      )
    }
  }

  private func locallyAttached(serial: String) throws -> Bool {
    let output = try runner.run("/usr/sbin/ioreg", ["-p", "IOUSB", "-l", "-a"], timeout: 5)
    let plist = try PropertyListSerialization.propertyList(from: Data(output.utf8), format: nil)
    return Self.containsUSBSerial(serial, in: plist)
  }

  static func containsUSBSerial(_ serial: String, in value: Any) -> Bool {
    if let object = value as? [String: Any] {
      if let found = object["USB Serial Number"] as? String,
        (object["idVendor"] as? Int) == 1452,
        ForwardedUSBDevice.normalizedSerial(found) == ForwardedUSBDevice.normalizedSerial(serial)
      {
        return true
      }
      return object.values.contains { containsUSBSerial(serial, in: $0) }
    }
    return (value as? [Any])?.contains { containsUSBSerial(serial, in: $0) } ?? false
  }

  private func deviceCommand(_ arguments: [String], timeout: TimeInterval) throws -> Data {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "debagr-usb-apple-\(UUID())")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("result.json")
    _ = try runner.run(
      "/usr/bin/xcrun", ["devicectl"] + arguments + ["--json-output", output.path], timeout: timeout
    )
    return try Data(contentsOf: output)
  }

  deinit { tunnel?.stop() }
}
