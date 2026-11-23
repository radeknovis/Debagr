import DebagrCore
import Foundation

public enum MCPFramingStyle: Sendable, Equatable {
  case newlineDelimited
  case contentLength
}

public struct MCPIncomingMessage: Sendable {
  public let payload: Data
  public let framing: MCPFramingStyle

  public init(payload: Data, framing: MCPFramingStyle) {
    self.payload = payload
    self.framing = framing
  }
}

public protocol MCPTransport: Sendable {
  func readMessage() async throws -> MCPIncomingMessage?
  func writeMessage(_ payload: Data, framing: MCPFramingStyle) async throws
}

public actor StdioMCPTransport: MCPTransport {
  private let input: FileHandle
  private let output: FileHandle
  private var buffer = Data()
  private var reachedEOF = false

  public init(
    input: FileHandle = .standardInput,
    output: FileHandle = .standardOutput
  ) {
    self.input = input
    self.output = output
  }

  public func readMessage() async throws -> MCPIncomingMessage? {
    while true {
      if let parsed = trySelfContainedFrame() {
        return parsed
      }
      if reachedEOF {
        return nil
      }
      let chunk = input.availableData
      if chunk.isEmpty {
        reachedEOF = true
        if !buffer.isEmpty {
          let trimmed = String(decoding: buffer, as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines
          )
          buffer.removeAll()
          if !trimmed.isEmpty {
            return MCPIncomingMessage(payload: Data(trimmed.utf8), framing: .newlineDelimited)
          }
        }
        return nil
      }
      buffer.append(chunk)
    }
  }

  public func writeMessage(_ payload: Data, framing: MCPFramingStyle) async throws {
    var outData = Data()
    switch framing {
    case .newlineDelimited:
      outData.append(payload)
      outData.append(0x0A)
    case .contentLength:
      let header = "Content-Length: \(payload.count)\r\n\r\n"
      outData.append(Data(header.utf8))
      outData.append(payload)
    }
    try output.write(contentsOf: outData)
  }

  private func trySelfContainedFrame() -> MCPIncomingMessage? {
    // Trim leading empty lines before checking framing
    while buffer.first == 0x0A || buffer.first == 0x0D {
      buffer.removeFirst()
    }
    guard !buffer.isEmpty else { return nil }

    let prefixStr = String(decoding: buffer.prefix(32), as: UTF8.self)
    if prefixStr.lowercased().hasPrefix("content-length:") {
      let separator = Data("\r\n\r\n".utf8)
      guard let headerEnd = buffer.range(of: separator) else { return nil }
      let headerStr = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
      var contentLength: Int?
      for line in headerStr.split(separator: "\r\n") {
        let lower = line.lowercased()
        if lower.hasPrefix("content-length:") {
          let raw = line.dropFirst("content-length:".count).trimmingCharacters(
            in: .whitespacesAndNewlines
          )
          contentLength = Int(raw)
        }
      }
      guard let len = contentLength else {
        buffer.removeSubrange(..<headerEnd.upperBound)
        return nil
      }
      let bodyStart = headerEnd.upperBound
      let bodyEnd = bodyStart + len
      guard buffer.count >= bodyEnd else { return nil }
      let body = Data(buffer[bodyStart..<bodyEnd])
      buffer.removeSubrange(..<bodyEnd)
      return MCPIncomingMessage(payload: body, framing: .contentLength)
    }

    if let newlineIdx = buffer.firstIndex(of: 0x0A) {
      let lineData = Data(buffer[..<newlineIdx])
      buffer.removeSubrange(...newlineIdx)
      let trimmed = String(decoding: lineData, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      if trimmed.isEmpty {
        return trySelfContainedFrame()
      }
      return MCPIncomingMessage(payload: Data(trimmed.utf8), framing: .newlineDelimited)
    }

    return nil
  }
}

public actor MCPStdioServer {
  private let registry: MCPToolRegistry
  private let transport: any MCPTransport
  private let stderrLogger: @Sendable (String) -> Void

  public init(
    registry: MCPToolRegistry = MCPToolRegistry(),
    transport: any MCPTransport = StdioMCPTransport(),
    stderrLogger: @escaping @Sendable (String) -> Void = { msg in
      FileHandle.standardError.write(Data((msg + "\n").utf8))
    }
  ) {
    self.registry = registry
    self.transport = transport
    self.stderrLogger = stderrLogger
  }

  public func run() async {
    while let message = try? await transport.readMessage() {
      if let response = await handleMessage(message.payload) {
        do {
          let encoder = JSONEncoder()
          encoder.outputFormatting = [.sortedKeys]
          let responseData = try encoder.encode(response)
          try await transport.writeMessage(responseData, framing: message.framing)
        } catch {
          stderrLogger("Failed writing MCP response: \(error.localizedDescription)")
        }
      }
    }
  }

  public func handleMessage(_ data: Data) async -> JSONRPCResponse? {
    let request: JSONRPCRequest
    do {
      request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
    } catch {
      return JSONRPCResponse(
        id: nil,
        error: JSONRPCErrorObject(
          code: -32700, message: "Parse error: \(error.localizedDescription)")
      )
    }

    // Notifications omit `id` and expect no response.
    if request.id == nil || request.method.hasPrefix("notifications/") {
      return nil
    }

    let id = request.id
    switch request.method {
    case "initialize":
      let clientVersion = request.params?["protocolVersion"]?.stringValue
      let negotiatedVersion =
        (clientVersion == "2024-11-05" || clientVersion == "2025-03-26")
        ? clientVersion! : "2025-03-26"
      let result: JSONValue = .object([
        "protocolVersion": .string(negotiatedVersion),
        "capabilities": .object([
          "tools": .object(["listChanged": .bool(false)])
        ]),
        "serverInfo": .object([
          "name": .string("debagr"),
          "version": .string(DebagrVersion.current),
        ]),
      ])
      return JSONRPCResponse(id: id, result: result)

    case "ping":
      return JSONRPCResponse(id: id, result: .object([:]))

    case "tools/list":
      let toolValues = (try? registry.tools.map { try JSONValue.fromEncodable($0) }) ?? []
      return JSONRPCResponse(id: id, result: .object(["tools": .array(toolValues)]))

    case "tools/call":
      guard let toolName = request.params?["name"]?.stringValue else {
        return JSONRPCResponse(
          id: id,
          error: JSONRPCErrorObject(code: -32602, message: "Missing tool 'name' in params.")
        )
      }
      let args = request.params?["arguments"]?.objectValue ?? [:]
      let output = await registry.call(name: toolName, arguments: args)
      guard let resultVal = try? JSONValue.fromEncodable(output) else {
        return JSONRPCResponse(
          id: id,
          error: JSONRPCErrorObject(code: -32603, message: "Failed encoding tool result.")
        )
      }
      return JSONRPCResponse(id: id, result: resultVal)

    default:
      return JSONRPCResponse(
        id: id,
        error: JSONRPCErrorObject(code: -32601, message: "Method not found: \(request.method)")
      )
    }
  }
}
