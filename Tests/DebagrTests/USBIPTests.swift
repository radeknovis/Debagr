import XCTest

@testable import Debagr

final class USBIPTests: XCTestCase {
  func testExistingExportCatalogIsReusedOnlyForTheExplicitlySelectedDevice() throws {
    let command = try USBIPCommand([
      "serve", "--tool", "/tool", "--listen", "100.80.103.100",
      "--peer", "100.98.191.109", "--serial", "phone",
    ])
    let device = USBIPDevice(
      serial: "phone", name: "iPhone", vendorID: 0x05ac,
      productID: 0x12a8, locationID: 0x0010_0000)
    let saved = Data(#"[{"vendor":1452,"product":4776,"location":1048576,"label":"iphone"}]"#.utf8)
    XCTAssertEqual(
      try command.backendArguments(devices: [device], savedExports: saved),
      ["100.80.103.100", "100.98.191.109"])
    for saved in [
      Data("[]".utf8), Data("[{},{}]".utf8),
      Data(#"[{"vendor":1452,"product":4776,"location":0}]"#.utf8),
    ] {
      XCTAssertThrowsError(try command.backendArguments(devices: [device], savedExports: saved))
    }
  }
  func testUSBIPCheckIgnoresWirelessAndUnavailableDevices() throws {
    let hardware = ["deviceType": "iPad", "reality": "physical"]
    func device(_ id: String, _ transport: String, _ state: String) -> [String: Any] {
      [
        "hardwareProperties": hardware.merging(["udid": id]) { _, new in new },
        "connectionProperties": ["transportType": transport],
        "properties": ["connection": ["state": state]],
      ]
    }
    let data = try JSONSerialization.data(withJSONObject: [
      "result": [
        "devices": [
          device("wired", "wired", "connected"), device("other", "localNetwork", "connected"),
          device("absent", "wired", "unavailable"), device("unknown", "", "connected"),
          [
            "hardwareProperties": hardware.merging(["udid": "legacy"]) { _, new in new },
            "connectionProperties": ["state": "disconnected", "transportType": "wired"],
          ],
        ]
      ]
    ])
    let wired = try CoreDeviceInventory.decodeDevices(
      from: data, pairedMacNodeID: "local", wiredOnly: true)
    XCTAssertEqual(wired.map(\.identity.value), ["wired"])
    XCTAssertEqual(
      try CoreDeviceInventory.decodeDevices(from: data, pairedMacNodeID: "local").count, 5)
  }

  func testClientPassesExplicitArgumentsWithoutShell() throws {
    let list = try USBIPCommand([
      "list", "--tool", "/tmp/tool with spaces", "--remote", "100.80.103.100",
    ])
    XCTAssertEqual(try list.backendArguments(), ["-r", "100.80.103.100", "list"])
    let attach = try USBIPCommand([
      "attach", "--tool", "/tmp/tool", "--remote", "10.0.0.2", "--busid", "1-2.3",
    ])
    XCTAssertEqual(try attach.backendArguments(), ["-r", "10.0.0.2", "attach", "--busid", "1-2.3"])
  }

  func testRejectsAmbiguousOrUnsafeOptions() {
    for arguments in [
      [], ["serve"], ["devices", "--json"], ["probe", "--status", "yes"],
      ["list", "--tool", "relative", "--remote", "10.0.0.2"],
      ["list", "--tool", "/tool", "--remote", "8.8.8.8"],
      ["list", "--tool", "/tool", "--remote", "0.0.0.0"],
      ["list", "--tool", "/tool", "--remote", "example.com"],
      ["list", "--tool", "/tool", "--remote", "10.0.0.2", "--remote", "10.0.0.3"],
      ["attach", "--tool", "/tool", "--remote", "10.0.0.2", "--busid", "--help"],
      ["attach", "--tool", "/tool", "--remote", "10.0.0.2", "--busid", "1-1; id"],
      ["run-session", "--request", "/tmp/session/request.json"],
      ["run-session", "--session", "/tmp/session"],
      ["stop-session", "--session", "/tmp/session", "--approved", "e30="],
    ] { XCTAssertThrowsError(try USBIPCommand(arguments), "\(arguments)") }
  }

  func testProbeHelperIsFoundBesideTheRealExecutableBehindALink() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ProbeLink-\(UUID().uuidString)")
    let bundle = folder.appendingPathComponent("Debagr.app/Contents/MacOS")
    let bin = folder.appendingPathComponent("bin")
    for directory in [bundle, bin] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: folder) }
    let executable = bundle.appendingPathComponent("Debagr")
    try Data().write(to: executable)
    let link = bin.appendingPathComponent("debagr")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
    let helper = bundle.resolvingSymlinksInPath().appendingPathComponent("USBIPProbe").path
    XCTAssertEqual(USBIPCommand.probeURL(executable: link).path, helper)
    XCTAssertEqual(USBIPCommand.probeURL(executable: executable).path, helper)
  }

  func testMissingToolErrorSaysWhatToInstallOrSelect() throws {
    let list = try USBIPCommand([
      "list", "--tool", "/nonexistent/usbip-macos", "--remote", "10.0.0.2",
    ])
    XCTAssertThrowsError(try list.run()) { error in
      let message = error.localizedDescription
      XCTAssertTrue(message.contains("/nonexistent/usbip-macos"), message)
      XCTAssertTrue(message.contains("Install usbip-macos"), message)
      XCTAssertTrue(message.contains("/opt/homebrew/bin or /usr/local/bin"), message)
      XCTAssertTrue(message.contains("--tool"), message)
    }
    XCTAssertTrue(
      USBIPCommand.missingTool("/x", action: "serve").contains("patched longcable-server"))
  }

  func testServerResolvesSerialAtCurrentLocationAndRejectsMissingOrDuplicateDevice() throws {
    let command = try USBIPCommand([
      "serve", "--tool", "/tool", "--listen", "100.80.103.100",
      "--peer", "100.98.191.109", "--serial", "phone",
    ])
    let device = USBIPDevice(
      serial: "phone", name: "iPhone", vendorID: 0x05ac,
      productID: 0x12a8, locationID: 0x0010_0000)
    XCTAssertEqual(
      try command.backendArguments(devices: [device]),
      ["100.80.103.100", "100.98.191.109", "05ac", "12a8", "00100000", "debagr"])
    XCTAssertThrowsError(try command.backendArguments(devices: []))
    XCTAssertThrowsError(try command.backendArguments(devices: [device, device]))
    let other = USBIPDevice(
      serial: "phone", name: "Other", vendorID: 1, productID: 2, locationID: 3)
    XCTAssertThrowsError(try command.backendArguments(devices: [other]))
    let keyboard = USBIPDevice(
      serial: "phone", name: "Apple Keyboard", vendorID: 0x05ac, productID: 2, locationID: 3)
    XCTAssertThrowsError(try command.backendArguments(devices: [keyboard]))
    let moved = USBIPDevice(
      serial: "phone", name: "iPhone", vendorID: 0x05ac,
      productID: 0x12a8, locationID: 0x0110_0000)
    XCTAssertEqual(try command.backendArguments(devices: [moved])[4], "01100000")
  }
}
