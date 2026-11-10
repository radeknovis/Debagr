import XCTest

@testable import Debagr

final class InventoryTests: XCTestCase {
  func testProvisionalIdentityPrefersBonjourIdentifierMetadata() {
    let device = BonjourDevice(
      instanceName: "service-instance",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "iPad.local",
      port: 49_153,
      txt: ["identifier": "stable-service-id"]
    )

    XCTAssertEqual(
      TargetDeviceIdentity.provisional(
        pairedMacNodeID: "tailnet-mac",
        service: device
      ).value,
      "bonjour:stable-service-id"
    )
  }

  func testTargetDeviceRegistryKeepsMultipleDevicesIndependent() {
    let phoneService = BonjourDevice(
      instanceName: "iPhone",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "iphone.local",
      port: 49_152,
      txt: [:]
    )
    let tabletService = BonjourDevice(
      instanceName: "iPad",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "ipad.local",
      port: 49_153,
      txt: [:]
    )
    let phoneID = TargetDeviceIdentity.apple(
      pairedMacNodeID: "tailnet-mac",
      identifier: "phone-udid"
    )
    let tabletID = TargetDeviceIdentity.apple(
      pairedMacNodeID: "tailnet-mac",
      identifier: "tablet-udid"
    )

    var registry = TargetDeviceRegistry()
    registry.upsert(
      identity: phoneID,
      displayName: "Phone",
      kind: .iPhone,
      service: phoneService
    )
    registry.upsert(
      identity: tabletID,
      displayName: "Tablet",
      kind: .iPad,
      service: tabletService
    )

    XCTAssertEqual(registry.devices.count, 2)
    XCTAssertEqual(registry.orderedDevices.map(\.kind), [.iPhone, .iPad])
    XCTAssertEqual(registry.device(for: phoneID)?.service?.port, 49_152)

    registry.remove(phoneID)

    XCTAssertNil(registry.device(for: phoneID))
    XCTAssertEqual(registry.device(for: tabletID)?.kind, .iPad)
  }

  func testTargetDeviceKindInfersPhoneAndPadWithoutRequiringMetadata() {
    let phone = BonjourDevice(
      instanceName: "Office iPhone",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "phone.local",
      port: 49_152,
      txt: [:]
    )
    let tablet = BonjourDevice(
      instanceName: "Office tablet",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "tablet.local",
      port: 49_153,
      txt: ["model": "iPad Pro"]
    )
    let unknown = BonjourDevice(
      instanceName: "Apple device",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "device.local",
      port: 49_154,
      txt: [:]
    )

    XCTAssertEqual(TargetDeviceKind.inferred(from: phone), .iPhone)
    XCTAssertEqual(TargetDeviceKind.inferred(from: tablet), .iPad)
    XCTAssertEqual(TargetDeviceKind.inferred(from: unknown), .unknown)
  }

  func testCoreDeviceInventoryKeepsOnlyPhysicalIPhoneAndIPad() throws {
    let json = """
      {
        "result": {
          "devices": [
            {
              "properties": {
                "hardware": {
                  "deviceType": "iPhone",
                  "marketingName": "iPhone 16 Pro",
                  "reality": "physical",
                  "udid": "phone-udid"
                },
                "connection": { "state": "disconnected" }
              },
              "deviceProperties": { "name": "Test iPhone" }
            },
            {
              "properties": {
                "hardware": {
                  "deviceType": "iPad",
                  "marketingName": "iPad Pro",
                  "reality": "physical",
                  "udid": "tablet-udid"
                },
                "connection": { "state": "unavailable" }
              },
              "deviceProperties": { "name": "Test iPad" }
            },
            {
              "properties": {
                "hardware": {
                  "deviceType": "appleWatch",
                  "reality": "physical",
                  "udid": "watch-udid"
                }
              }
            },
            {
              "properties": {
                "hardware": {
                  "deviceType": "iPhone",
                  "reality": "simulated",
                  "udid": "simulator-udid"
                }
              }
            }
          ]
        }
      }
      """

    let devices = try CoreDeviceInventory.decodeDevices(
      from: try XCTUnwrap(json.data(using: .utf8)),
      pairedMacNodeID: "local-mac"
    )

    XCTAssertEqual(devices.map(\.displayName), ["Test iPhone", "Test iPad"])
    XCTAssertEqual(devices.map(\.kind), [.iPhone, .iPad])
    XCTAssertEqual(devices.map(\.status), [.paired, .unavailable])
  }

  func testRegistryMergesCoreDeviceWithMatchingBonjourService() {
    let service = BonjourDevice(
      instanceName: "RemotePairing",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "iphone.local",
      port: 49_152,
      txt: ["identifier": "phone-udid"]
    )
    var registry = TargetDeviceRegistry()
    registry.merge(
      TargetDevice(
        identity: .apple(pairedMacNodeID: "mac", identifier: "phone-udid"),
        displayName: "Test iPhone",
        kind: .iPhone,
        service: nil,
        status: .paired
      )
    )
    registry.merge(
      TargetDevice(
        identity: .provisional(pairedMacNodeID: "mac", service: service),
        displayName: service.suggestedDisplayName,
        kind: .iPhone,
        service: service,
        status: .visible
      )
    )

    XCTAssertEqual(registry.devices.count, 1)
    XCTAssertEqual(registry.orderedDevices[0].identity.source, .appleIdentifier)
    XCTAssertEqual(registry.orderedDevices[0].displayName, "Test iPhone")
    XCTAssertEqual(registry.orderedDevices[0].status, .visible)
    XCTAssertEqual(registry.orderedDevices[0].service?.port, 49_152)
  }

  func testRegistryMergesUniqueFriendlyNameWhenBonjourIdentifierDiffers() {
    let service = BonjourDevice(
      instanceName: "bonjour-id",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "Jane--iPhone.local",
      port: 49_152,
      txt: [:]
    )
    var registry = TargetDeviceRegistry()
    registry.merge(
      TargetDevice(
        identity: .apple(pairedMacNodeID: "mac", identifier: "apple-udid"),
        displayName: "Jane - iPhone",
        kind: .iPhone,
        service: nil,
        status: .paired
      )
    )
    registry.merge(
      TargetDevice(
        identity: .provisional(pairedMacNodeID: "mac", service: service),
        displayName: service.suggestedDisplayName,
        kind: .iPhone,
        service: service,
        status: .visible
      )
    )

    XCTAssertEqual(registry.devices.count, 1)
    XCTAssertEqual(registry.orderedDevices[0].identity.value, "apple-udid")
    XCTAssertEqual(registry.orderedDevices[0].service?.hostName, "Jane--iPhone.local")
  }
}
