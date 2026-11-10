import Darwin
import Foundation

/// Local stdio only. Tool execution reuses the CLI contract without a shell.
final class LocalMCP {
  private var initialized = false
  private var ready = false
  private let execute: ([String]) throws -> Data

  init(execute: @escaping ([String]) throws -> Data = LocalMCP.runCLI) { self.execute = execute }

  static let tools: [(name: String, flag: String, fields: [String], mutates: Bool)] = [
    ("devices", "--devices", [], false),
    ("status", "--status", ["deviceIdentifier"], false),
    ("diagnose", "--diagnose", ["deviceIdentifier"], false),
    ("installed_apps", "--installed-apps", ["deviceIdentifier"], false),
    ("launch_app", "--launch-app", ["deviceIdentifier", "bundleIdentifier"], true),
    ("deploy_app", "--deploy-app", ["deviceIdentifier", "appPath"], true),
  ]

  static func run() {
    let session = LocalMCP()
    while let line = readLine() {
      do {
        guard line.utf8.count <= 1_048_576 else { throw CLIError.conflictingCommands }
        let request = try JSONSerialization.jsonObject(with: Data(line.utf8))
        if let reply = session.handle(request) { AgentCLI.writeJSONValue(reply) }
      } catch {
        AgentCLI.writeJSONValue([
          "jsonrpc": "2.0", "id": NSNull(),
          "error": ["code": -32700, "message": "Invalid JSON-RPC input"],
        ])
      }
    }
  }

  func handle(_ value: Any) -> Any? {
    if let batch = value as? [Any] {
      guard ready, !batch.isEmpty else {
        return error(id: NSNull(), code: -32600, message: "Invalid batch")
      }
      let replies = batch.compactMap { handle($0) }
      return replies.isEmpty ? nil : replies
    }
    guard let request = value as? [String: Any], request["jsonrpc"] as? String == "2.0",
      let method = request["method"] as? String
    else {
      return error(id: NSNull(), code: -32600, message: "Invalid request")
    }
    let id = request["id"] ?? NSNull()
    if request["id"] == nil {
      if method == "notifications/initialized", initialized { ready = true }
      return nil
    }
    if method == "ping" { return result(id: id, value: [:]) }
    if method == "initialize" {
      guard !initialized else { return error(id: id, code: -32600, message: "Already initialized") }
      initialized = true
      return result(
        id: id,
        value: [
          "protocolVersion": "2025-03-26", "capabilities": ["tools": [:]],
          "serverInfo": ["name": "debagr", "version": ProductSupport.version],
        ])
    }
    guard ready else { return error(id: id, code: -32002, message: "Initialize the session first") }
    if method == "tools/list" {
      return result(
        id: id,
        value: [
          "tools": Self.tools.map { tool -> [String: Any] in
            let properties = Dictionary(
              uniqueKeysWithValues: tool.fields.map { ($0, ["type": "string", "minLength": 1]) })
            return [
              "name": tool.name,
              "description": tool.mutates
                ? "Run an explicit app operation on the paired Mac. User authorization is required."
                : "Read device state on the paired Mac.",
              "inputSchema": [
                "type": "object", "properties": properties, "required": tool.fields,
                "additionalProperties": false,
              ],
              "annotations": [
                "readOnlyHint": !tool.mutates, "destructiveHint": tool.mutates,
                "openWorldHint": false,
              ],
            ]
          }
        ])
    }
    guard method == "tools/call" else {
      return error(id: id, code: -32601, message: "Unknown method")
    }
    guard let params = request["params"] as? [String: Any], let name = params["name"] as? String,
      let tool = Self.tools.first(where: { $0.name == name })
    else {
      return error(id: id, code: -32602, message: "Unknown tool")
    }
    let arguments = params["arguments"] as? [String: Any] ?? [:]
    guard Set(arguments.keys).isSubset(of: Set(tool.fields)),
      tool.fields.allSatisfy({
        guard let value = arguments[$0] as? String else { return false }
        return !value.isEmpty && !value.hasPrefix("-") && !value.contains("\0")
      })
    else { return error(id: id, code: -32602, message: "Invalid tool arguments") }
    var command = [tool.flag]
    if let bundle = arguments["bundleIdentifier"] as? String { command.append(bundle) }
    if let path = arguments["appPath"] as? String {
      guard path.hasPrefix("/") else {
        return error(id: id, code: -32602, message: "appPath must be absolute on the paired Mac")
      }
      command.append(path)
    }
    if let device = arguments["deviceIdentifier"] as? String { command += ["--device", device] }
    if name == "status" || name == "diagnose" { command += ["--timeout", "30"] }
    command.append("--json")
    do {
      let data = try execute(command)
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      return result(
        id: id,
        value: [
          "content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]],
          "isError": object?["ok"] as? Bool != true,
        ])
    } catch {
      return result(
        id: id,
        value: [
          "content": [["type": "text", "text": error.localizedDescription]], "isError": true,
        ])
    }
  }

  private func result(id: Any, value: [String: Any]) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "result": value]
  }
  private func error(id: Any, code: Int, message: String) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
  }

  static func runCLI(_ arguments: [String]) throws -> Data {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("debagr-mcp-\(UUID())")
    guard
      FileManager.default.createFile(
        atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    else { throw CocoaError(.fileWriteUnknown) }
    defer { try? FileManager.default.removeItem(at: url) }
    let output = try FileHandle(forWritingTo: url)
    defer { try? output.close() }
    let process = Process()
    process.executableURL = URL(
      fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    guard finished.wait(timeout: .now() + 180) == .success else {
      process.terminate()
      if finished.wait(timeout: .now() + 1) != .success { kill(process.processIdentifier, SIGKILL) }
      throw DeviceDeploymentError.timedOut
    }
    return try Data(contentsOf: url)
  }
}
