import Foundation

public enum Redactor: Sendable {
  public static func redactUDID(_ udid: String?) -> String {
    guard let udid = udid?.trimmingCharacters(in: .whitespacesAndNewlines), !udid.isEmpty else {
      return "unknown"
    }
    if udid.count <= 8 {
      return String(repeating: "*", count: udid.count)
    }
    return "\(udid.prefix(4))...\(udid.suffix(4))"
  }

  public static func redactIP(_ address: String?, strict: Bool) -> String? {
    guard let address else { return nil }
    guard strict else { return address }
    if address.contains(":") {
      let parts = address.split(separator: ":", omittingEmptySubsequences: false)
      guard let first = parts.first, !first.isEmpty else { return "[redacted-ipv6]" }
      return "\(first):*:*:*:*"
    }
    let octets = address.split(separator: ".")
    if octets.count == 4 {
      return "\(octets[0]).\(octets[1]).*.*"
    }
    return "[redacted-ip]"
  }

  public static func redactFreeformText(
    _ text: String,
    knownSensitiveValues: [String] = []
  ) -> String {
    var result = text
    for sensitive in knownSensitiveValues where !sensitive.isEmpty {
      result = result.replacingOccurrences(of: sensitive, with: "[redacted]")
    }
    // Redact MAC@pairID Bonjour instance strings such as 12:34:56:78:9a:bc@deadbeefcafebabe
    let bonjourPattern = #"[0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5}@[0-9a-zA-Z_-]+"#
    result = replaceRegex(pattern: bonjourPattern, in: result, with: "[redacted-wireless-identity]")

    // Redact PEM blocks if any ever surfaced in tool output
    let pemPattern = #"-----BEGIN [A-Z0-9 ]+-----[\s\S]*?-----END [A-Z0-9 ]+-----"#
    result = replaceRegex(pattern: pemPattern, in: result, with: "[redacted-key-material]")
    return result
  }

  private static func replaceRegex(pattern: String, in input: String, with template: String)
    -> String
  {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return input
    }
    let range = NSRange(input.startIndex..., in: input)
    return regex.stringByReplacingMatches(
      in: input, options: [], range: range, withTemplate: template)
  }
}
