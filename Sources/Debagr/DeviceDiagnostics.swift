import Foundation

struct DiagnosticFailure: Error {
  let underlying: Error
  let checks: [String: Any]
  let recoverySteps: [String]
}

enum DeviceDiagnostics {
  static func checks(deviceIdentifier: String, store: ManagedDeviceStore = ManagedDeviceStore())
    -> [String: Any]
  {
    var checks: [String: Any] = [:]
    func record(_ name: String, _ body: () throws -> String) {
      do { checks[name] = ["status": "passed", "message": try body()] } catch {
        checks[name] = ["status": "failed", "message": error.localizedDescription]
      }
    }
    let tools = ProductSupport.developerToolsAvailable
    checks["developerTools"] = [
      "status": tools ? "passed" : "failed",
      "message": tools ? "devicectl available" : "Install Xcode and select its developer directory",
    ]
    var configured: ConfiguredDevice?
    record("savedConfiguration") {
      configured = try store.load()
      return configured == nil
        ? "No managed remote device; local deployment is still available"
        : "Saved configuration is valid"
    }
    record("networkInterface") {
      _ = try NetworkSupport.resolveInterface(named: configured?.interfaceName ?? "auto")
      return "Wi-Fi/Ethernet interface has an IPv4 address"
    }
    if tools {
      record("appleInventory") {
        let devices = try CoreDeviceInventory.load(pairedMacNodeID: "local")
        guard devices.contains(where: { $0.identity.value == deviceIdentifier }) else {
          throw CLIError.deviceNotFound
        }
        return "Selected device is present in Apple's inventory; readiness is checked separately"
      }
    } else {
      checks["appleInventory"] = ["status": "skipped", "message": "Developer tools unavailable"]
    }
    if let configured, configured.deviceIdentifier == deviceIdentifier,
      let provider = NetworkProvider(rawValue: configured.profile.provider)
    {
      checks["relayEnabled"] = [
        "status": configured.enabled ? "passed" : "failed",
        "message": configured.enabled
          ? "Remote relay enabled" : "Choose Resume Wireless Connection in the Debagr menu",
      ]
      record("vpnPeer") {
        _ = try provider.resolvePeer(configured.peerName)
        return provider.discoversPeers
          ? "Selected VPN peer is online"
          : "Manual VPN address is valid; peer connectivity needs readiness verification"
      }
    } else {
      checks["vpnPeer"] = ["status": "skipped", "message": "No matching remote configuration"]
    }
    return checks
  }

  static func recoverySteps(from checks: [String: Any], underlyingError: Error) -> [String] {
    var steps: [String] = []

    for (name, value) in checks where isCheckFailed(value) {
      switch name {
      case "developerTools":
        steps.append("Install Xcode and select its developer directory")
      case "savedConfiguration":
        steps.append("Open Debagr on the Builder Mac and complete device setup")
      case "networkInterface":
        steps.append("Connect the Builder Mac to Wi-Fi or Ethernet")
      case "appleInventory":
        steps.append(
          "Connect the Target Device by USB, unlock it, approve Apple trust, and enable Developer Mode"
        )
      case "relayEnabled":
        steps.append("Choose Resume Wireless Connection in the Debagr menu-bar app")
      case "vpnPeer":
        steps.append("Ensure both Mac and device are connected to the private VPN")
      default:
        steps.append("Resolve the \(name) check failure")
      }
    }

    if steps.isEmpty {
      switch underlyingError {
      case DeviceDeploymentError.deviceLocked:
        steps.append("Unlock the Target Device and keep it awake")
      case DeviceDeploymentError.timedOut:
        steps.append("Retry with a longer --timeout; the device may be slow to respond")
      default:
        steps.append(
          "Open Debagr on the paired Builder and connect the configured device. Re-pair over USB if trust was revoked."
        )
      }
    }

    return steps
  }

  private static func isCheckFailed(_ value: Any) -> Bool {
    guard let dict = value as? [String: Any],
      let status = dict["status"] as? String
    else { return false }
    return status == "failed"
  }
}
