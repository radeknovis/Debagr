import Foundation

enum AgentCLI {
  static let recovery =
    "Open Debagr on the paired Builder and connect the configured device. Keep the device unlocked, on Wi-Fi, with its selected VPN connected. Re-pair over USB if trust was revoked."

  static func waitUntilReady(
    deviceIdentifier: String, timeout: TimeInterval,
    check: (String, TimeInterval) throws -> Void = {
      try DeviceDeployer().checkReady(deviceIdentifier: $0, timeout: $1)
    }
  ) throws {
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while true {
      let remaining = deadline - ProcessInfo.processInfo.systemUptime
      guard remaining > 0 else { throw DeviceDeploymentError.timedOut }
      do {
        try check(deviceIdentifier, min(5, remaining))
        return
      } catch {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 1 else { throw error }
        Thread.sleep(forTimeInterval: min(1, remaining))
      }
    }
  }

  static func run(_ options: CommandLineOptions) throws {
    let command = options.agentCommand!
    if command == "usb-services" || command == "usb-profile" {
      try USBProfileTransfer.run(options)
      return
    }
    let store = ManagedDeviceStore()
    let configured = try store.load()
    switch command {
    case "devices":
      var devices = try CoreDeviceInventory.load(pairedMacNodeID: "local")
      if let configured,
        !devices.contains(where: { $0.identity.value == configured.deviceIdentifier })
      {
        devices.append(
          TargetDevice(
            identity: .apple(pairedMacNodeID: "local", identifier: configured.deviceIdentifier),
            displayName: configured.displayName, kind: configured.kind ?? .unknown,
            service: nil, status: .unavailable))
      }
      emit(
        [
          "devices": devices.map { device in
            [
              "deviceIdentifier": device.identity.value, "name": device.displayName,
              "kind": device.kind.rawValue, "inventoryState": device.status.rawValue,
              "configured": configured?.deviceIdentifier == device.identity.value,
              "remoteEnabled": configured?.deviceIdentifier == device.identity.value
                && configured?.enabled == true,
            ] as [String: Any]
          }
        ], operation: command, options: options)
    case "status", "diagnose":
      let identifier = options.deviceIdentifier!
      try waitUntilReady(deviceIdentifier: identifier, timeout: options.timeout)
      emit(
        [
          "state": "ready", "deviceIdentifier": identifier,
          "configured": configured?.deviceIdentifier == identifier,
          "developerToolsAvailable": ProductSupport.developerToolsAvailable,
          "tailscaleInstalled": TailscaleClient.installedExecutablePath() != nil,
          "networkProvider": configured?.profile.provider ?? "none",
        ],
        operation: command, options: options)
    case "configure":
      let identifier = options.deviceIdentifier!
      let devices = try CoreDeviceInventory.load(pairedMacNodeID: "local")
      guard let device = devices.first(where: { $0.identity.value == identifier }) else {
        throw CLIError.missingDevice
      }
      let peer = try options.provider.resolvePeer(options.peerName!)
      let profile: DeviceProfile
      if let host = options.bonjourHost {
        profile = try DirectDeviceApplication.capturedProfile(
          peerName: options.peerName!, host: host, timeout: options.timeout,
          provider: options.provider)
      } else if let imported = try ProfileStore(url: options.profileURL).load() {
        profile = imported
      } else {
        throw CLIError.invalidDirectDeviceOptions
      }
      guard profile.peerIP == peer.ipAddress, profile.provider == options.provider.rawValue else {
        throw CLIError.invalidDirectDeviceOptions
      }
      try store.save(
        ConfiguredDevice(
          deviceIdentifier: identifier, displayName: device.displayName,
          peerName: peer.dnsName.isEmpty ? peer.ipAddress : peer.dnsName,
          interfaceName: options.interfaceName, profile: profile, kind: device.kind))
      emit(
        [
          "state": "configured", "deviceIdentifier": identifier,
          "nextAction":
            "Open Debagr on this Mac. Configuration does not prove readiness; run --status.",
        ],
        operation: command, options: options)
    default: throw CLIError.conflictingCommands
    }
  }

  static func emit(_ result: [String: Any], operation: String, options: CommandLineOptions) {
    if options.json {
      writeJSON(["schemaVersion": 1, "ok": true, "operation": operation, "result": result])
    } else if let devices = result["devices"] as? [[String: Any]] {
      for device in devices {
        print("\(device["name"]!) — \(device["deviceIdentifier"]!) (\(device["inventoryState"]!))")
      }
    } else {
      print("\(result["state"] ?? "Completed"): \(result["deviceIdentifier"] ?? "")")
    }
  }

  static func failure(_ error: Error, operation: String) -> (object: [String: Any], exitCode: Int32)
  {
    var code = "command_failed"
    var message = "The device command failed."
    var recovery = "Run --diagnose --device <UDID> --json and check Xcode signing and device trust."
    var exitCode: Int32 = 1
    var installed = false
    var bundleIdentifier: String?
    switch error {
    case is CLIError:
      code = "invalid_arguments"
      message = error.localizedDescription
      recovery = "Run --help and select one command with an explicit device."
      exitCode = 64
    case DeviceDeploymentError.invalidApp:
      code = "invalid_app"
      message = error.localizedDescription
      recovery = "Build a signed iphoneos .app on the Builder for this device."
      exitCode = 65
    case DeviceDeploymentError.launchFailed(let identifier):
      code = "launch_failed"
      message = error.localizedDescription
      recovery = "Installation succeeded. Unlock the device and retry launch only using devicectl."
      installed = true
      bundleIdentifier = identifier
    case DeviceDeploymentError.deviceLocked:
      code = "device_locked"
      message = error.localizedDescription
      recovery = "Unlock the selected device and keep it awake, then retry --status."
      exitCode = 2
    case DeviceDeploymentError.commandFailed(let arguments, _):
      if arguments.contains("lockState") {
        code = "device_unavailable"
        recovery = Self.recovery
        exitCode = 2
      } else {
        code = "installation_failed"
        recovery =
          "Check the app's signing, provisioning, available device storage, and device connection before retrying."
      }
    case is TailscaleError:
      code = "tailscale_unavailable"
      message = error.localizedDescription
      recovery = "Connect both endpoints to Tailscale and select the unique peer for this device."
      exitCode = 2
    case is ProfileError:
      code = "invalid_profile"
      message = error.localizedDescription
      recovery =
        "Select a supported provider and the device's private VPN IPv4 address. Public, loopback, link-local, and IPv6 addresses are unsupported."
      exitCode = 64
    case is ManagedDeviceError:
      code = "relay_already_running"
      message = error.localizedDescription
      recovery =
        "Use the existing menu-bar app; stop the old foreground relay before enabling remote deployment."
      exitCode = 2
    case is NetworkSupportError:
      code = "network_unavailable"
      recovery = "Connect the Builder to Wi-Fi or Ethernet."
      exitCode = 2
    default:
      if operation == "status" || operation == "diagnose" {
        code = "device_unavailable"
        recovery = Self.recovery
        exitCode = 2
      }
    }
    var detail: [String: Any] = [
      "code": code, "message": message, "recovery": recovery, "installationConfirmed": installed,
    ]
    if let bundleIdentifier { detail["bundleIdentifier"] = bundleIdentifier }
    if installed { detail["installed"] = true }
    var object: [String: Any] = [
      "schemaVersion": 1, "ok": false, "operation": operation, "error": detail,
    ]
    if operation == "diagnose" {
      object["checks"] = [
        "developerToolsAvailable": ProductSupport.developerToolsAvailable,
        "tailscaleInstalled": TailscaleClient.installedExecutablePath() != nil,
        "remoteConfigured": (try? ManagedDeviceStore().load()) != nil,
        "networkProvider": (try? ManagedDeviceStore().load())?.profile.provider ?? "none",
      ]
    }
    return (object, exitCode)
  }

  static func writeJSON(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
  }
}
