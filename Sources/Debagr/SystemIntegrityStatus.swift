import Darwin
import Foundation

enum SystemIntegrityStatus: String, Codable {
  case enabled, disabled, custom, unknown

  static func parse(_ output: String, exitStatus: Int32 = 0) -> Self {
    guard exitStatus == 0 else { return .unknown }
    let text = output.lowercased()
    if text.contains("custom configuration") { return .custom }
    let lines = text.components(separatedBy: .newlines).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if lines.contains("system integrity protection status: disabled.") { return .disabled }
    if lines.contains("system integrity protection status: enabled.") { return .enabled }
    return .unknown
  }

  static func probe() -> Self {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
    process.arguments = ["status"]
    process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C", "LANG": "C"])
    { _, new in new }
    process.standardInput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let output = Pipe()
    process.standardOutput = output
    do { try process.run() } catch { return .unknown }
    let timeout = DispatchWorkItem {
      if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
    }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: timeout)
    defer { timeout.cancel() }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return parse(String(decoding: data, as: UTF8.self), exitStatus: process.terminationStatus)
  }

  var annotation: String {
    switch self {
    case .disabled: return "SIP off · experimental Builder path"
    case .enabled: return "SIP on · Builder access restricted"
    case .custom: return "SIP customized · check Builder access"
    case .unknown: return "Builder SIP status unavailable"
    }
  }

  var explanation: String {
    switch self {
    case .disabled:
      return
        "SIP is disabled on the Builder, enabling the current experimental root-based USB import path. System protections are reduced. USB capability is checked separately when connecting."
    case .enabled:
      return
        "SIP protects this Builder. The current backend needs an Apple-approved host-controller entitlement, or the experimental SIP-off plus root path. This Debagr build has no such entitlement."
    case .custom:
      return
        "The Builder has a custom SIP configuration. Some protections remain enabled. The actual USB controller probe determines whether this backend can import a device."
    case .unknown:
      return
        "No recent SIP result is available for the Builder. Open the latest Debagr there and Refresh. SIP status alone never proves USB access."
    }
  }

  static let setupExplanation = """
    The Builder creates a virtual USB host controller. The installed usbip-macos backend supports an Apple-approved com.apple.developer.usb.host-controller-interface entitlement with a granting provisioning profile, or its experimental SIP-off plus root path. This build does not have that entitlement. The Client exports physical USB and does not need SIP disabled.

    Disabling SIP reduces system-wide protection. Green describes compatibility with this experimental backend; the actual USB capability probe still runs when connecting. Apple recommends disabling SIP only temporarily for development.

    If you choose the experimental path, change SIP on the Builder only:
    • Apple silicon: shut down, hold the power button until startup options appear, then select Options → Continue.
    • Intel: restart while holding Command-R.
    • In Recovery, open Utilities → Terminal, run csrutil disable, then restart.

    Restore protection by returning to Recovery, running csrutil enable, and restarting. Reenabling SIP can block this experimental USB importer again. Debagr only reads SIP status and never changes it.
    """
}
