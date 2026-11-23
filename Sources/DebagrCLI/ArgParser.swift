import DebagrCore
import Foundation

public struct ParsedCLIArguments: Sendable, Equatable {
  public let positionals: [String]
  public let flags: Set<String>
  public let values: [String: [String]]

  public init(positionals: [String], flags: Set<String>, values: [String: [String]]) {
    self.positionals = positionals
    self.flags = flags
    self.values = values
  }

  public func hasFlag(_ name: String) -> Bool {
    flags.contains(name)
  }

  public func value(for name: String) -> String? {
    values[name]?.last
  }

  public func allValues(for name: String) -> [String] {
    values[name] ?? []
  }
}

public enum ArgParser: Sendable {
  private static let booleanFlags: Set<String> = [
    "--all",
    "--no-launch",
    "--no-verify",
    "--terminate-existing",
    "--redact",
    "--no-redact",
    "--pretty",
    "--compact",
    "--help",
    "-h",
    "--version",
    "-v",
    "--approve",
    "--json",
  ]

  public static func parse(_ args: [String]) throws -> ParsedCLIArguments {
    var positionals: [String] = []
    var flags: Set<String> = []
    var values: [String: [String]] = [:]

    var index = 0
    while index < args.count {
      let token = args[index]
      if token == "--" {
        if index + 1 < args.count {
          positionals.append(contentsOf: args[(index + 1)...])
        }
        break
      }

      if token.hasPrefix("--") || token == "-h" || token == "-v" {
        if let eqIdx = token.firstIndex(of: "="), token.hasPrefix("--") {
          let key = String(token[..<eqIdx])
          let val = String(token[token.index(after: eqIdx)...])
          values[key, default: []].append(val)
          index += 1
          continue
        }

        if booleanFlags.contains(token) {
          flags.insert(token)
          index += 1
          continue
        }

        guard index + 1 < args.count else {
          throw DebagrError(
            code: .invalidArguments,
            category: "cli",
            message: "Option '\(token)' requires a value.",
            recoverable: true
          )
        }
        let val = args[index + 1]
        values[token, default: []].append(val)
        index += 2
        continue
      }

      positionals.append(token)
      index += 1
    }

    return ParsedCLIArguments(positionals: positionals, flags: flags, values: values)
  }

  public static func parseEnvironmentVariables(_ pairs: [String]) throws -> [String: String] {
    var result: [String: String] = [:]
    for pair in pairs {
      guard let eqIdx = pair.firstIndex(of: "="), eqIdx != pair.startIndex else {
        throw DebagrError(
          code: .invalidArguments,
          category: "cli",
          message: "Invalid --env entry '\(pair)'; expected KEY=VALUE.",
          recoverable: true
        )
      }
      let key = String(pair[..<eqIdx])
      let value = String(pair[pair.index(after: eqIdx)...])
      result[key] = value
    }
    return result
  }

  public static func parseTimeout(_ raw: String?) throws -> TimeInterval? {
    guard let raw else { return nil }
    guard let seconds = TimeInterval(raw), seconds >= 1, seconds <= 3600 else {
      throw DebagrError(
        code: .invalidArguments,
        category: "cli",
        message: "Invalid --timeout '\(raw)'; expected seconds between 1 and 3600.",
        recoverable: true
      )
    }
    return seconds
  }

  public static func parsePort(_ raw: String?, defaultPort: UInt16) throws -> UInt16 {
    guard let raw else { return defaultPort }
    guard let port = UInt16(raw), port >= 1 else {
      throw DebagrError(
        code: .invalidArguments,
        category: "cli",
        message: "Invalid --port '\(raw)'; expected 1...65535.",
        recoverable: true
      )
    }
    return port
  }
}
