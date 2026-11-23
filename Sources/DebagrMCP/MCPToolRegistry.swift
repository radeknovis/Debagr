import DebagrCore
import Foundation

public struct MCPToolDescriptor: Codable, Sendable, Equatable {
  public let name: String
  public let description: String
  public let inputSchema: JSONValue

  public init(name: String, description: String, inputSchema: JSONValue) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
  }
}

public struct MCPToolCallOutput: Codable, Sendable, Equatable {
  public let content: [MCPTextContent]
  public let structuredContent: JSONValue?
  public let isError: Bool

  public init(text: String, structuredContent: JSONValue?, isError: Bool) {
    self.content = [MCPTextContent(type: "text", text: text)]
    self.structuredContent = structuredContent
    self.isError = isError
  }
}

public struct MCPTextContent: Codable, Sendable, Equatable {
  public let type: String
  public let text: String

  public init(type: String = "text", text: String) {
    self.type = type
    self.text = text
  }
}

public final class MCPToolRegistry: Sendable {
  private let coordinator: DeploymentCoordinator

  public init(coordinator: DeploymentCoordinator = DeploymentCoordinator()) {
    self.coordinator = coordinator
  }

  public var tools: [MCPToolDescriptor] {
    [
      MCPToolDescriptor(
        name: "debagr_list_devices",
        description:
          "List physical iPhones and iPads visible on this Builder Mac (paired eligible devices by default).",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "includeIneligible": .object([
              "type": .string("boolean"),
              "description": .string(
                "Include simulators, Macs, watches, or unpaired devices with explanations."
              ),
            ])
          ]),
        ])
      ),
      MCPToolDescriptor(
        name: "debagr_check_readiness",
        description:
          "Check whether the configured iPhone/iPad is reachable over native USB/Wi-Fi or the VPN bridge, paired, developer-mode enabled, and unlocked.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "device": .object([
              "type": .string("string"),
              "description": .string("Optional device UDID/name override."),
            ]),
            "timeoutSeconds": .object([
              "type": .string("number"),
              "description": .string("Optional check timeout in seconds (default 20)."),
            ]),
          ]),
        ])
      ),
      MCPToolDescriptor(
        name: "debagr_diagnose",
        description:
          "Collect redacted diagnostics for Debagr, devicectl, VPN reachability, bridge state, storage permissions, and recent receipts.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "redact": .object([
              "type": .string("boolean"),
              "description": .string("Keep strict redaction enabled (default true)."),
            ])
          ]),
        ])
      ),
      MCPToolDescriptor(
        name: "debagr_list_apps",
        description: "List removable apps installed on the target iPhone/iPad.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "device": .object([
              "type": .string("string"),
              "description": .string("Optional device UDID/name override."),
            ]),
            "bundleId": .object([
              "type": .string("string"),
              "description": .string("Filter for a specific bundle identifier."),
            ]),
          ]),
        ])
      ),
      MCPToolDescriptor(
        name: "debagr_install_app",
        description:
          "Validate a signed iphoneos .app bundle on the Builder Mac and install it onto the target device without launching.",
        inputSchema: .object([
          "type": .string("object"),
          "required": .array([.string("appPath")]),
          "properties": .object([
            "appPath": .object([
              "type": .string("string"),
              "description": .string("Path to the signed iphoneos .app bundle on the Builder Mac."),
            ]),
            "device": .object([
              "type": .string("string"),
              "description": .string("Optional device UDID/name override."),
            ]),
            "verify": .object([
              "type": .string("boolean"),
              "description": .string(
                "Verify bundle appears in device apps after install (default true)."),
            ]),
            "timeoutSeconds": .object([
              "type": .string("number"),
              "description": .string("Optional timeout in seconds."),
            ]),
          ]),
        ])
      ),
      MCPToolDescriptor(
        name: "debagr_launch_app",
        description:
          "Launch an already-installed app on the unlocked target device (ideal for recovery after INSTALL_SUCCEEDED_LAUNCH_FAILED).",
        inputSchema: .object([
          "type": .string("object"),
          "required": .array([.string("bundleId")]),
          "properties": .object([
            "bundleId": .object([
              "type": .string("string"),
              "description": .string("Bundle identifier of the installed app."),
            ]),
            "device": .object([
              "type": .string("string"),
              "description": .string("Optional device UDID/name override."),
            ]),
            "terminateExisting": .object([
              "type": .string("boolean"),
              "description": .string("Terminate running instance before launching."),
            ]),
            "arguments": .object([
              "type": .string("array"),
              "items": .object(["type": .string("string")]),
              "description": .string("Optional command-line arguments passed to the app."),
            ]),
            "timeoutSeconds": .object([
              "type": .string("number"),
              "description": .string("Optional launch timeout in seconds (default 45)."),
            ]),
          ]),
        ])
      ),
      MCPToolDescriptor(
        name: "debagr_deploy_app",
        description:
          "Validate a signed iphoneos .app bundle, install it onto the target physical device, verify installation, and launch it with structured recovery errors.",
        inputSchema: .object([
          "type": .string("object"),
          "required": .array([.string("appPath")]),
          "properties": .object([
            "appPath": .object([
              "type": .string("string"),
              "description": .string("Path to the signed iphoneos .app bundle on the Builder Mac."),
            ]),
            "device": .object([
              "type": .string("string"),
              "description": .string("Optional device UDID/name override."),
            ]),
            "launch": .object([
              "type": .string("boolean"),
              "description": .string("Launch after verified installation (default true)."),
            ]),
            "terminateExisting": .object([
              "type": .string("boolean"),
              "description": .string("Terminate running instance before launching."),
            ]),
            "timeoutSeconds": .object([
              "type": .string("number"),
              "description": .string("Optional install timeout in seconds."),
            ]),
          ]),
        ])
      ),
    ]
  }

  public func call(name: String, arguments: [String: JSONValue]) async -> MCPToolCallOutput {
    do {
      switch name {
      case "debagr_list_devices":
        let includeAll = arguments["includeIneligible"]?.boolValue ?? false
        let devices = try await coordinator.listDevices(includeIneligible: includeAll)
        return try successOutput(devices)

      case "debagr_check_readiness":
        let device = arguments["device"]?.stringValue
        let timeout = arguments["timeoutSeconds"]?.doubleValue ?? 20
        let report = try await coordinator.checkReadiness(
          deviceOverride: device,
          timeoutSeconds: timeout
        )
        return try successOutput(report, forceError: !report.ready)

      case "debagr_diagnose":
        let redact = arguments["redact"]?.boolValue ?? true
        let report = try await coordinator.doctor(strictRedaction: redact)
        return try successOutput(report)

      case "debagr_list_apps":
        let device = arguments["device"]?.stringValue
        let bundleID = arguments["bundleId"]?.stringValue
        let apps = try await coordinator.listApps(deviceOverride: device, bundleID: bundleID)
        return try successOutput(apps)

      case "debagr_install_app":
        guard let appPath = arguments["appPath"]?.stringValue, !appPath.isEmpty else {
          return errorOutput(
            DebagrErrorPayload(
              code: .invalidArguments,
              category: "mcp",
              message: "Missing required parameter 'appPath'."
            )
          )
        }
        let device = arguments["device"]?.stringValue
        let verify = arguments["verify"]?.boolValue ?? true
        let timeout = arguments["timeoutSeconds"]?.doubleValue
        let res = try await coordinator.install(
          appPath: appPath,
          deviceOverride: device,
          verify: verify,
          timeoutSeconds: timeout
        )
        return try successOutput(res)

      case "debagr_launch_app":
        guard let bundleID = arguments["bundleId"]?.stringValue, !bundleID.isEmpty else {
          return errorOutput(
            DebagrErrorPayload(
              code: .invalidArguments,
              category: "mcp",
              message: "Missing required parameter 'bundleId'."
            )
          )
        }
        let device = arguments["device"]?.stringValue
        let terminate = arguments["terminateExisting"]?.boolValue ?? false
        let launchArgs = arguments["arguments"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let timeout = arguments["timeoutSeconds"]?.doubleValue ?? 45
        let res = try await coordinator.launch(
          bundleID: bundleID,
          deviceOverride: device,
          arguments: launchArgs,
          terminateExisting: terminate,
          timeoutSeconds: timeout
        )
        return try successOutput(res)

      case "debagr_deploy_app":
        guard let appPath = arguments["appPath"]?.stringValue, !appPath.isEmpty else {
          return errorOutput(
            DebagrErrorPayload(
              code: .invalidArguments,
              category: "mcp",
              message: "Missing required parameter 'appPath'."
            )
          )
        }
        let device = arguments["device"]?.stringValue
        let launchAfter = arguments["launch"]?.boolValue ?? true
        let terminate = arguments["terminateExisting"]?.boolValue ?? false
        let timeout = arguments["timeoutSeconds"]?.doubleValue
        let res = try await coordinator.deploy(
          appPath: appPath,
          deviceOverride: device,
          launchAfterInstall: launchAfter,
          terminateExisting: terminate,
          timeoutSeconds: timeout
        )
        return try successOutput(res)

      default:
        return errorOutput(
          DebagrErrorPayload(
            code: .invalidArguments,
            category: "mcp",
            message: "Unknown MCP tool '\(name)'."
          )
        )
      }
    } catch let err as DebagrError {
      return errorOutput(err.payload)
    } catch {
      return errorOutput(
        DebagrErrorPayload(
          code: .internalError,
          category: "internal",
          message: error.localizedDescription,
          recoverable: false
        )
      )
    }
  }

  private func successOutput<T: Encodable>(_ value: T, forceError: Bool = false) throws
    -> MCPToolCallOutput
  {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    let text = String(decoding: data, as: UTF8.self)
    let structured = try? JSONValue.fromEncodable(value)
    return MCPToolCallOutput(text: text, structuredContent: structured, isError: forceError)
  }

  private func errorOutput(_ payload: DebagrErrorPayload) -> MCPToolCallOutput {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = (try? encoder.encode(payload)) ?? Data("{\"error\":\"encoding failure\"}".utf8)
    let text = String(decoding: data, as: UTF8.self)
    let structured = try? JSONValue.fromEncodable(payload)
    return MCPToolCallOutput(text: text, structuredContent: structured, isError: true)
  }
}
