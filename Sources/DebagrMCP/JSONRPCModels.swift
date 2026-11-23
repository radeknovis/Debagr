import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let b = try? container.decode(Bool.self) {
      self = .bool(b)
    } else if let i = try? container.decode(Int.self) {
      self = .int(i)
    } else if let d = try? container.decode(Double.self) {
      self = .double(d)
    } else if let s = try? container.decode(String.self) {
      self = .string(s)
    } else if let arr = try? container.decode([JSONValue].self) {
      self = .array(arr)
    } else if let obj = try? container.decode([String: JSONValue].self) {
      self = .object(obj)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported JSON value"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let b): try container.encode(b)
    case .int(let i): try container.encode(i)
    case .double(let d): try container.encode(d)
    case .string(let s): try container.encode(s)
    case .array(let arr): try container.encode(arr)
    case .object(let obj): try container.encode(obj)
    }
  }

  public var stringValue: String? {
    if case .string(let s) = self { return s }
    return nil
  }

  public var boolValue: Bool? {
    if case .bool(let b) = self { return b }
    return nil
  }

  public var intValue: Int? {
    if case .int(let i) = self { return i }
    if case .double(let d) = self { return Int(d) }
    return nil
  }

  public var doubleValue: Double? {
    if case .double(let d) = self { return d }
    if case .int(let i) = self { return Double(i) }
    return nil
  }

  public var arrayValue: [JSONValue]? {
    if case .array(let arr) = self { return arr }
    return nil
  }

  public var objectValue: [String: JSONValue]? {
    if case .object(let obj) = self { return obj }
    return nil
  }

  public static func fromEncodable<T: Encodable>(_ value: T) throws -> JSONValue {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    return try JSONDecoder().decode(JSONValue.self, from: data)
  }
}

public struct JSONRPCRequest: Codable, Sendable, Equatable {
  public let jsonrpc: String
  public let id: JSONValue?
  public let method: String
  public let params: [String: JSONValue]?

  public init(
    jsonrpc: String = "2.0",
    id: JSONValue? = nil,
    method: String,
    params: [String: JSONValue]? = nil
  ) {
    self.jsonrpc = jsonrpc
    self.id = id
    self.method = method
    self.params = params
  }
}

public struct JSONRPCErrorObject: Codable, Sendable, Equatable {
  public let code: Int
  public let message: String
  public let data: JSONValue?

  public init(code: Int, message: String, data: JSONValue? = nil) {
    self.code = code
    self.message = message
    self.data = data
  }
}

public struct JSONRPCResponse: Codable, Sendable, Equatable {
  public let jsonrpc: String
  public let id: JSONValue?
  public let result: JSONValue?
  public let error: JSONRPCErrorObject?

  public init(
    id: JSONValue?,
    result: JSONValue? = nil,
    error: JSONRPCErrorObject? = nil
  ) {
    self.jsonrpc = "2.0"
    self.id = id
    self.result = result
    self.error = error
  }
}
