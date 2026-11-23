import DebagrBridge
import DebagrCLI
import DebagrCore
import Foundation

public final class LiveExperimentalCLIHandler: ExperimentalCLIHandling, Sendable {
  public init() {}

  public func runExperimentalCommand(subargs: [String], parsed: ParsedCLIArguments) async throws
    -> ExperimentalCLIOutput
  {
    guard let route = subargs.first else {
      throw DebagrError(
        code: .invalidArguments,
        category: "experimental",
        message:
          "Expected experimental subcommand: `cable-bridge` or `usbip`. Both routes are experimental."
      )
    }

    switch route {
    case "cable-bridge":
      let action = subargs.dropFirst().first ?? "guide"
      switch action {
      case "guide":
        let clientHost = parsed.value(for: "--client-host") ?? "<user>@<client-vpn-ip>"
        let udid = parsed.value(for: "--udid") ?? "<device-udid>"
        let instance = parsed.value(for: "--instance") ?? "<bonjour-instance>"
        let port = try ArgParser.parsePort(parsed.value(for: "--port"), defaultPort: 22078)
        return ExperimentalCLIOutput(
          command: "experimental.cable-bridge.guide",
          data: CableBridgeGuide(
            clientHost: clientHost,
            deviceUDID: udid,
            bonjourInstance: instance,
            port: port
          )
        )

      case "client":
        guard let udid = parsed.value(for: "--udid"), !udid.isEmpty else {
          throw DebagrError(
            code: .invalidArguments,
            category: "experimental_cable_bridge",
            message: "`experimental cable-bridge client` requires `--udid <device-udid>`."
          )
        }
        let port = try ArgParser.parsePort(parsed.value(for: "--port"), defaultPort: 22078)
        let relay = CableBridgeClientRelay(targetUDID: udid, localPort: port)
        let status = try await relay.start()
        // Keep relaying until SIGINT/SIGTERM in terminal invocation
        try await withTaskCancellationHandler {
          while !Task.isCancelled {
            try await Task.sleep(for: .seconds(60))
          }
        } onCancel: {
          Task { await relay.stop() }
        }
        return ExperimentalCLIOutput(command: "experimental.cable-bridge.client", data: status)

      case "builder":
        guard let instance = parsed.value(for: "--instance"), !instance.isEmpty else {
          throw DebagrError(
            code: .invalidArguments,
            category: "experimental_cable_bridge",
            message: "`experimental cable-bridge builder` requires `--instance <bonjour-instance>`."
          )
        }
        let port = try ArgParser.parsePort(parsed.value(for: "--port"), defaultPort: 22078)
        let session = CableBridgeBuilderSession()
        let status = try await session.start(instanceName: instance, forwardedPort: port)
        try await withTaskCancellationHandler {
          while !Task.isCancelled {
            try await Task.sleep(for: .seconds(60))
          }
        } onCancel: {
          Task { await session.stop() }
        }
        return ExperimentalCLIOutput(command: "experimental.cable-bridge.builder", data: status)

      default:
        throw DebagrError(
          code: .invalidArguments,
          category: "experimental_cable_bridge",
          message: "Unknown cable-bridge action '\(action)'. Expected: guide | client | builder."
        )
      }

    case "usbip":
      let action = subargs.dropFirst().first ?? "guide"
      switch action {
      case "check":
        let supervisor = SystemUSBIPToolSupervisor()
        let report = supervisor.checkPrerequisites(
          customBinaryPath: parsed.value(for: "--usbip-path"))
        return ExperimentalCLIOutput(command: "experimental.usbip.check", data: report)

      case "guide":
        return ExperimentalCLIOutput(command: "experimental.usbip.guide", data: USBIPGuidePayload())

      default:
        throw DebagrError(
          code: .invalidArguments,
          category: "experimental_usbip",
          message: "Unknown usbip action '\(action)'. Expected: check | guide."
        )
      }

    default:
      throw DebagrError(
        code: .invalidArguments,
        category: "experimental",
        message: "Unknown experimental route '\(route)'. Expected: cable-bridge | usbip."
      )
    }
  }
}
