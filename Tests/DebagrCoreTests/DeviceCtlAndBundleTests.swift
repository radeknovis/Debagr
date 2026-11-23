import Foundation
import Testing

@testable import DebagrCore

@Suite("DeviceCtl Dual-Schema & App Bundle Validation")
struct DeviceCtlAndBundleTests {
  @Test("Decodes Xcode 27 properties.* devicectl payload accurately")
  func decodesModernSchema() throws {
    let json = #"""
      {
        "info": { "outcome": "success", "version": "651.31", "jsonVersion": 5 },
        "result": {
          "devices": [
            {
              "identifier": "DFED0FBB-E09B-5FB5-8597-5FC3F02F55EA",
              "properties": {
                "connection": {
                  "pairingState": "paired",
                  "state": "disconnected",
                  "transportType": "localNetwork"
                },
                "hardware": {
                  "deviceType": "iPhone",
                  "ecid": 8520772802035740,
                  "marketingName": "iPhone 16 Pro",
                  "platform": "iOS",
                  "productType": "iPhone17,1",
                  "reality": "physical",
                  "udid": "00008140-001E45990413C01C"
                },
                "software": {
                  "osVersionNumber": { "stringValue": "27.3" }
                },
                "state": {
                  "bootState": "booted",
                  "developerModeStatus": { "enabled": { "mode": 1 } },
                  "name": "Radek's iPhone 16 Pro"
                }
              }
            }
          ]
        }
      }
      """#

    let envelope = try JSONDecoder().decode(
      DeviceCtlEnvelope<DeviceCtlListDevicesResult>.self,
      from: Data(json.utf8)
    )
    let device = try #require(envelope.result?.devices.first?.toPhysicalDevice())
    #expect(device.isEligibleForDebagr)
    #expect(device.platform == .iOS)
    #expect(device.reality == .physical)
    #expect(device.pairingState == .paired)
    #expect(device.osVersion == "27.3")
    #expect(device.isDeveloperModeEnabled == true)
    #expect(device.udid == "00008140-001E45990413C01C")
  }

  @Test(
    "Decodes legacy hardwareProperties/deviceProperties/connectionProperties payload and iPad detection"
  )
  func decodesLegacySchema() throws {
    let json = #"""
      {
        "result": {
          "devices": [
            {
              "identifier": "CORE-IPAD-1",
              "hardwareProperties": {
                "deviceType": "iPad",
                "platform": "iOS",
                "productType": "iPad14,5",
                "marketingName": "iPad Pro",
                "reality": "physical",
                "udid": "00008112-0011223344556677"
              },
              "deviceProperties": {
                "name": "Studio iPad",
                "osVersionNumber": "18.2",
                "developerModeStatus": "disabled"
              },
              "connectionProperties": {
                "pairingState": "paired",
                "transportType": "wired",
                "tunnelState": "connected"
              }
            },
            {
              "identifier": "SIM-1",
              "hardwareProperties": {
                "deviceType": "iPhone",
                "platform": "iOS",
                "reality": "simulated",
                "udid": "SIM-UDID-1"
              },
              "deviceProperties": { "name": "iPhone Sim" },
              "connectionProperties": { "pairingState": "unpaired" }
            }
          ]
        }
      }
      """#

    let envelope = try JSONDecoder().decode(
      DeviceCtlEnvelope<DeviceCtlListDevicesResult>.self,
      from: Data(json.utf8)
    )
    let devices = (envelope.result?.devices ?? []).map { $0.toPhysicalDevice() }
    #expect(devices.count == 2)

    let ipad = devices[0]
    #expect(ipad.platform == .iPadOS)
    #expect(ipad.isEligibleForDebagr)
    #expect(ipad.isDeveloperModeEnabled == false)
    #expect(ipad.transportType == .wired)
    #expect(ipad.tunnelState == .connected)

    let sim = devices[1]
    #expect(!sim.isEligibleForDebagr)
    #expect(sim.reality == .simulated)
  }

  @Test("AppBundleValidator accepts signed iphoneos .app and rejects simulator/mac/unsigned apps")
  func validatesAppBundles() async throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("debagr-bundle-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    func makeBundle(name: String, info: [String: Any]) throws -> URL {
      let appURL = tempRoot.appendingPathComponent("\(name).app", isDirectory: true)
      try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
      let data = try PropertyListSerialization.data(
        fromPropertyList: info, format: .xml, options: 0)
      try data.write(to: appURL.appendingPathComponent("Info.plist"))
      return appURL
    }

    let validApp = try makeBundle(
      name: "SampleIOS",
      info: [
        "CFBundleIdentifier": "com.example.sampleios",
        "CFBundleName": "SampleIOS",
        "CFBundleShortVersionString": "1.2.0",
        "CFBundleVersion": "42",
        "DTPlatformName": "iphoneos",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
      ]
    )

    let simApp = try makeBundle(
      name: "SampleSim",
      info: [
        "CFBundleIdentifier": "com.example.samplesim",
        "DTPlatformName": "iphonesimulator",
      ]
    )

    let macApp = try makeBundle(
      name: "SampleMac",
      info: [
        "CFBundleIdentifier": "com.example.samplemac",
        "DTPlatformName": "macosx",
      ]
    )

    let passingRunner = StubCommandRunner { _, args in
      if args.contains("--verify") {
        return CommandResult(
          exitCode: 0, stdout: Data(), stderr: Data(), timedOut: false, durationMs: 5)
      }
      return CommandResult(
        exitCode: 0,
        stdout: Data(),
        stderr: Data("Authority=Apple Development: Test Developer\n".utf8),
        timedOut: false,
        durationMs: 4
      )
    }

    let validator = SystemAppBundleValidator(runner: passingRunner)
    let validated = try await validator.validate(appPath: validApp.path)
    #expect(validated.bundleIdentifier == "com.example.sampleios")
    #expect(validated.signingAuthority == "Apple Development: Test Developer")

    await #expect(throws: DebagrError.self) {
      _ = try await validator.validate(appPath: simApp.path)
    }
    await #expect(throws: DebagrError.self) {
      _ = try await validator.validate(appPath: macApp.path)
    }

    let unsignedRunner = StubCommandRunner { _, _ in
      CommandResult(
        exitCode: 1,
        stdout: Data(),
        stderr: Data("code object is not signed at all\n".utf8),
        timedOut: false,
        durationMs: 3
      )
    }
    let unsignedValidator = SystemAppBundleValidator(runner: unsignedRunner)
    do {
      _ = try await unsignedValidator.validate(appPath: validApp.path)
      Issue.record("Expected APP_NOT_SIGNED error")
    } catch let err as DebagrError {
      #expect(err.payload.code == .appNotSigned)
    }
  }
}

struct StubCommandRunner: CommandRunning {
  let handler: @Sendable (String, [String]) async throws -> CommandResult

  func run(
    executable: String,
    arguments: [String],
    environment: [String: String]?,
    timeoutSeconds: TimeInterval
  ) async throws -> CommandResult {
    try await handler(executable, arguments)
  }
}
