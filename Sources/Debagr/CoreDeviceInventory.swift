import Darwin
import Foundation

enum CoreDeviceInventoryError: LocalizedError {
  case commandFailed(Int32)
  case timedOut
  case invalidOutput(String)

  var errorDescription: String? {
    switch self {
    case .commandFailed(let status):
      return "devicectl failed with status \(status)."
    case .timedOut:
      return "devicectl did not finish within 10 seconds."
    case .invalidOutput(let details):
      return "Unable to read devicectl output: \(details)"
    }
  }
}

enum CoreDeviceInventory {
  static func load(pairedMacNodeID: String) throws -> [TargetDevice] {
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("debagr-devices-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [
      "devicectl", "list", "devices", "--json-output", outputURL.path,
    ]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()

    guard finished.wait(timeout: .now() + 10) == .success else {
      process.terminate()
      if finished.wait(timeout: .now() + 1) != .success {
        _ = kill(process.processIdentifier, SIGKILL)
      }
      throw CoreDeviceInventoryError.timedOut
    }
    guard process.terminationStatus == 0 else {
      throw CoreDeviceInventoryError.commandFailed(process.terminationStatus)
    }

    do {
      return try decodeDevices(
        from: Data(contentsOf: outputURL),
        pairedMacNodeID: pairedMacNodeID
      )
    } catch let error as CoreDeviceInventoryError {
      throw error
    } catch {
      throw CoreDeviceInventoryError.invalidOutput(error.localizedDescription)
    }
  }

  static func decodeDevices(from data: Data, pairedMacNodeID: String) throws -> [TargetDevice] {
    let output = try JSONDecoder().decode(Output.self, from: data)
    return output.result.devices.compactMap { device in
      let hardware = device.properties?.hardware
      let deviceType = hardware?.deviceType ?? device.hardwareProperties?.deviceType
      let reality = hardware?.reality ?? device.hardwareProperties?.reality
      guard reality == "physical", let kind = TargetDeviceKind(coreDeviceType: deviceType) else {
        return nil
      }

      let identifier = hardware?.udid ?? device.hardwareProperties?.udid
      guard let identifier, !identifier.isEmpty else { return nil }
      let name = device.properties?.name ?? device.deviceProperties?.name
      let displayName = name?.nilIfBlank ?? hardware?.marketingName ?? kind.displayName
      let connectionState = device.properties?.connection?.state

      return TargetDevice(
        identity: .apple(pairedMacNodeID: pairedMacNodeID, identifier: identifier),
        displayName: displayName,
        kind: kind,
        service: nil,
        status: connectionState == "unavailable" ? .unavailable : .paired
      )
    }
  }

  private struct Output: Decodable {
    let result: Result
  }

  private struct Result: Decodable {
    let devices: [Device]
  }

  private struct Device: Decodable {
    let properties: Properties?
    let hardwareProperties: LegacyHardware?
    let deviceProperties: LegacyDevice?
  }

  private struct Properties: Decodable {
    let name: String?
    let hardware: Hardware?
    let connection: Connection?
  }

  private struct Hardware: Decodable {
    let deviceType: String?
    let marketingName: String?
    let reality: String?
    let udid: String?
  }

  private struct Connection: Decodable {
    let state: String?
  }

  private struct LegacyHardware: Decodable {
    let deviceType: String?
    let reality: String?
    let udid: String?
  }

  private struct LegacyDevice: Decodable {
    let name: String?
  }
}

extension TargetDeviceKind {
  fileprivate init?(coreDeviceType: String?) {
    switch coreDeviceType?.lowercased() {
    case "iphone":
      self = .iPhone
    case "ipad":
      self = .iPad
    default:
      return nil
    }
  }
}

extension String {
  fileprivate var nilIfBlank: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
