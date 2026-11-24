import DebagrCore
import Foundation
import Network
import os

public enum LockdownMatchVerdict: Sendable, Equatable {
  case verifiedMatch
  case mismatch(reason: String)
  case inconclusive
}

public struct LockdownDeviceIdentity: Codable, Sendable, Equatable {
  public let deviceName: String?
  public let productType: String?
  public let productVersion: String?
  public let humanReadableProductVersion: String?
  public let hardwareModel: String?
  public let productName: String?
  public let cpuArchitecture: String?

  public init(
    deviceName: String? = nil,
    productType: String? = nil,
    productVersion: String? = nil,
    humanReadableProductVersion: String? = nil,
    hardwareModel: String? = nil,
    productName: String? = nil,
    cpuArchitecture: String? = nil
  ) {
    self.deviceName = deviceName
    self.productType = productType
    self.productVersion = productVersion
    self.humanReadableProductVersion = humanReadableProductVersion
    self.hardwareModel = hardwareModel
    self.productName = productName
    self.cpuArchitecture = cpuArchitecture
  }

  public var effectiveOSVersion: String? {
    if let productVersion, !productVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return productVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let humanReadableProductVersion,
      !humanReadableProductVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return humanReadableProductVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
  }

  public var isIPad: Bool {
    productType?.lowercased().hasPrefix("ipad") ?? false
  }

  public var isIPhone: Bool {
    productType?.lowercased().hasPrefix("iphone") ?? false
  }

  public var osDisplayLabel: String? {
    guard let version = effectiveOSVersion else { return nil }
    return "\(isIPad ? "iPadOS" : "iOS") \(version)"
  }

  public var compactSummary: String {
    [deviceName, productType, osDisplayLabel]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
  }

  public func compare(to device: PhysicalDevice) -> LockdownMatchVerdict {
    if let probedProductType = nonEmptyTrimmed(productType),
      let expectedProductType = nonEmptyTrimmed(device.productType),
      probedProductType.caseInsensitiveCompare(expectedProductType) != .orderedSame
    {
      return .mismatch(
        reason:
          "VPN endpoint answered as hardware \(probedProductType), expected \(expectedProductType)."
      )
    }

    if (isIPad && device.platform == .iOS) || (isIPhone && device.platform == .iPadOS) {
      let answeredPlatform = isIPad ? "iPadOS" : "iOS"
      return .mismatch(
        reason:
          "VPN endpoint answered as an \(answeredPlatform) device, expected \(device.platform.rawValue)."
      )
    }

    let normalizedProbedName = nonEmptyTrimmed(deviceName).map(Self.normalizeDeviceName)
    let normalizedExpectedName = nonEmptyTrimmed(device.name).map(Self.normalizeDeviceName)
    if let probedName = normalizedProbedName,
      let expectedName = normalizedExpectedName,
      !Self.isGenericAppleDeviceName(probedName),
      probedName.caseInsensitiveCompare(expectedName) != .orderedSame
    {
      return .mismatch(
        reason: "VPN endpoint answered as '\(deviceName ?? probedName)', expected '\(device.name)'."
      )
    }

    if let probedVersion = effectiveOSVersion,
      let expectedVersion = nonEmptyTrimmed(device.osVersion),
      let probedMajorMinor = Self.leadingMajorMinor(probedVersion),
      let expectedMajorMinor = Self.leadingMajorMinor(expectedVersion),
      probedMajorMinor != expectedMajorMinor
    {
      return .mismatch(
        reason: "VPN endpoint reported OS \(probedVersion), expected \(expectedVersion)."
      )
    }

    if let probedProductType = nonEmptyTrimmed(productType),
      let expectedProductType = nonEmptyTrimmed(device.productType),
      probedProductType.caseInsensitiveCompare(expectedProductType) == .orderedSame
    {
      return .verifiedMatch
    }

    if let probedName = normalizedProbedName,
      let expectedName = normalizedExpectedName,
      probedName.caseInsensitiveCompare(expectedName) == .orderedSame
    {
      return .verifiedMatch
    }

    return .inconclusive
  }

  private func nonEmptyTrimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func normalizeDeviceName(_ raw: String) -> String {
    raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\u{2019}", with: "'")
      .replacingOccurrences(of: "\u{2018}", with: "'")
  }

  private static func isGenericAppleDeviceName(_ normalized: String) -> Bool {
    let lower = normalized.lowercased()
    return lower == "iphone" || lower == "ipad"
  }

  private static func leadingMajorMinor(_ version: String) -> (Int, Int)? {
    let token = version.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? version
    let components = token.split(separator: ".").compactMap { Int($0) }
    guard let major = components.first else { return nil }
    let minor = components.count >= 2 ? components[1] : 0
    return (major, minor)
  }
}

public protocol LockdownIdentityProbing: Sendable {
  func probeIdentity(host: String, port: UInt16, timeoutSeconds: TimeInterval) async
    -> LockdownDeviceIdentity?
}

public final class NWConnectionLockdownProbe: LockdownIdentityProbing, Sendable {
  public static let maxFrameBytes = 64 * 1024

  private let allowNonPrivateHosts: Bool

  public init(allowNonPrivateHosts: Bool = false) {
    self.allowNonPrivateHosts = allowNonPrivateHosts
  }

  public func probeIdentity(
    host: String,
    port: UInt16 = VPNEndpoint.defaultLockdownPort,
    timeoutSeconds: TimeInterval = 2.0
  ) async -> LockdownDeviceIdentity? {
    let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard allowNonPrivateHosts || IPValidation.isPrivateVPNAddress(trimmedHost) else {
      return nil
    }
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
      return nil
    }

    let queryFrame: Data
    let getValueFrame: Data
    do {
      queryFrame = try Self.encodeFrame(["Request": "QueryType", "Label": "Debagr"])
      getValueFrame = try Self.encodeFrame(["Request": "GetValue", "Label": "Debagr"])
    } catch {
      return nil
    }

    let connection = NWConnection(host: NWEndpoint.Host(trimmedHost), port: nwPort, using: .tcp)
    let queue = DispatchQueue(label: "dev.debagr.lockdownprobe.\(UUID().uuidString)")
    let session = ProbeSession(connection: connection)
    let effectiveTimeout = max(0.3, min(10.0, timeoutSeconds))

    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard session.attachContinuation(continuation) else {
          return
        }

        connection.stateUpdateHandler = { state in
          switch state {
          case .ready:
            Self.sendFrame(queryFrame, on: connection) { sentQuery in
              guard sentQuery else {
                session.finish(nil)
                return
              }
              Self.receiveFrame(from: connection) { queryResponse in
                guard let queryResponse,
                  (queryResponse["Type"] as? String) == "com.apple.mobile.lockdown"
                else {
                  session.finish(nil)
                  return
                }
                Self.sendFrame(getValueFrame, on: connection) { sentGetValue in
                  guard sentGetValue else {
                    session.finish(nil)
                    return
                  }
                  Self.receiveFrame(from: connection) { valueResponse in
                    guard let valueResponse else {
                      session.finish(nil)
                      return
                    }
                    session.finish(Self.parseIdentity(from: valueResponse))
                  }
                }
              }
            }
          case .failed, .cancelled:
            session.finish(nil)
          default:
            break
          }
        }

        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + effectiveTimeout) {
          session.finish(nil)
        }
      }
    } onCancel: {
      session.cancel()
    }
  }

  public static func encodeFrame(_ plist: [String: Any]) throws -> Data {
    let body = try PropertyListSerialization.data(
      fromPropertyList: plist,
      format: .xml,
      options: 0
    )
    var length = UInt32(body.count).bigEndian
    var frame = Data(bytes: &length, count: 4)
    frame.append(body)
    return frame
  }

  public static func decodeFrame(_ payload: Data) throws -> [String: Any] {
    let object = try PropertyListSerialization.propertyList(
      from: payload,
      options: [],
      format: nil
    )
    guard let dict = object as? [String: Any] else {
      throw DebagrError(
        code: .bridgeError,
        category: "lockdown",
        message: "Expected dictionary payload in lockdown plist frame."
      )
    }
    return dict
  }

  public static func parseIdentity(from response: [String: Any]) -> LockdownDeviceIdentity? {
    guard let values = response["Value"] as? [String: Any] else {
      return nil
    }

    func nonEmptyString(_ key: String) -> String? {
      guard let raw = values[key] as? String else { return nil }
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }

    let identity = LockdownDeviceIdentity(
      deviceName: nonEmptyString("DeviceName"),
      productType: nonEmptyString("ProductType"),
      productVersion: nonEmptyString("ProductVersion"),
      humanReadableProductVersion: nonEmptyString("HumanReadableProductVersionString"),
      hardwareModel: nonEmptyString("HardwareModel"),
      productName: nonEmptyString("ProductName"),
      cpuArchitecture: nonEmptyString("CPUArchitecture")
    )

    if identity.deviceName == nil,
      identity.productType == nil,
      identity.productVersion == nil,
      identity.hardwareModel == nil
    {
      return nil
    }
    return identity
  }

  private static func sendFrame(
    _ data: Data,
    on connection: NWConnection,
    completion: @escaping @Sendable (Bool) -> Void
  ) {
    connection.send(
      content: data,
      completion: .contentProcessed { error in
        completion(error == nil)
      }
    )
  }

  private static func receiveFrame(
    from connection: NWConnection,
    completion: @escaping @Sendable ([String: Any]?) -> Void
  ) {
    receiveExact(4, from: connection) { headerData in
      guard let headerData, headerData.count == 4 else {
        completion(nil)
        return
      }
      let length = headerData.withUnsafeBytes { raw -> UInt32 in
        let bytes = raw.bindMemory(to: UInt8.self)
        return (UInt32(bytes[0]) << 24)
          | (UInt32(bytes[1]) << 16)
          | (UInt32(bytes[2]) << 8)
          | UInt32(bytes[3])
      }
      guard length > 0, length <= UInt32(maxFrameBytes) else {
        completion(nil)
        return
      }
      receiveExact(Int(length), from: connection) { bodyData in
        guard let bodyData else {
          completion(nil)
          return
        }
        completion(try? decodeFrame(bodyData))
      }
    }
  }

  private static func receiveExact(
    _ count: Int,
    from connection: NWConnection,
    accumulated: Data = Data(),
    completion: @escaping @Sendable (Data?) -> Void
  ) {
    let remaining = count - accumulated.count
    if remaining <= 0 {
      completion(accumulated)
      return
    }
    connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) {
      data, _, isComplete, error in
      if error != nil {
        completion(nil)
        return
      }
      var next = accumulated
      if let data, !data.isEmpty {
        next.append(data)
      }
      if next.count >= count {
        completion(next)
      } else if isComplete {
        completion(nil)
      } else {
        receiveExact(count, from: connection, accumulated: next, completion: completion)
      }
    }
  }

  private final class ProbeSession: Sendable {
    private struct State {
      var finished = false
      var cancelled = false
      var continuation: CheckedContinuation<LockdownDeviceIdentity?, Never>?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let connection: NWConnection

    init(connection: NWConnection) {
      self.connection = connection
    }

    func attachContinuation(
      _ continuation: CheckedContinuation<LockdownDeviceIdentity?, Never>
    ) -> Bool {
      let cancelledEarly = state.withLock { current -> Bool in
        if current.cancelled || current.finished {
          current.finished = true
          return true
        }
        current.continuation = continuation
        return false
      }
      if cancelledEarly {
        connection.cancel()
        continuation.resume(returning: nil)
        return false
      }
      return true
    }

    func finish(_ identity: LockdownDeviceIdentity?) {
      let continuation: CheckedContinuation<LockdownDeviceIdentity?, Never>? = state.withLock {
        current in
        guard !current.finished else { return nil }
        current.finished = true
        let cont = current.continuation
        current.continuation = nil
        return cont
      }
      connection.cancel()
      continuation?.resume(returning: identity)
    }

    func cancel() {
      let continuation: CheckedContinuation<LockdownDeviceIdentity?, Never>? = state.withLock {
        current in
        current.cancelled = true
        guard !current.finished else { return nil }
        current.finished = true
        let cont = current.continuation
        current.continuation = nil
        return cont
      }
      connection.cancel()
      continuation?.resume(returning: nil)
    }
  }
}
