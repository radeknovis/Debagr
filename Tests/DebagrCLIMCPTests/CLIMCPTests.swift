import DebagrBridge
import DebagrCore
import Foundation
import Testing

@testable import DebagrCLI
@testable import DebagrMCP

@Suite("CLI & MCP Server")
struct CLIMCPTests {
  private func makeHarness(
    configured: Bool = true,
    lockState: LockState = .unlocked,
    launchError: DebagrError? = nil,
    installError: DebagrError? = nil
  ) throws -> (
    dir: URL,
    runner: CLIRunner,
    output: MemoryCLIOutput,
    registry: MCPToolRegistry
  ) {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("debagr-climcp-test-\(UUID().uuidString)", isDirectory: true)
    let cfg = FileConfigStore(directoryURL: dir)
    if configured {
      let fixed = Date(timeIntervalSince1970: 1_700_000_000)
      try cfg.save(
        DebagrConfig(
          managedDevice: ManagedDeviceProfile(
            udid: "00008140-001E45990413C01C",
            coreDeviceID: "CORE-1",
            displayName: "Pocket iPhone",
            model: "iPhone 16 Pro",
            platform: .iOS,
            vpn: VPNEndpoint(provider: .tailscale, address: "100.64.22.33"),
            wirelessIdentity: WirelessIdentity(
              bonjourInstanceName: "12:34:56:78:9a:bc@deadbeef00112233",
              txtRecords: ["pair": "secret-txt"],
              confirmedHardwareUDID: "00008140-001E45990413C01C",
              capturedAt: fixed
            ),
            savedAt: fixed
          )
        )
      )
    }

    let device = PhysicalDevice(
      coreDeviceID: "CORE-1",
      udid: "00008140-001E45990413C01C",
      name: "Pocket iPhone",
      model: "iPhone 16 Pro",
      platform: .iOS,
      osVersion: "27.3",
      reality: .physical,
      pairingState: .paired,
      transportType: .localNetwork,
      tunnelState: .connected,
      isDeveloperModeEnabled: true
    )

    let devicectl = TestCLIStubDeviceCtl(
      devices: [device],
      lockStateValue: lockState,
      apps: [InstalledApp(bundleIdentifier: "com.example.demo", name: "Demo")],
      installOutcome: DeviceCtlInstallOutcome(
        bundleIdentifier: "com.example.demo",
        launchServicesIdentifier: "LS-777"
      ),
      installError: installError,
      launchError: launchError
    )

    let receipts = FileReceiptStore(directoryURL: dir)
    let bridgeStore = FileBridgeStateStore(directoryURL: dir)
    let supervisor = WirelessBridgeSupervisor(
      configStore: cfg,
      bridgeStateStore: bridgeStore,
      devicectl: devicectl,
      dnssd: TestStubDNSSD(),
      tcpProbe: TestStubTCPProbe(),
      vpnDiscovery: TestStubVPNDiscovery()
    )

    let bundle = ValidatedAppBundle(
      path: "/tmp/Demo.app",
      bundleIdentifier: "com.example.demo",
      displayName: "Demo",
      shortVersion: "1.0",
      buildVersion: "1",
      platformName: "iphoneos",
      signingAuthority: "Apple Development"
    )

    let coordinator = DeploymentCoordinator(
      devicectl: devicectl,
      appValidator: TestStubBundleValidator(bundle: bundle),
      configStore: cfg,
      receiptStore: receipts,
      bridgeStateStore: bridgeStore,
      vpnDiscovery: TestStubVPNDiscovery(),
      runner: TestStubCommandRunner()
    )

    let output = MemoryCLIOutput()
    let runner = CLIRunner(
      coordinator: coordinator,
      supervisor: supervisor,
      configStore: cfg,
      receiptStore: receipts,
      output: output
    )
    let registry = MCPToolRegistry(coordinator: coordinator)
    return (dir, runner, output, registry)
  }

  @Test("CLI version, config redaction, ready, and deploy exit codes")
  func cliCommandsAndExitCodes() async throws {
    let (dir, runner, output, _) = try makeHarness(configured: true, lockState: .unlocked)
    defer { try? FileManager.default.removeItem(at: dir) }

    let verCode = await runner.run(arguments: ["version", "--compact"])
    #expect(verCode == 0)
    #expect(output.stdoutString.contains("\"version\":\"\(DebagrVersion.current)\""))

    output.clear()
    let cfgCode = await runner.run(arguments: ["config", "show"])
    #expect(cfgCode == 0)
    #expect(!output.stdoutString.contains("12:34:56:78:9a:bc@deadbeef00112233"))
    #expect(!output.stdoutString.contains("100.64.22.33"))
    #expect(output.stdoutString.contains("\"wirelessIdentityCaptured\" : true"))

    output.clear()
    let readyCode = await runner.run(arguments: ["ready"])
    #expect(readyCode == 0)
    #expect(output.stdoutString.contains("\"ready\" : true"))

    output.clear()
    let deployCode = await runner.run(arguments: ["deploy", "--app", "/tmp/Demo.app"])
    #expect(deployCode == 0)
    #expect(output.stdoutString.contains("\"launched\" : true"))
  }

  @Test(
    "CLI returns exit code 3 when locked, 4 on partial install-only success, 5 on uncertain timeout"
  )
  func cliRecoverableExitCodes() async throws {
    let hLocked = try makeHarness(configured: true, lockState: .locked)
    defer { try? FileManager.default.removeItem(at: hLocked.dir) }
    let lockedCode = await hLocked.runner.run(arguments: ["deploy", "--app", "/tmp/Demo.app"])
    #expect(lockedCode == CLIExitCode.deviceNotReady.rawValue)
    #expect(hLocked.output.stdoutString.contains("DEVICE_LOCKED"))

    let hPartial = try makeHarness(
      configured: true,
      lockState: .unlocked,
      launchError: DebagrError(code: .launchFailed, category: "launch", message: "Trust needed")
    )
    defer { try? FileManager.default.removeItem(at: hPartial.dir) }
    let partialCode = await hPartial.runner.run(arguments: ["deploy", "--app", "/tmp/Demo.app"])
    #expect(partialCode == CLIExitCode.partialSuccessLaunchFailed.rawValue)
    #expect(hPartial.output.stdoutString.contains("INSTALL_SUCCEEDED_LAUNCH_FAILED"))

    let hTimeout = try makeHarness(
      configured: true,
      lockState: .unlocked,
      installError: DebagrError(
        code: .operationTimeoutUncertain,
        category: "timeout",
        message: "Timed out"
      )
    )
    defer { try? FileManager.default.removeItem(at: hTimeout.dir) }
    let timeoutCode = await hTimeout.runner.run(arguments: ["deploy", "--app", "/tmp/Demo.app"])
    #expect(timeoutCode == CLIExitCode.uncertainTimeout.rawValue)
    #expect(hTimeout.output.stdoutString.contains("OPERATION_TIMEOUT_UNCERTAIN"))
  }

  @Test(
    "MCP stdio server handles initialize, tools/list, tools/call, notifications, and parse errors")
  func mcpProtocolLifecycle() async throws {
    let (dir, _, _, registry) = try makeHarness(
      configured: true,
      lockState: .unlocked,
      launchError: DebagrError(code: .launchFailed, category: "launch", message: "Untrusted app")
    )
    defer { try? FileManager.default.removeItem(at: dir) }

    let requests: [String] = [
      #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"1.0"}}}"#,
      #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
      #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#,
      #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#,
      #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"debagr_check_readiness","arguments":{}}}"#,
      #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"debagr_deploy_app","arguments":{"appPath":"/tmp/Demo.app"}}}"#,
      #"{"invalid json"#,
    ]

    let transport = InMemoryMCPTransport(
      messages: requests.map {
        MCPIncomingMessage(payload: Data($0.utf8), framing: .newlineDelimited)
      }
    )
    let server = MCPStdioServer(registry: registry, transport: transport, stderrLogger: { _ in })
    await server.run()

    let written = await transport.writtenMessages
    // 7 incoming messages, 1 notification produces no reply -> 6 responses
    #expect(written.count == 6)

    let initResp = try JSONDecoder().decode(JSONRPCResponse.self, from: written[0].payload)
    #expect(initResp.result?["protocolVersion"]?.stringValue == "2025-03-26")
    #expect(initResp.result?["serverInfo"]?["name"]?.stringValue == "debagr")

    let listResp = try JSONDecoder().decode(JSONRPCResponse.self, from: written[2].payload)
    let tools = listResp.result?["tools"]?.arrayValue ?? []
    let names = tools.compactMap { $0["name"]?.stringValue }
    #expect(names.count == 7)
    #expect(names.contains("debagr_deploy_app"))
    #expect(names.contains("debagr_launch_app"))

    let readyResp = try JSONDecoder().decode(JSONRPCResponse.self, from: written[3].payload)
    #expect(readyResp.result?["isError"]?.boolValue == false)

    let deployResp = try JSONDecoder().decode(JSONRPCResponse.self, from: written[4].payload)
    #expect(deployResp.result?["isError"]?.boolValue == true)
    #expect(
      deployResp.result?["structuredContent"]?["code"]?.stringValue
        == "INSTALL_SUCCEEDED_LAUNCH_FAILED"
    )

    let parseErr = try JSONDecoder().decode(JSONRPCResponse.self, from: written[5].payload)
    #expect(parseErr.error?.code == -32700)
  }
}

extension JSONValue {
  fileprivate subscript(key: String) -> JSONValue? {
    objectValue?[key]
  }
}

final class MemoryCLIOutput: CLIOutputWriting, @unchecked Sendable {
  private let lock = NSLock()
  private var stdoutBuf = ""
  private var stderrBuf = ""

  var stdoutString: String { lock.withLock { stdoutBuf } }

  func clear() {
    lock.withLock {
      stdoutBuf = ""
      stderrBuf = ""
    }
  }

  func writeStdout(_ text: String) {
    lock.withLock { stdoutBuf += text }
  }

  func writeStderr(_ text: String) {
    lock.withLock { stderrBuf += text }
  }
}

actor InMemoryMCPTransport: MCPTransport {
  private var queue: [MCPIncomingMessage]
  private(set) var writtenMessages: [(payload: Data, framing: MCPFramingStyle)] = []

  init(messages: [MCPIncomingMessage]) {
    self.queue = messages
  }

  func readMessage() async throws -> MCPIncomingMessage? {
    guard !queue.isEmpty else { return nil }
    return queue.removeFirst()
  }

  func writeMessage(_ payload: Data, framing: MCPFramingStyle) async throws {
    writtenMessages.append((payload, framing))
  }
}

actor TestCLIStubDeviceCtl: DeviceControlling {
  let devices: [PhysicalDevice]
  let lockStateValue: LockState
  let apps: [InstalledApp]
  let installOutcome: DeviceCtlInstallOutcome
  let installError: DebagrError?
  let launchError: DebagrError?

  init(
    devices: [PhysicalDevice],
    lockStateValue: LockState,
    apps: [InstalledApp],
    installOutcome: DeviceCtlInstallOutcome,
    installError: DebagrError?,
    launchError: DebagrError?
  ) {
    self.devices = devices
    self.lockStateValue = lockStateValue
    self.apps = apps
    self.installOutcome = installOutcome
    self.installError = installError
    self.launchError = launchError
  }

  func version() async throws -> String? { "651.31" }
  func listDevices(timeout: TimeInterval) async throws -> [PhysicalDevice] { devices }
  func deviceDetails(identifier: String, timeout: TimeInterval) async throws -> PhysicalDevice {
    devices[0]
  }
  func lockState(identifier: String, timeout: TimeInterval) async throws -> LockState {
    lockStateValue
  }
  func listApps(identifier: String, bundleID: String?, timeout: TimeInterval) async throws
    -> [InstalledApp]
  { apps }
  func installApp(identifier: String, appPath: String, timeout: TimeInterval) async throws
    -> DeviceCtlInstallOutcome
  {
    if let installError { throw installError }
    return installOutcome
  }
  func launchApp(
    identifier: String,
    bundleID: String,
    arguments: [String],
    environment: [String: String],
    terminateExisting: Bool,
    launchServicesIdentifier: String?,
    timeout: TimeInterval
  ) async throws -> DeviceCtlLaunchOutcome {
    if let launchError { throw launchError }
    return DeviceCtlLaunchOutcome(pid: 4242)
  }
  func pairDevice(identifier: String, timeout: TimeInterval) async throws {}
}

struct TestStubBundleValidator: AppBundleValidating {
  let bundle: ValidatedAppBundle
  func validate(appPath: String) async throws -> ValidatedAppBundle { bundle }
}

struct TestStubVPNDiscovery: VPNPeerDiscovering {
  func discoverPeers(provider: VPNProvider) async -> VPNEnvironmentStatus {
    VPNEnvironmentStatus(provider: provider, available: true, detail: "OK", peers: [])
  }
}

struct TestStubCommandRunner: CommandRunning {
  func run(
    executable: String,
    arguments: [String],
    environment: [String: String]?,
    timeoutSeconds: TimeInterval
  ) async throws -> CommandResult {
    CommandResult(
      exitCode: 0, stdout: Data("Xcode 27.2\n".utf8), stderr: Data(), timedOut: false, durationMs: 1
    )
  }
}

actor TestStubDNSSD: DNSSDControlling {
  func browseMobdevServices(timeoutSeconds: TimeInterval) async throws -> [BonjourServiceRecord] {
    []
  }
  func startProxy(_ spec: ProxyRegistrationSpec) async throws -> ProxyHandle {
    ProxyHandle(spec: spec)
  }
  func stopProxy(_ handle: ProxyHandle) async {}
  func stopAllProxies() async {}
}

struct TestStubTCPProbe: TCPProbing {
  func probe(host: String, port: UInt16, timeoutSeconds: TimeInterval) async -> Bool { true }
}
