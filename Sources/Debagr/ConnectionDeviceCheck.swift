import Foundation

/// Read-only CoreDevice operations; process state never substitutes for this check.
struct ConnectionDeviceCheck {
  var inventory: () throws -> [TargetDevice] = {
    guard ProductSupport.developerToolsAvailable else {
      throw USBIPError.invalid(
        "Install Xcode and select its developer tools on this Builder, then Check Device again.")
    }
    return try CoreDeviceInventory.load(pairedMacNodeID: "local")
  }
  var verify: (String) throws -> Void = {
    try DeviceDeployer().checkReady(deviceIdentifier: $0, timeout: 15)
  }

  func devices() throws -> [TargetDevice] {
    try inventory().filter { $0.identity.source == .appleIdentifier }
      .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
  }

  static let readyPrefix = "Ready through CoreDevice:"

  func check(_ device: TargetDevice) throws -> String {
    try verify(device.identity.value)
    return
      "\(Self.readyPrefix) \(device.displayName) (…\(device.identity.value.suffix(6))) is reachable and unlocked."
  }

  static func recovery(for error: Error) -> String {
    switch error {
    case DeviceDeploymentError.deviceLocked:
      return "Unlock the device, keep it awake, then Check Device again."
    case DeviceDeploymentError.invalidResult:
      return
        "CoreDevice could not confirm readiness. Keep the device unlocked and Check Device again."
    case DeviceDeploymentError.timedOut, CoreDeviceInventoryError.timedOut:
      return
        "The device check timed out. Keep the device unlocked, confirm the Client is sharing it, then Check Device again."
    default:
      return
        "The device is not reachable yet. Confirm Trust on the device, keep it unlocked, then Check Device again. Details are in Diagnostics."
    }
  }
}
