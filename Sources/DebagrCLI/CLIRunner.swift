import DebagrBridge
import DebagrCore
import Foundation

public protocol CLIOutputWriting: Sendable {
  func writeStdout(_ text: String)
  func writeStderr(_ text: String)
}

public struct StandardCLIOutput: CLIOutputWriting, Sendable {
  public init() {}

  public func writeStdout(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
  }

  public func writeStderr(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
  }
}

public protocol ExperimentalCLIHandling: Sendable {
  func runExperimentalCommand(subargs: [String], parsed: ParsedCLIArguments) async throws
    -> ExperimentalCLIOutput
}

public struct ExperimentalCLIOutput: Sendable {
  public let command: String
  public let data: any Encodable & Sendable

  public init(command: String, data: any Encodable & Sendable) {
    self.command = command
    self.data = data
  }
}

public struct UnavailableExperimentalHandler: ExperimentalCLIHandling {
  public init() {}

  public func runExperimentalCommand(subargs: [String], parsed: ParsedCLIArguments) async throws
    -> ExperimentalCLIOutput
  {
    throw DebagrError(
      code: .invalidArguments,
      category: "experimental",
      message: "Experimental routes are not linked in this CLI runner instance.",
      recoverable: true
    )
  }
}

public final class CLIRunner: Sendable {
  private let coordinator: DeploymentCoordinator
  private let supervisor: WirelessBridgeSupervisor
  private let configStore: any ConfigStoring
  private let receiptStore: any ReceiptStoring
  private let bridgeStateStore: any BridgeStateStoring
  private let experimentalHandler: any ExperimentalCLIHandling
  private let output: any CLIOutputWriting

  public init(
    coordinator: DeploymentCoordinator = DeploymentCoordinator(),
    supervisor: WirelessBridgeSupervisor = WirelessBridgeSupervisor(),
    configStore: any ConfigStoring = FileConfigStore(),
    receiptStore: any ReceiptStoring = FileReceiptStore(),
    bridgeStateStore: any BridgeStateStoring = FileBridgeStateStore(),
    experimentalHandler: any ExperimentalCLIHandling = UnavailableExperimentalHandler(),
    output: any CLIOutputWriting = StandardCLIOutput()
  ) {
    self.coordinator = coordinator
    self.supervisor = supervisor
    self.configStore = configStore
    self.receiptStore = receiptStore
    self.bridgeStateStore = bridgeStateStore
    self.experimentalHandler = experimentalHandler
    self.output = output
  }

  public func run(arguments: [String]) async -> Int32 {
    do {
      let parsed = try ArgParser.parse(arguments)
      let compact = parsed.hasFlag("--compact")

      if parsed.hasFlag("--help") || parsed.hasFlag("-h") {
        output.writeStdout(Self.helpText)
        return CLIExitCode.success.rawValue
      }

      if parsed.hasFlag("--version") || parsed.hasFlag("-v") {
        try emitSuccess(command: "version", data: VersionInfoPayload(), compact: compact)
        return CLIExitCode.success.rawValue
      }

      guard let cmd = parsed.positionals.first else {
        output.writeStdout(Self.helpText)
        return CLIExitCode.usageError.rawValue
      }

      switch cmd {
      case "help":
        output.writeStdout(Self.helpText)
        return CLIExitCode.success.rawValue

      case "version":
        try emitSuccess(command: "version", data: VersionInfoPayload(), compact: compact)
        return CLIExitCode.success.rawValue

      case "devices":
        let includeAll = parsed.hasFlag("--all")
        let devices = try await coordinator.listDevices(includeIneligible: includeAll)
        try emitSuccess(command: "devices", data: devices, compact: compact)
        return CLIExitCode.success.rawValue

      case "ready":
        let device = parsed.value(for: "--device")
        let timeout = try ArgParser.parseTimeout(parsed.value(for: "--timeout")) ?? 20
        let report = try await coordinator.checkReadiness(
          deviceOverride: device,
          timeoutSeconds: timeout
        )
        try emitSuccess(command: "ready", data: report, compact: compact)
        if report.ready {
          return CLIExitCode.success.rawValue
        }
        if let firstBlocker = report.blockers.first {
          return CLIExitCode.from(errorCode: firstBlocker.code).rawValue
        }
        return CLIExitCode.deviceNotReady.rawValue

      case "doctor":
        let strictRedaction = !parsed.hasFlag("--no-redact")
        let report = try await coordinator.doctor(strictRedaction: strictRedaction)
        try emitSuccess(command: "doctor", data: report, compact: compact)
        return CLIExitCode.success.rawValue

      case "apps":
        let device = parsed.value(for: "--device")
        let bundleID = parsed.value(for: "--bundle-id")
        let timeout = try ArgParser.parseTimeout(parsed.value(for: "--timeout")) ?? 25
        let apps = try await coordinator.listApps(
          deviceOverride: device,
          bundleID: bundleID,
          timeoutSeconds: timeout
        )
        try emitSuccess(command: "apps", data: apps, compact: compact)
        return CLIExitCode.success.rawValue

      case "install":
        guard let appPath = parsed.value(for: "--app") else {
          throw DebagrError(
            code: .invalidArguments,
            category: "cli",
            message: "`debagr install` requires `--app <path-to-.app>`."
          )
        }
        let device = parsed.value(for: "--device")
        let verify = !parsed.hasFlag("--no-verify")
        let timeout = try ArgParser.parseTimeout(parsed.value(for: "--timeout"))
        let result = try await coordinator.install(
          appPath: appPath,
          deviceOverride: device,
          verify: verify,
          timeoutSeconds: timeout
        )
        try emitSuccess(command: "install", data: result, compact: compact)
        return CLIExitCode.success.rawValue

      case "launch":
        guard let bundleID = parsed.value(for: "--bundle-id") else {
          throw DebagrError(
            code: .invalidArguments,
            category: "cli",
            message: "`debagr launch` requires `--bundle-id <bundle-identifier>`."
          )
        }
        let device = parsed.value(for: "--device")
        let terminateExisting = parsed.hasFlag("--terminate-existing")
        let launchArgs = parsed.allValues(for: "--arg")
        let envVars = try ArgParser.parseEnvironmentVariables(parsed.allValues(for: "--env"))
        let timeout = try ArgParser.parseTimeout(parsed.value(for: "--timeout")) ?? 45
        let result = try await coordinator.launch(
          bundleID: bundleID,
          deviceOverride: device,
          arguments: launchArgs,
          environment: envVars,
          terminateExisting: terminateExisting,
          timeoutSeconds: timeout
        )
        try emitSuccess(command: "launch", data: result, compact: compact)
        return CLIExitCode.success.rawValue

      case "deploy":
        guard let appPath = parsed.value(for: "--app") else {
          throw DebagrError(
            code: .invalidArguments,
            category: "cli",
            message: "`debagr deploy` requires `--app <path-to-.app>`."
          )
        }
        let device = parsed.value(for: "--device")
        let launchAfterInstall = !parsed.hasFlag("--no-launch")
        let terminateExisting = parsed.hasFlag("--terminate-existing")
        let timeout = try ArgParser.parseTimeout(parsed.value(for: "--timeout"))
        let result = try await coordinator.deploy(
          appPath: appPath,
          deviceOverride: device,
          launchAfterInstall: launchAfterInstall,
          terminateExisting: terminateExisting,
          timeoutSeconds: timeout
        )
        try emitSuccess(command: "deploy", data: result, compact: compact)
        return CLIExitCode.success.rawValue

      case "bridge":
        return try await handleBridgeCommand(
          subcommand: parsed.positionals.dropFirst().first,
          compact: compact
        )

      case "config":
        return try handleConfigCommand(
          subcommand: parsed.positionals.dropFirst().first,
          parsed: parsed,
          compact: compact
        )

      case "receipts":
        let receipts = try receiptStore.listRecent(limit: 20)
        try emitSuccess(command: "receipts", data: receipts, compact: compact)
        return CLIExitCode.success.rawValue

      case "experimental":
        let subargs = Array(parsed.positionals.dropFirst())
        let out = try await experimentalHandler.runExperimentalCommand(
          subargs: subargs,
          parsed: parsed
        )
        try emitAnySuccess(command: out.command, data: out.data, compact: compact)
        return CLIExitCode.success.rawValue

      default:
        throw DebagrError(
          code: .invalidArguments,
          category: "cli",
          message: "Unknown command '\(cmd)'. Run `debagr --help` for usage."
        )
      }
    } catch let err as DebagrError {
      let commandName = arguments.first(where: { !$0.hasPrefix("-") }) ?? "debagr"
      emitError(
        command: commandName, payload: err.payload, compact: arguments.contains("--compact"))
      return CLIExitCode.from(errorCode: err.payload.code).rawValue
    } catch {
      let commandName = arguments.first(where: { !$0.hasPrefix("-") }) ?? "debagr"
      let payload = DebagrErrorPayload(
        code: .internalError,
        category: "internal",
        message: error.localizedDescription,
        recoverable: false
      )
      emitError(command: commandName, payload: payload, compact: arguments.contains("--compact"))
      return CLIExitCode.generalError.rawValue
    }
  }

  private func handleBridgeCommand(subcommand: String?, compact: Bool) async throws -> Int32 {
    switch subcommand ?? "status" {
    case "status":
      let snap: BridgeStateSnapshot
      if let persisted = try? bridgeStateStore.load() {
        snap = persisted
      } else {
        snap = await supervisor.currentSnapshot()
      }
      try emitSuccess(command: "bridge.status", data: snap, compact: compact)
      return CLIExitCode.success.rawValue
    case "start", "ensure":
      _ = await supervisor.setPaused(false)
      let snap = await supervisor.reconcileOnce()
      try emitSuccess(command: "bridge.\(subcommand ?? "start")", data: snap, compact: compact)
      return CLIExitCode.success.rawValue
    case "stop":
      _ = await supervisor.setPaused(true)
      let snap = await supervisor.currentSnapshot()
      try emitSuccess(command: "bridge.stop", data: snap, compact: compact)
      return CLIExitCode.success.rawValue
    default:
      throw DebagrError(
        code: .invalidArguments,
        category: "cli",
        message:
          "Unknown bridge subcommand '\(subcommand ?? "")'. Expected: status | start | stop | ensure."
      )
    }
  }

  private func handleConfigCommand(
    subcommand: String?,
    parsed: ParsedCLIArguments,
    compact: Bool
  ) throws -> Int32 {
    switch subcommand ?? "show" {
    case "show":
      let config = try configStore.load()
      let summary = RedactedConfigSummary(from: config)
      try emitSuccess(command: "config.show", data: summary, compact: compact)
      return CLIExitCode.success.rawValue
    case "clear":
      _ = try configStore.update { cfg in
        cfg.managedDevice = nil
      }
      let summary = RedactedConfigSummary(from: try configStore.load())
      try emitSuccess(command: "config.clear", data: summary, compact: compact)
      return CLIExitCode.success.rawValue
    default:
      throw DebagrError(
        code: .invalidArguments,
        category: "cli",
        message: "Unknown config subcommand '\(subcommand ?? "")'. Expected: show | clear."
      )
    }
  }

  private func emitSuccess<T: Encodable & Sendable>(
    command: String,
    data: T,
    compact: Bool
  ) throws {
    let envelope = CLIEnvelope(command: command, ok: true, data: data, error: nil)
    let json = try encodeJSON(envelope, compact: compact)
    output.writeStdout(json + "\n")
  }

  private func emitAnySuccess(
    command: String,
    data: any Encodable & Sendable,
    compact: Bool
  ) throws {
    struct AnyEncodableBox: Encodable, @unchecked Sendable {
      let encodeImpl: (Encoder) throws -> Void
      init(_ value: any Encodable) {
        self.encodeImpl = value.encode
      }
      func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
      }
    }
    let envelope = CLIEnvelope(
      command: command,
      ok: true,
      data: AnyEncodableBox(data),
      error: nil
    )
    let json = try encodeJSON(envelope, compact: compact)
    output.writeStdout(json + "\n")
  }

  private func emitError(command: String, payload: DebagrErrorPayload, compact: Bool) {
    let envelope = CLIEnvelope<EmptyCLIResult>(
      command: command,
      ok: false,
      data: nil,
      error: payload
    )
    if let json = try? encodeJSON(envelope, compact: compact) {
      output.writeStdout(json + "\n")
    } else {
      output.writeStderr("{\"ok\":false,\"error\":{\"message\":\"Serialization failure\"}}\n")
    }
  }

  private func encodeJSON<T: Encodable>(_ value: T, compact: Bool) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = compact ? [.sortedKeys] : [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
  }

  public static let helpText = """
    Debagr \(DebagrVersion.current) — Remote iOS/iPadOS deployment bridge on your paired Builder Mac

    USAGE:
      debagr                          Launch menu-bar app & setup UI
      debagr mcp                      Start local stdio MCP server (JSON-RPC 2.0)
      debagr <command> [options]      Run machine-readable JSON CLI

    CORE COMMANDS:
      devices [--all]                 List paired physical iPhones/iPads (--all includes ineligible)
      ready [--device <id>]           Check device reachability, pairing, developer mode & lock state
      doctor [--no-redact]            Diagnostics report (redacts pairing secrets & IPs by default)
      apps [--device <id>] [--bundle-id <id>]
                                      List installed apps on target device
      install --app <path> [--device <id>] [--no-verify] [--timeout <sec>]
                                      Validate signed iphoneos .app and install
      launch --bundle-id <id> [--device <id>] [--terminate-existing] [--arg <v>] [--env K=V]
                                      Launch an installed app on unlocked target device
      deploy --app <path> [--device <id>] [--no-launch] [--terminate-existing] [--timeout <sec>]
                                      Validate, install, verify installation, and launch
      bridge status|start|stop|ensure Inspect or control the wireless VPN DNS-SD bridge
      config show|clear               Inspect (redacted) or clear managed device configuration
      receipts                        List recent local deployment receipts
      version                         Print structured version info

    EXPERIMENTAL COMMANDS (Clearly Experimental):
      experimental cable-bridge client --udid <udid> [--port 22078]
                                      Forward USB usbmuxd port 62078 onto 127.0.0.1 over SSH+VPN
      experimental cable-bridge builder --instance <bonjour-instance> --port 22078
                                      Register local DNS-SD proxy for forwarded cable bridge port
      experimental cable-bridge guide [--client-host <user@vpn-ip>]
                                      Print Terminal walkthrough for USB via Mac (Cable Service Bridge)
      experimental usbip check [--usbip-path <path>]
                                      Check separately installed third-party USB/IP tools
      experimental usbip guide        Print guided Pair via USB/IP instructions

    EXIT CODES:
      0  Success
      1  General / installation / verification failure
      2  Invalid CLI usage / arguments
      3  Device not configured, unreachable, unpaired, locked, or VPN down
      4  Partial success: app installed & verified, launch failed
      5  Operation timed out with uncertain outcome (post-timeout state checked)
    """
}
