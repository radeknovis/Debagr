import Foundation
import Network

struct USBIPRemoteDevice: Equatable {
  let busID: String
  let vendorID: UInt16
  let productID: UInt16
}

enum USBIPRemoteInventory {
  static func parse(_ data: Data) throws -> [USBIPRemoteDevice]? {
    guard data.count <= 1_048_576 else {
      throw USBIPError.invalid("USB device list exceeds the supported size.")
    }
    guard data.count >= 12 else { return nil }
    guard DebagrPeerDiscovery.isUSBIPReply(data) else {
      throw USBIPError.invalid("The Client did not return a valid USB/IP device list.")
    }
    let bytes = Array(data)
    func u16(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1]) }
    let count =
      UInt32(bytes[8]) << 24 | UInt32(bytes[9]) << 16 | UInt32(bytes[10]) << 8 | UInt32(bytes[11])
    guard count <= 128 else { throw USBIPError.invalid("Too many exported USB devices.") }
    var devices: [USBIPRemoteDevice] = []
    var offset = 12
    for _ in 0..<count {
      guard bytes.count >= offset + 312 else { return nil }
      let rawBus = bytes[(offset + 256)..<(offset + 288)].prefix { $0 != 0 }
      guard let bus = String(bytes: rawBus, encoding: .utf8),
        bus.range(of: #"^[0-9]+-[0-9]+(\.[0-9]+)*$"#, options: .regularExpression) != nil
      else {
        throw USBIPError.invalid("The Client returned an invalid USB bus ID.")
      }
      devices.append(
        USBIPRemoteDevice(busID: bus, vendorID: u16(offset + 300), productID: u16(offset + 302)))
      offset += 312 + Int(bytes[offset + 311]) * 4
      guard bytes.count >= offset else { return nil }
    }
    return devices
  }

  static func list(host: String) throws -> [USBIPRemoteDevice] {
    guard NetworkSupport.isAllowedPrivateVPNIPv4(host) else {
      throw USBIPError.invalid("Choose a private IPv4 address for the Client.")
    }
    let connection = NWConnection(host: NWEndpoint.Host(host), port: 3240, using: .tcp)
    let queue = DispatchQueue(label: "debagr.usbip-list")
    let completed = DispatchSemaphore(value: 0)
    let result = LockedValue<Result<[USBIPRemoteDevice], Error>?>(nil)
    var buffer = Data()
    func finish(_ value: Result<[USBIPRemoteDevice], Error>) {
      guard result.get() == nil else { return }
      result.set(value)
      connection.stateUpdateHandler = nil
      connection.cancel()
      completed.signal()
    }
    func read() {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
        data, _, complete, error in
        if let data { buffer.append(data) }
        do {
          if let devices = try parse(buffer) {
            finish(.success(devices))
          } else if complete || error != nil {
            finish(.failure(USBIPError.invalid("The Client closed an incomplete USB device list.")))
          } else {
            read()
          }
        } catch { finish(.failure(error)) }
      }
    }
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        connection.send(
          content: Data([1, 17, 128, 5, 0, 0, 0, 0]),
          completion: .contentProcessed { error in
            if let error { finish(.failure(error)) } else { read() }
          })
      case .failed(let error): finish(.failure(error))
      default: break
      }
    }
    connection.start(queue: queue)
    if completed.wait(timeout: .now() + 5) == .timedOut {
      queue.async {
        finish(
          .failure(
            USBIPError.invalid(
              "Client timed out. Start Connection on the Client first, then retry.")))
      }
      completed.wait()
    }
    return try result.get()!.get()
  }
}
