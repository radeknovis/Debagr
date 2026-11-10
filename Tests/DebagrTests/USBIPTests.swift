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
    ] { XCTAssertThrowsError(try USBIPCommand(arguments), "\(arguments)") }
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
    let moved = USBIPDevice(
      serial: "phone", name: "iPhone", vendorID: 0x05ac,
      productID: 0x12a8, locationID: 0x0110_0000)
    XCTAssertEqual(try command.backendArguments(devices: [moved])[4], "01100000")
  }
}
