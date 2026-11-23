import DebagrBridge
import DebagrCore
import Foundation
import os

public struct CableBridgeGuide: Codable, Sendable, Equatable {
  public let label: String
  public let experimentalNotice: String
  public let clientCommand: String
  public let sshTunnelCommand: String
  public let builderCommand: String
  public let caveats: [String]

  public init(
    clientHost: String = "<user>@<client-vpn-ip>",
    deviceUDID: String = "<device-udid>",
    bonjourInstance: String = "<bonjour-instance>",
    port: UInt16 = 22078
  ) {
    self.label = "Experimental — USB via Mac (Cable Service Bridge)"
    self.experimentalNotice =
      "EXPERIMENTAL: Forwards lockdown/service TCP traffic (port 62078) of an ALREADY-PAIRED device plugged into a second Mac over SSH + private VPN. Does not transfer Apple trust, share raw USB, require root, or modify SIP."
    self.clientCommand =
      "debagr experimental cable-bridge client --udid \(deviceUDID) --port \(port)"
    self.sshTunnelCommand = "ssh -N -L 127.0.0.1:\(port):127.0.0.1:\(port) \(clientHost)"
    self.builderCommand =
      "debagr experimental cable-bridge builder --instance \(bonjourInstance) --port \(port)"
    self.caveats = [
      "Device must already be paired with the Builder Mac; this path does NOT support initial Apple USB pairing.",
      "Both relays bind strictly to 127.0.0.1 (loopback only); SSH provides encryption and authentication.",
      "Useful when the roaming iPhone/iPad has Wi-Fi turned off and is plugged via cable into another Mac.",
    ]
  }
}

public struct CableBridgeStatus: Codable, Sendable, Equatable {
  public let experimental: Bool
  public let role: String
  public let listeningAddress: String
  public let boundPort: UInt16
  public let targetDeviceUDIDRedacted: String?
  public let activeConnections: Int

  public init(
    role: String,
    listeningAddress: String,
    boundPort: UInt16,
    targetDeviceUDIDRedacted: String? = nil,
    activeConnections: Int = 0
  ) {
    self.experimental = true
    self.role = role
    self.listeningAddress = listeningAddress
    self.boundPort = boundPort
    self.targetDeviceUDIDRedacted = targetDeviceUDIDRedacted
    self.activeConnections = activeConnections
  }
}

public actor CableBridgeClientRelay {
  private let usbmuxd: UsbmuxdClient
  private let targetUDID: String
  private let requestedPort: UInt16
  private let devicePort: UInt16

  private var listenFD: Int32 = -1
  private var actualPort: UInt16 = 0
  private var acceptTask: Task<Void, Never>?
  private let activePumps = OSAllocatedUnfairLock(initialState: 0)
  private let stopSignal = OSAllocatedUnfairLock(initialState: false)

  public init(
    usbmuxd: UsbmuxdClient = UsbmuxdClient(),
    targetUDID: String,
    localPort: UInt16 = 22078,
    devicePort: UInt16 = VPNEndpoint.defaultLockdownPort
  ) {
    self.usbmuxd = usbmuxd
    self.targetUDID = targetUDID
    self.requestedPort = localPort
    self.devicePort = devicePort
  }

  deinit {
    stopSignal.withLock { $0 = true }
    if listenFD >= 0 {
      Darwin.close(listenFD)
    }
  }

  public func start() throws -> CableBridgeStatus {
    let devices = try usbmuxd.listUSBDevices()
    guard
      let matched = devices.first(where: {
        $0.serialNumber.caseInsensitiveCompare(targetUDID) == .orderedSame
      })
    else {
      throw DebagrError(
        code: .deviceNotFound,
        category: "experimental_cable_bridge",
        message:
          "No USB-attached device matching UDID \(Redactor.redactUDID(targetUDID)) found via usbmuxd.",
        recoverable: true,
        nextSteps: [
          "Plug the iPhone/iPad into this Mac with a USB cable and ensure it is unlocked."
        ]
      )
    }

    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw DebagrError(
        code: .bridgeError,
        category: "experimental_cable_bridge",
        message: "Failed creating loopback TCP socket: errno \(errno)."
      )
    }

    var reuse: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

    // Bind strictly to 127.0.0.1 loopback only — never 0.0.0.0
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = requestedPort.bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindRC = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindRC == 0 else {
      let err = errno
      Darwin.close(fd)
      throw DebagrError(
        code: .bridgeError,
        category: "experimental_cable_bridge",
        message: "Failed binding 127.0.0.1:\(requestedPort) (errno \(err))."
      )
    }

    guard Darwin.listen(fd, 16) == 0 else {
      let err = errno
      Darwin.close(fd)
      throw DebagrError(
        code: .bridgeError,
        category: "experimental_cable_bridge",
        message: "Failed listening on loopback socket (errno \(err))."
      )
    }

    var boundAddr = sockaddr_in()
    var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &boundAddr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        getsockname(fd, sockPtr, &boundLen)
      }
    }

    self.listenFD = fd
    self.actualPort = UInt16(bigEndian: boundAddr.sin_port)
    stopSignal.withLock { $0 = false }

    let deviceID = matched.deviceID
    let devPort = self.devicePort
    let mux = self.usbmuxd
    let signal = self.stopSignal
    let pumpCounter = self.activePumps

    acceptTask = Task.detached {
      while !signal.withLock({ $0 }) {
        var clientAddr = sockaddr_in()
        var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
          ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            Darwin.accept(fd, sockPtr, &clientLen)
          }
        }
        if clientFD < 0 {
          if errno == EINTR { continue }
          break
        }

        Task.detached {
          pumpCounter.withLock { $0 += 1 }
          defer {
            Darwin.close(clientFD)
            pumpCounter.withLock { $0 = max(0, $0 - 1) }
          }
          do {
            let deviceFD = try mux.connectToDevicePort(deviceID: deviceID, port: devPort)
            defer { Darwin.close(deviceFD) }
            Self.pumpBidirectional(fdA: clientFD, fdB: deviceFD, stopSignal: signal)
          } catch {
            // Connection fails cleanly if device unplugged or port rejected
          }
        }
      }
    }

    return CableBridgeStatus(
      role: "client-relay",
      listeningAddress: "127.0.0.1",
      boundPort: actualPort,
      targetDeviceUDIDRedacted: Redactor.redactUDID(targetUDID),
      activeConnections: activePumps.withLock { $0 }
    )
  }

  public func status() -> CableBridgeStatus {
    CableBridgeStatus(
      role: "client-relay",
      listeningAddress: "127.0.0.1",
      boundPort: actualPort,
      targetDeviceUDIDRedacted: Redactor.redactUDID(targetUDID),
      activeConnections: activePumps.withLock { $0 }
    )
  }

  public func stop() {
    stopSignal.withLock { $0 = true }
    acceptTask?.cancel()
    acceptTask = nil
    if listenFD >= 0 {
      Darwin.close(listenFD)
      listenFD = -1
    }
  }

  private static func pumpBidirectional(
    fdA: Int32,
    fdB: Int32,
    stopSignal: OSAllocatedUnfairLock<Bool>
  ) {
    var buffer = [UInt8](repeating: 0, count: 16_384)
    var fds = [
      pollfd(fd: fdA, events: Int16(POLLIN), revents: 0),
      pollfd(fd: fdB, events: Int16(POLLIN), revents: 0),
    ]

    while !stopSignal.withLock({ $0 }) {
      fds[0].revents = 0
      fds[1].revents = 0
      let ready = Darwin.poll(&fds, nfds_t(2), 250)
      if ready < 0 {
        if errno == EINTR { continue }
        break
      }
      if ready == 0 { continue }

      if (fds[0].revents & Int16(POLLIN)) != 0 {
        if !forwardOnce(from: fdA, to: fdB, buffer: &buffer) { break }
      }
      if (fds[1].revents & Int16(POLLIN)) != 0 {
        if !forwardOnce(from: fdB, to: fdA, buffer: &buffer) { break }
      }
      if (fds[0].revents & Int16(POLLHUP | POLLERR | POLLNVAL)) != 0
        || (fds[1].revents & Int16(POLLHUP | POLLERR | POLLNVAL)) != 0
      {
        break
      }
    }
  }

  private static func forwardOnce(from src: Int32, to dst: Int32, buffer: inout [UInt8]) -> Bool {
    let n = buffer.withUnsafeMutableBytes { raw -> ssize_t in
      guard let base = raw.baseAddress else { return -1 }
      return Darwin.read(src, base, raw.count)
    }
    if n <= 0 { return false }
    var offset = 0
    while offset < n {
      let written = buffer.withUnsafeBytes { raw -> ssize_t in
        guard let base = raw.baseAddress else { return -1 }
        return Darwin.write(dst, base.advanced(by: offset), n - offset)
      }
      if written < 0 {
        if errno == EINTR { continue }
        return false
      }
      offset += written
    }
    return true
  }
}

public actor CableBridgeBuilderSession {
  private let dnssd: any DNSSDControlling
  private let tcpProbe: any TCPProbing
  private var activeHandle: ProxyHandle?

  public init(
    dnssd: any DNSSDControlling = SystemDNSSDController(),
    tcpProbe: any TCPProbing = NWConnectionTCPProbe()
  ) {
    self.dnssd = dnssd
    self.tcpProbe = tcpProbe
  }

  public func start(instanceName: String, forwardedPort: UInt16) async throws -> CableBridgeStatus {
    let reachable = await tcpProbe.probe(
      host: "127.0.0.1",
      port: forwardedPort,
      timeoutSeconds: 3.0
    )
    guard reachable else {
      throw DebagrError(
        code: .bridgeError,
        category: "experimental_cable_bridge",
        message: "Loopback forwarded port 127.0.0.1:\(forwardedPort) is not reachable.",
        recoverable: true,
        nextSteps: [
          "Ensure `debagr experimental cable-bridge client` is running on the Client Mac.",
          "Ensure your SSH local port forward (`ssh -N -L 127.0.0.1:\(forwardedPort):127.0.0.1:\(forwardedPort) ...`) is active.",
        ]
      )
    }

    let spec = ProxyRegistrationSpec(
      instanceName: instanceName,
      port: forwardedPort,
      proxyHost: "debagr-cable.local.",
      targetIP: "127.0.0.1",
      txtRecords: [:]
    )
    let handle = try await dnssd.startProxy(spec)
    activeHandle = handle
    return CableBridgeStatus(
      role: "builder-proxy",
      listeningAddress: "127.0.0.1",
      boundPort: forwardedPort,
      targetDeviceUDIDRedacted: nil,
      activeConnections: 0
    )
  }

  public func stop() async {
    if let activeHandle {
      self.activeHandle = nil
      await dnssd.stopProxy(activeHandle)
    }
  }
}
