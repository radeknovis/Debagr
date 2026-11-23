import DebagrCore
import Foundation

public struct UsbmuxdHeader: Sendable, Equatable {
  public static let byteSize = 16
  public static let plistProtocolVersion: UInt32 = 1
  public static let plistMessageType: UInt32 = 8

  public let length: UInt32
  public let version: UInt32
  public let messageType: UInt32
  public let tag: UInt32

  public init(
    length: UInt32,
    version: UInt32 = UsbmuxdHeader.plistProtocolVersion,
    messageType: UInt32 = UsbmuxdHeader.plistMessageType,
    tag: UInt32
  ) {
    self.length = length
    self.version = version
    self.messageType = messageType
    self.tag = tag
  }

  public func encode() -> Data {
    var data = Data(capacity: Self.byteSize)
    var leLength = length.littleEndian
    var leVersion = version.littleEndian
    var leType = messageType.littleEndian
    var leTag = tag.littleEndian
    withUnsafeBytes(of: &leLength) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: &leVersion) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: &leType) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: &leTag) { data.append(contentsOf: $0) }
    return data
  }

  public static func decode(from data: Data) throws -> UsbmuxdHeader {
    guard data.count >= byteSize else {
      throw DebagrError(
        code: .bridgeError,
        category: "usbmuxd",
        message: "Truncated usbmuxd header (\(data.count) bytes)."
      )
    }
    func readLE32(_ offset: Int) -> UInt32 {
      var val: UInt32 = 0
      _ = withUnsafeMutableBytes(of: &val) { dst in
        data.copyBytes(to: dst, from: offset..<(offset + 4))
      }
      return UInt32(littleEndian: val)
    }
    return UsbmuxdHeader(
      length: readLE32(0),
      version: readLE32(4),
      messageType: readLE32(8),
      tag: readLE32(12)
    )
  }
}

public struct UsbmuxdAttachedDevice: Codable, Sendable, Equatable, Identifiable {
  public var id: Int { deviceID }
  public let deviceID: Int
  public let serialNumber: String
  public let connectionType: String

  public init(deviceID: Int, serialNumber: String, connectionType: String) {
    self.deviceID = deviceID
    self.serialNumber = serialNumber
    self.connectionType = connectionType
  }
}

public enum UsbmuxdProtocol: Sendable {
  public static let defaultSocketPath = "/var/run/usbmuxd"

  public static func encodeListDevicesPacket(tag: UInt32 = 1) throws -> Data {
    let plist: [String: Any] = [
      "MessageType": "ListDevices",
      "ClientVersionString": "Debagr-\(DebagrVersion.current)",
      "ProgName": "Debagr",
    ]
    return try encodePlistPacket(plist, tag: tag)
  }

  public static func encodeConnectPacket(
    deviceID: Int,
    port: UInt16 = VPNEndpoint.defaultLockdownPort,
    tag: UInt32 = 2
  ) throws -> Data {
    // Apple usbmuxd requires PortNumber in network byte order (big-endian).
    let networkPort = Int(port.bigEndian)
    let plist: [String: Any] = [
      "MessageType": "Connect",
      "ClientVersionString": "Debagr-\(DebagrVersion.current)",
      "ProgName": "Debagr",
      "DeviceID": deviceID,
      "PortNumber": networkPort,
    ]
    return try encodePlistPacket(plist, tag: tag)
  }

  public static func encodePlistPacket(_ dictionary: [String: Any], tag: UInt32) throws -> Data {
    let body = try PropertyListSerialization.data(
      fromPropertyList: dictionary, format: .xml, options: 0)
    let totalLength = UInt32(UsbmuxdHeader.byteSize + body.count)
    let header = UsbmuxdHeader(length: totalLength, tag: tag).encode()
    var packet = Data(capacity: Int(totalLength))
    packet.append(header)
    packet.append(body)
    return packet
  }

  public static func decodePlistDictionary(from body: Data) throws -> [String: Any] {
    let obj = try PropertyListSerialization.propertyList(from: body, options: [], format: nil)
    guard let dict = obj as? [String: Any] else {
      throw DebagrError(
        code: .bridgeError,
        category: "usbmuxd",
        message: "usbmuxd response payload is not a plist dictionary."
      )
    }
    return dict
  }

  public static func parseDeviceList(from dict: [String: Any]) -> [UsbmuxdAttachedDevice] {
    guard let rawList = dict["DeviceList"] as? [[String: Any]] else { return [] }
    return rawList.compactMap { entry -> UsbmuxdAttachedDevice? in
      guard let props = entry["Properties"] as? [String: Any],
        let deviceID = props["DeviceID"] as? Int,
        let serial = props["SerialNumber"] as? String
      else {
        return nil
      }
      let connectionType = (props["ConnectionType"] as? String) ?? "Unknown"
      return UsbmuxdAttachedDevice(
        deviceID: deviceID,
        serialNumber: serial,
        connectionType: connectionType
      )
    }
  }

  public static func parseResultCode(from dict: [String: Any]) -> Int? {
    guard (dict["MessageType"] as? String) == "Result" else { return nil }
    return dict["Number"] as? Int
  }
}

public final class UsbmuxdClient: Sendable {
  public let socketPath: String

  public init(socketPath: String = UsbmuxdProtocol.defaultSocketPath) {
    self.socketPath = socketPath
  }

  public func listUSBDevices() throws -> [UsbmuxdAttachedDevice] {
    let fd = try openUnixSocket()
    defer { Darwin.close(fd) }

    let req = try UsbmuxdProtocol.encodeListDevicesPacket(tag: 1)
    try writeAll(req, to: fd)
    let (_, body) = try readPacket(from: fd)
    let dict = try UsbmuxdProtocol.decodePlistDictionary(from: body)
    return UsbmuxdProtocol.parseDeviceList(from: dict)
      .filter { $0.connectionType.caseInsensitiveCompare("USB") == .orderedSame }
  }

  /// Opens a connected usbmuxd stream fd directly to `port` (default 62078) on `deviceID`.
  /// Caller owns the returned file descriptor and must close it when done.
  public func connectToDevicePort(
    deviceID: Int,
    port: UInt16 = VPNEndpoint.defaultLockdownPort
  ) throws -> Int32 {
    let fd = try openUnixSocket()
    do {
      let req = try UsbmuxdProtocol.encodeConnectPacket(deviceID: deviceID, port: port, tag: 2)
      try writeAll(req, to: fd)
      let (_, body) = try readPacket(from: fd)
      let dict = try UsbmuxdProtocol.decodePlistDictionary(from: body)
      guard let code = UsbmuxdProtocol.parseResultCode(from: dict), code == 0 else {
        let codeStr = UsbmuxdProtocol.parseResultCode(from: dict).map(String.init) ?? "unknown"
        throw DebagrError(
          code: .bridgeError,
          category: "usbmuxd",
          message: "usbmuxd Connect to device \(deviceID) port \(port) failed (code \(codeStr))."
        )
      }
      return fd
    } catch {
      Darwin.close(fd)
      throw error
    }
  }

  private func openUnixSocket() throws -> Int32 {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw DebagrError(
        code: .bridgeError,
        category: "usbmuxd",
        message: "Failed opening AF_UNIX socket for usbmuxd: errno \(errno)."
      )
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(socketPath.utf8)
    let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path)
    guard pathBytes.count < maxPathLen else {
      Darwin.close(fd)
      throw DebagrError(
        code: .bridgeError,
        category: "usbmuxd",
        message: "usbmuxd socket path is too long."
      )
    }

    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
      ptr.withMemoryRebound(to: UInt8.self, capacity: maxPathLen) { buf in
        buf.initialize(repeating: 0, count: maxPathLen)
        for (idx, byte) in pathBytes.enumerated() {
          buf[idx] = byte
        }
      }
    }

    let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
    let rc = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        Darwin.connect(fd, sockPtr, addrLen)
      }
    }
    guard rc == 0 else {
      let err = errno
      Darwin.close(fd)
      throw DebagrError(
        code: .bridgeError,
        category: "usbmuxd",
        message: "Failed connecting to usbmuxd socket at \(socketPath) (errno \(err))."
      )
    }
    return fd
  }

  private func readPacket(from fd: Int32) throws -> (UsbmuxdHeader, Data) {
    let headerData = try readExact(count: UsbmuxdHeader.byteSize, from: fd)
    let header = try UsbmuxdHeader.decode(from: headerData)
    let bodyCount = Int(header.length) - UsbmuxdHeader.byteSize
    guard bodyCount >= 0, bodyCount <= 4 * 1024 * 1024 else {
      throw DebagrError(
        code: .bridgeError,
        category: "usbmuxd",
        message: "Invalid usbmuxd response frame length \(header.length)."
      )
    }
    let body = try readExact(count: bodyCount, from: fd)
    return (header, body)
  }

  private func readExact(count: Int, from fd: Int32) throws -> Data {
    var buffer = Data(count: count)
    var received = 0
    while received < count {
      let n = buffer.withUnsafeMutableBytes { raw -> ssize_t in
        guard let base = raw.baseAddress else { return -1 }
        return Darwin.read(fd, base.advanced(by: received), count - received)
      }
      if n < 0 {
        if errno == EINTR { continue }
        throw DebagrError(
          code: .bridgeError,
          category: "usbmuxd",
          message: "Failed reading from usbmuxd socket: errno \(errno)."
        )
      }
      if n == 0 {
        throw DebagrError(
          code: .bridgeError,
          category: "usbmuxd",
          message: "Unexpected EOF from usbmuxd socket."
        )
      }
      received += n
    }
    return buffer
  }

  private func writeAll(_ data: Data, to fd: Int32) throws {
    var sent = 0
    while sent < data.count {
      let n = data.withUnsafeBytes { raw -> ssize_t in
        guard let base = raw.baseAddress else { return -1 }
        return Darwin.write(fd, base.advanced(by: sent), data.count - sent)
      }
      if n < 0 {
        if errno == EINTR { continue }
        throw DebagrError(
          code: .bridgeError,
          category: "usbmuxd",
          message: "Failed writing to usbmuxd socket: errno \(errno)."
        )
      }
      sent += n
    }
  }
}
