import DebagrCore
import Foundation
import Network
import Testing

@testable import DebagrBridge

@Suite("LockdownIdentityProbe")
struct LockdownIdentityProbeTests {
  private func makeDevice(
    name: String = "Radek’s iPhone 16 Pro",
    productType: String? = "iPhone17,1",
    platform: DevicePlatform = .iOS,
    osVersion: String? = "27.3"
  ) -> PhysicalDevice {
    PhysicalDevice(
      coreDeviceID: "CORE-1",
      udid: "00008140-001E45990413C01C",
      name: name,
      model: "iPhone 16 Pro",
      productType: productType,
      platform: platform,
      osVersion: osVersion,
      reality: .physical,
      pairingState: .paired,
      transportType: .localNetwork,
      tunnelState: .disconnected
    )
  }

  @Test("Encodes and decodes XML plist frames and extracts LockdownDeviceIdentity")
  func frameCodecAndIdentityParsing() throws {
    let request: [String: Any] = ["Request": "QueryType", "Label": "Debagr"]
    let frame = try NWConnectionLockdownProbe.encodeFrame(request)
    #expect(frame.count > 4)

    let declaredLength = frame.prefix(4).withUnsafeBytes { raw -> Int in
      let b = raw.bindMemory(to: UInt8.self)
      return (Int(b[0]) << 24) | (Int(b[1]) << 16) | (Int(b[2]) << 8) | Int(b[3])
    }
    #expect(declaredLength == frame.count - 4)

    let decoded = try NWConnectionLockdownProbe.decodeFrame(Data(frame.dropFirst(4)))
    #expect(decoded["Request"] as? String == "QueryType")
    #expect(decoded["Label"] as? String == "Debagr")

    let getValueResponse: [String: Any] = [
      "Request": "GetValue",
      "Value": [
        "CPUArchitecture": "arm64e",
        "DeviceName": "Radek’s iPhone 16 Pro",
        "HardwareModel": "D93AP",
        "HumanReadableProductVersionString": "27.3",
        "ProductName": "iPhone OS",
        "ProductType": "iPhone17,1",
        "ProductVersion": "27.3",
      ],
    ]
    let identity = try #require(NWConnectionLockdownProbe.parseIdentity(from: getValueResponse))
    #expect(identity.deviceName == "Radek’s iPhone 16 Pro")
    #expect(identity.productType == "iPhone17,1")
    #expect(identity.productVersion == "27.3")
    #expect(identity.hardwareModel == "D93AP")
    #expect(identity.productName == "iPhone OS")
    #expect(identity.cpuArchitecture == "arm64e")
    #expect(identity.isIPhone)
    #expect(!identity.isIPad)
    #expect(identity.osDisplayLabel == "iOS 27.3")
    #expect(identity.compactSummary == "Radek’s iPhone 16 Pro · iPhone17,1 · iOS 27.3")
  }

  @Test("LockdownDeviceIdentity.compare detects matches, mismatches, and inconclusive cases")
  func identityComparisonVerdicts() {
    let step1Device = makeDevice()

    let curlyApostropheMatch = LockdownDeviceIdentity(
      deviceName: "Radek's iPhone 16 Pro",
      productType: "iPhone17,1",
      productVersion: "27.3.1"
    )
    #expect(curlyApostropheMatch.compare(to: step1Device) == .verifiedMatch)

    let wrongProductType = LockdownDeviceIdentity(
      deviceName: "Radek’s iPhone 16 Pro",
      productType: "iPhone16,1",
      productVersion: "27.3"
    )
    if case .mismatch = wrongProductType.compare(to: step1Device) {
      // expected
    } else {
      Issue.record("Expected mismatch for differing productType")
    }

    let wrongName = LockdownDeviceIdentity(
      deviceName: "Test Lab iPhone",
      productType: "iPhone17,1",
      productVersion: "27.3"
    )
    if case .mismatch = wrongName.compare(to: step1Device) {
      // expected
    } else {
      Issue.record("Expected mismatch for differing deviceName")
    }

    let wrongOS = LockdownDeviceIdentity(
      deviceName: "Radek’s iPhone 16 Pro",
      productType: "iPhone17,1",
      productVersion: "18.4"
    )
    if case .mismatch = wrongOS.compare(to: step1Device) {
      // expected
    } else {
      Issue.record("Expected mismatch for differing major.minor OS version")
    }

    let iPadAgainstIPhone = LockdownDeviceIdentity(
      deviceName: "iPad",
      productType: "iPad16,3",
      productVersion: "27.3"
    )
    if case .mismatch = iPadAgainstIPhone.compare(to: makeDevice(productType: nil)) {
      // expected
    } else {
      Issue.record("Expected mismatch when iPad responds for an iOS device")
    }

    let genericNameNoProductType = LockdownDeviceIdentity(
      deviceName: "iPhone",
      productType: nil,
      productVersion: "27.3"
    )
    #expect(genericNameNoProductType.compare(to: makeDevice(productType: nil)) == .inconclusive)
  }

  @Test(
    "NWConnectionLockdownProbe queries loopback mock lockdownd and rejects non-private hosts by default"
  )
  func loopbackProbeAndPrivateAddressGuard() async throws {
    let defaultProbe = NWConnectionLockdownProbe()
    let rejected = await defaultProbe.probeIdentity(
      host: "8.8.8.8", port: 62078, timeoutSeconds: 1.0)
    #expect(rejected == nil)

    let server = MockLockdownServer()
    defer { server.stop() }
    let port = try await server.start()

    let loopbackProbe = NWConnectionLockdownProbe(allowNonPrivateHosts: true)
    let identity = try #require(
      await loopbackProbe.probeIdentity(host: "127.0.0.1", port: port, timeoutSeconds: 3.0)
    )
    #expect(identity.deviceName == "Radek’s iPhone 16 Pro")
    #expect(identity.productType == "iPhone17,1")
    #expect(identity.productVersion == "27.3")
    #expect(identity.hardwareModel == "D93AP")
  }
}

private final class MockLockdownServer: @unchecked Sendable {
  private let queue = DispatchQueue(label: "dev.debagr.mock-lockdownd")
  private var listener: NWListener?
  private var connections: [NWConnection] = []

  func start() async throws -> UInt16 {
    let listener = try NWListener(using: .tcp, on: .any)
    self.listener = listener

    return try await withCheckedThrowingContinuation { continuation in
      let resumed = LockBox(false)
      listener.stateUpdateHandler = { [weak self] state in
        switch state {
        case .ready:
          guard resumed.takeOnce() else { return }
          if let port = listener.port?.rawValue {
            continuation.resume(returning: port)
          } else {
            continuation.resume(
              throwing: DebagrError(
                code: .bridgeError,
                category: "test",
                message: "MockLockdownServer did not assign port."
              )
            )
          }
        case .failed(let error):
          guard resumed.takeOnce() else { return }
          self?.stop()
          continuation.resume(throwing: error)
        default:
          break
        }
      }

      listener.newConnectionHandler = { [weak self] connection in
        self?.handleConnection(connection)
      }

      listener.start(queue: queue)
    }
  }

  func stop() {
    queue.async { [weak self] in
      self?.listener?.cancel()
      self?.listener = nil
      for conn in self?.connections ?? [] {
        conn.cancel()
      }
      self?.connections.removeAll()
    }
  }

  private func handleConnection(_ connection: NWConnection) {
    connections.append(connection)
    connection.start(queue: queue)
    readNextRequest(on: connection, buffer: Data())
  }

  private func readNextRequest(on connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
      [weak self] data, _, isComplete, error in
      guard let self, error == nil else {
        connection.cancel()
        return
      }
      var nextBuffer = buffer
      if let data {
        nextBuffer.append(data)
      }

      while nextBuffer.count >= 4 {
        let len = nextBuffer.prefix(4).withUnsafeBytes { raw -> Int in
          let b = raw.bindMemory(to: UInt8.self)
          return (Int(b[0]) << 24) | (Int(b[1]) << 16) | (Int(b[2]) << 8) | Int(b[3])
        }
        guard nextBuffer.count >= 4 + len else { break }
        let bodyStart = nextBuffer.index(nextBuffer.startIndex, offsetBy: 4)
        let frameEnd = nextBuffer.index(bodyStart, offsetBy: len)
        let body = Data(nextBuffer[bodyStart..<frameEnd])
        nextBuffer = Data(nextBuffer[frameEnd...])

        if let request = try? NWConnectionLockdownProbe.decodeFrame(body),
          let reqType = request["Request"] as? String
        {
          let response: [String: Any]
          if reqType == "QueryType" {
            response = ["Request": "QueryType", "Type": "com.apple.mobile.lockdown"]
          } else if reqType == "GetValue" {
            response = [
              "Request": "GetValue",
              "Value": [
                "CPUArchitecture": "arm64e",
                "DeviceName": "Radek’s iPhone 16 Pro",
                "HardwareModel": "D93AP",
                "ProductName": "iPhone OS",
                "ProductType": "iPhone17,1",
                "ProductVersion": "27.3",
              ],
            ]
          } else {
            response = ["Error": "InvalidRequest"]
          }

          if let encoded = try? NWConnectionLockdownProbe.encodeFrame(response) {
            connection.send(content: encoded, completion: .contentProcessed { _ in })
          }
        }
      }

      if !isComplete {
        self.readNextRequest(on: connection, buffer: nextBuffer)
      }
    }
  }
}

private final class LockBox: @unchecked Sendable {
  private let lock = NSLock()
  private var fired: Bool

  init(_ initial: Bool) {
    self.fired = initial
  }

  func takeOnce() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if fired { return false }
    fired = true
    return true
  }
}
