import DebagrBridge
import DebagrCLI
import DebagrCore
import Foundation
import Testing

@testable import DebagrExperimental

@Suite("Experimental Cable Service Bridge & USB/IP Pairing")
struct ExperimentalTests {
  @Test("Usbmuxd protocol encodes 16-byte LE header and big-endian PortNumber")
  func usbmuxdProtocolEncoding() throws {
    let listPacket = try UsbmuxdProtocol.encodeListDevicesPacket(tag: 7)
    let listHeader = try UsbmuxdHeader.decode(from: listPacket)
    #expect(listHeader.version == UsbmuxdHeader.plistProtocolVersion)
    #expect(listHeader.messageType == UsbmuxdHeader.plistMessageType)
    #expect(listHeader.tag == 7)
    #expect(Int(listHeader.length) == listPacket.count)

    let connectPacket = try UsbmuxdProtocol.encodeConnectPacket(deviceID: 42, port: 62078, tag: 9)
    let body = connectPacket.dropFirst(UsbmuxdHeader.byteSize)
    let dict = try UsbmuxdProtocol.decodePlistDictionary(from: Data(body))
    #expect((dict["MessageType"] as? String) == "Connect")
    #expect((dict["DeviceID"] as? Int) == 42)
    #expect((dict["PortNumber"] as? Int) == Int(UInt16(62078).bigEndian))
  }

  @Test("CableBridgeClientRelay relays loopback TCP connections to mock AF_UNIX usbmuxd")
  func cableBridgeEndToEndRelay() async throws {
    let sockPath = FileManager.default.temporaryDirectory
      .appendingPathComponent("debagr-mux-\(UUID().uuidString.prefix(8)).sock")
      .path
    defer { unlink(sockPath) }

    let mockServer = try MockUsbmuxdServer(
      socketPath: sockPath,
      udid: "00008140-001E45990413C01C",
      deviceID: 11
    )
    mockServer.start()
    defer { mockServer.stop() }

    let relay = CableBridgeClientRelay(
      usbmuxd: UsbmuxdClient(socketPath: sockPath),
      targetUDID: "00008140-001E45990413C01C",
      localPort: 0
    )
    let status = try await relay.start()
    #expect(status.listeningAddress == "127.0.0.1")
    #expect(status.boundPort > 0)
    #expect(status.experimental)

    // Connect a TCP client to 127.0.0.1:boundPort and exchange bytes through mock usbmuxd tunnel
    let reply = try Self.tcpRoundTrip(port: status.boundPort, payload: Data("hello-lockdown".utf8))
    #expect(String(decoding: reply, as: UTF8.self) == "echo:hello-lockdown")

    await relay.stop()
  }

  @Test("PairingCrypto authenticates matching SAS, rejects wrong SAS, role swap, and replay")
  func pairingCryptoSecurity() throws {
    let sessionID = "sess-42"
    let builder = PairingCryptoSession(sessionID: sessionID, role: .builder, sasCode: "654321")
    let client = PairingCryptoSession(sessionID: sessionID, role: .client, sasCode: "654321")

    let builderChannel = try builder.establishChannel(with: client.localHello)
    let clientChannel = try client.establishChannel(with: builder.localHello)

    try builderChannel.verifyPeerProof(clientChannel.makeLocalProof())
    try clientChannel.verifyPeerProof(builderChannel.makeLocalProof())

    let msg = Data("attach bus-1-2".utf8)
    let sealed = try builderChannel.sealControlMessage(msg)
    let opened = try clientChannel.openControlMessage(sealed)
    #expect(opened == msg)

    // Replay must fail
    #expect(throws: DebagrError.self) {
      _ = try clientChannel.openControlMessage(sealed)
    }

    // Wrong SAS must fail proof verification
    let wrongClient = PairingCryptoSession(sessionID: sessionID, role: .client, sasCode: "000000")
    let wrongChannel = try wrongClient.establishChannel(with: builder.localHello)
    #expect(throws: DebagrError.self) {
      try builderChannel.verifyPeerProof(wrongChannel.makeLocalProof())
    }

    // Role swap must fail
    let impersonator = PairingCryptoSession(sessionID: sessionID, role: .builder, sasCode: "654321")
    #expect(throws: DebagrError.self) {
      _ = try builder.establishChannel(with: impersonator.localHello)
    }
  }

  @Test(
    "USBIPSessionCoordinator requires explicit approval, supervises pairing, tears down, and yields wireless handoff"
  )
  func usbipCoordinatorWorkflow() async throws {
    let stubDevicectl = ExperimentalMockDeviceCtl()
    let stubSupervisor = ExperimentalMockToolSupervisor()
    let coordinator = USBIPSessionCoordinator(
      devicectl: stubDevicectl,
      toolSupervisor: stubSupervisor,
      peerDiscovery: SystemUSBIPPeerDiscovery()
    )

    let prereqs = await coordinator.checkPrerequisites(customBinaryPath: "/nonexistent/usbip")
    #expect(prereqs.experimental)

    let (builderHello, sas) = await coordinator.beginSession(
      role: .builder, sessionID: "s-1", sasCode: "112233")
    let clientSession = PairingCryptoSession(sessionID: "s-1", role: .client, sasCode: sas)
    let clientChannel = try clientSession.establishChannel(with: builderHello)

    let peer = DiscoveredUSBIPPeer(
      name: "client-mac", host: "100.64.5.5", port: 3240, source: "manual-private-vpn")
    let builderProof = try await coordinator.completePeerAuthentication(
      peer: peer,
      peerHello: clientSession.localHello,
      peerProof: clientChannel.makeLocalProof()
    )
    try clientChannel.verifyPeerProof(builderProof)

    // Unconfirmed security notice must be rejected
    let unapproved = PrivilegedApprovalReceipt(
      sessionID: "s-1",
      role: .builder,
      commandDescription: "usbip attach",
      userConfirmedSecurityNotice: false
    )
    await #expect(throws: DebagrError.self) {
      _ = try await coordinator.activateUSBIPAndPair(
        targetDeviceHint: "00008140-001E45990413C01C",
        approval: unapproved,
        binaryPath: "/usr/local/bin/usbip",
        arguments: ["attach"]
      )
    }

    // Approved notice runs supervised attach + pairing + teardown -> WirelessHandoffPayload
    let approved = PrivilegedApprovalReceipt(
      sessionID: "s-1",
      role: .builder,
      commandDescription: "usbip attach",
      userConfirmedSecurityNotice: true
    )
    let handoff = try await coordinator.activateUSBIPAndPair(
      targetDeviceHint: "00008140-001E45990413C01C",
      approval: approved,
      binaryPath: "/usr/local/bin/usbip",
      arguments: ["attach"]
    )
    #expect(handoff.pairedDevice.udid == "00008140-001E45990413C01C")
    #expect(await coordinator.phase == .tornDownReadyForWirelessHandoff)
    #expect(await stubSupervisor.stopCalls >= 1)
  }

  @Test("CLI experimental guide and usbip check commands emit experimental labels")
  func experimentalCLICommands() async throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("debagr-exp-cli-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let out = TestExpCLIOutput()
    let runner = CLIRunner(
      configStore: FileConfigStore(directoryURL: dir),
      receiptStore: FileReceiptStore(directoryURL: dir),
      experimentalHandler: LiveExperimentalCLIHandler(),
      output: out
    )

    let code1 = await runner.run(arguments: [
      "experimental", "cable-bridge", "guide", "--client-host", "dev@100.64.2.2",
    ])
    #expect(code1 == 0)
    #expect(out.text.contains("EXPERIMENTAL"))
    #expect(out.text.contains("127.0.0.1:22078:127.0.0.1:22078 dev@100.64.2.2"))

    out.clear()
    let code2 = await runner.run(arguments: ["experimental", "usbip", "check"])
    #expect(code2 == 0)
    #expect(out.text.contains("\"experimental\" : true"))
  }

  private static func tcpRoundTrip(port: UInt16, payload: Data) throws -> Data {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw POSIXError(.EIO) }
    defer { Darwin.close(fd) }

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let rc = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard rc == 0 else { throw POSIXError(.ECONNREFUSED) }

    _ = payload.withUnsafeBytes { raw in
      Darwin.write(fd, raw.baseAddress!, raw.count)
    }

    var buf = [UInt8](repeating: 0, count: 256)
    let n = Darwin.read(fd, &buf, buf.count)
    guard n > 0 else { return Data() }
    return Data(buf.prefix(n))
  }
}

private final class MockUsbmuxdServer: @unchecked Sendable {
  private let listenFD: Int32
  private let udid: String
  private let deviceID: Int
  private var thread: Thread?
  private let lock = NSLock()
  private var stopped = false

  init(socketPath: String, udid: String, deviceID: Int) throws {
    self.udid = udid
    self.deviceID = deviceID
    unlink(socketPath)
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw POSIXError(.EIO) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(socketPath.utf8)
    let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
      ptr.withMemoryRebound(to: UInt8.self, capacity: maxLen) { dst in
        dst.initialize(repeating: 0, count: maxLen)
        for (i, b) in bytes.enumerated() where i < maxLen - 1 {
          dst[i] = b
        }
      }
    }
    let rc = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard rc == 0, Darwin.listen(fd, 8) == 0 else {
      Darwin.close(fd)
      throw POSIXError(.EIO)
    }
    self.listenFD = fd
  }

  func start() {
    let t = Thread { [weak self] in
      self?.serveLoop()
    }
    self.thread = t
    t.start()
  }

  func stop() {
    lock.withLock { stopped = true }
    Darwin.close(listenFD)
  }

  private func serveLoop() {
    while !lock.withLock({ stopped }) {
      var addr = sockaddr_un()
      var len = socklen_t(MemoryLayout<sockaddr_un>.size)
      let clientFD = withUnsafeMutablePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
          Darwin.accept(listenFD, sockPtr, &len)
        }
      }
      if clientFD < 0 { break }
      Thread.detachNewThread { [udid, deviceID] in
        Self.handleClient(clientFD, udid: udid, deviceID: deviceID)
      }
    }
  }

  private static func handleClient(_ fd: Int32, udid: String, deviceID: Int) {
    defer { Darwin.close(fd) }
    guard let (header, dict) = try? readPlistPacket(from: fd),
      let msgType = dict["MessageType"] as? String
    else { return }

    if msgType == "ListDevices" {
      let resp: [String: Any] = [
        "DeviceList": [
          [
            "MessageType": "Attached",
            "DeviceID": deviceID,
            "Properties": [
              "DeviceID": deviceID,
              "SerialNumber": udid,
              "ConnectionType": "USB",
            ],
          ]
        ]
      ]
      if let data = try? UsbmuxdProtocol.encodePlistPacket(resp, tag: header.tag) {
        _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
      }
    } else if msgType == "Connect" {
      let resp: [String: Any] = ["MessageType": "Result", "Number": 0]
      if let data = try? UsbmuxdProtocol.encodePlistPacket(resp, tag: header.tag) {
        _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
      }
      var buf = [UInt8](repeating: 0, count: 512)
      let n = Darwin.read(fd, &buf, buf.count)
      if n > 0 {
        let reply = Data("echo:".utf8) + Data(buf.prefix(n))
        _ = reply.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
      }
    }
  }

  private static func readPlistPacket(from fd: Int32) throws -> (UsbmuxdHeader, [String: Any]) {
    var hdr = Data(count: UsbmuxdHeader.byteSize)
    var got = 0
    while got < UsbmuxdHeader.byteSize {
      let n = hdr.withUnsafeMutableBytes {
        Darwin.read(fd, $0.baseAddress!.advanced(by: got), UsbmuxdHeader.byteSize - got)
      }
      if n <= 0 { throw POSIXError(.EIO) }
      got += n
    }
    let header = try UsbmuxdHeader.decode(from: hdr)
    let bodyCount = Int(header.length) - UsbmuxdHeader.byteSize
    var body = Data(count: bodyCount)
    var bodyGot = 0
    while bodyGot < bodyCount {
      let n = body.withUnsafeMutableBytes {
        Darwin.read(fd, $0.baseAddress!.advanced(by: bodyGot), bodyCount - bodyGot)
      }
      if n <= 0 { throw POSIXError(.EIO) }
      bodyGot += n
    }
    let dict = try UsbmuxdProtocol.decodePlistDictionary(from: body)
    return (header, dict)
  }
}

actor ExperimentalMockDeviceCtl: DeviceControlling {
  private var paired = false
  func version() async throws -> String? { "651.31" }
  func listDevices(timeout: TimeInterval) async throws -> [PhysicalDevice] {
    [
      PhysicalDevice(
        coreDeviceID: "CORE-1",
        udid: "00008140-001E45990413C01C",
        name: "Remote iPhone",
        model: "iPhone 16 Pro",
        platform: .iOS,
        osVersion: "27.3",
        reality: .physical,
        pairingState: paired ? .paired : .unpaired,
        transportType: .wired,
        tunnelState: .connected
      )
    ]
  }
  func deviceDetails(identifier: String, timeout: TimeInterval) async throws -> PhysicalDevice {
    try await listDevices(timeout: timeout)[0]
  }
  func lockState(identifier: String, timeout: TimeInterval) async throws -> LockState { .unlocked }
  func listApps(identifier: String, bundleID: String?, timeout: TimeInterval) async throws
    -> [InstalledApp]
  { [] }
  func installApp(identifier: String, appPath: String, timeout: TimeInterval) async throws
    -> DeviceCtlInstallOutcome
  { DeviceCtlInstallOutcome(bundleIdentifier: nil, launchServicesIdentifier: nil) }
  func launchApp(
    identifier: String,
    bundleID: String,
    arguments: [String],
    environment: [String: String],
    terminateExisting: Bool,
    launchServicesIdentifier: String?,
    timeout: TimeInterval
  ) async throws -> DeviceCtlLaunchOutcome { DeviceCtlLaunchOutcome(pid: 1) }
  func pairDevice(identifier: String, timeout: TimeInterval) async throws {
    paired = true
  }
}

actor ExperimentalMockToolSupervisor: USBIPSupervising {
  private(set) var startCalls = 0
  private(set) var stopCalls = 0

  nonisolated func checkPrerequisites(customBinaryPath: String?) -> USBIPToolPrerequisites {
    USBIPToolPrerequisites(
      usbipBinaryPath: "/usr/local/bin/usbip", usbipAvailable: true, summary: "Mock")
  }

  func startSupervisedSession(
    binaryPath: String,
    arguments: [String],
    approval: PrivilegedApprovalReceipt
  ) async throws {
    startCalls += 1
  }

  func stopSupervisedSession() async {
    stopCalls += 1
  }
}

final class TestExpCLIOutput: CLIOutputWriting, @unchecked Sendable {
  private let lock = NSLock()
  private var buf = ""
  var text: String { lock.withLock { buf } }
  func clear() { lock.withLock { buf = "" } }
  func writeStdout(_ text: String) { lock.withLock { buf += text } }
  func writeStderr(_ text: String) {}
}
