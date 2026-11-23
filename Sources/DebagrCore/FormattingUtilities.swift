import Foundation

public enum PortValidation: Sendable {
  /// Parses an ASCII TCP port strictly in `1...65535`. Rejects port `0`, non-ASCII digits,
  /// whitespace-embedded garbage, and out-of-range integers.
  public static func parseTCPPort(_ raw: String) -> UInt16? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
      let port = UInt16(trimmed),
      port > 0
    else {
      return nil
    }
    return port
  }
}

public enum ShellFormatting: Sendable {
  /// Wraps a string in POSIX single quotes, escaping embedded single quotes as `'\''`.
  public static func singleQuote(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
    return "'\(escaped)'"
  }

  /// Leaves simple ASCII shell targets unquoted (`user@host.local`) and single-quotes anything
  /// containing spaces, quotes, globs, or special characters.
  public static func quoteIfNeeded(_ value: String) -> String {
    guard !value.isEmpty else { return "''" }
    let isSimple = value.allSatisfy { ch in
      ch.isASCII
        && (ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "." || ch == "@"
          || ch == ":" || ch == "/" || ch == "+")
    }
    return isSimple ? value : singleQuote(value)
  }

  /// Formats `ssh <host> '<remoteCommand>'`, keeping simple SSH targets readable while
  /// safely preserving spaces and nested quotes in the remote command.
  public static func formatRemoteSSHCommand(host: String, remoteCommand: String) -> String {
    "ssh \(quoteIfNeeded(host)) \(singleQuote(remoteCommand))"
  }
}

public enum TerminalSyntax: String, Sendable, CaseIterable {
  case shell
  case json
  case toml
  case plain

  public var badgeLabel: String? {
    switch self {
    case .json: "JSON"
    case .toml: "TOML"
    case .shell, .plain: nil
    }
  }
}

public enum TerminalTokenKind: Equatable, Sendable {
  case plain
  case command
  case flag
  case string
  case numberOrEnv
  case punctuation
  case comment
  case placeholder
  case key
}

public struct TerminalToken: Equatable, Sendable {
  public let text: String
  public let kind: TerminalTokenKind

  public init(text: String, kind: TerminalTokenKind) {
    self.text = text
    self.kind = kind
  }
}

public enum TerminalTokenizer: Sendable {
  public static let maxHighlightedBytes = 16_384

  public static func containsShellPlaceholders(_ text: String) -> Bool {
    var index = text.startIndex
    while index < text.endIndex {
      if text[index] == "<", matchPlaceholder(in: text[...], from: index) != nil {
        return true
      }
      index = text.index(after: index)
    }
    return false
  }

  public static func tokenize(_ text: String, syntax: TerminalSyntax) -> [TerminalToken] {
    guard !text.isEmpty else { return [] }
    guard syntax != .plain, text.utf8.count <= maxHighlightedBytes else {
      return [TerminalToken(text: text, kind: .plain)]
    }

    switch syntax {
    case .plain:
      return [TerminalToken(text: text, kind: .plain)]
    case .shell:
      return tokenizeShell(text)
    case .json:
      return tokenizeJSON(text)
    case .toml:
      return tokenizeTOML(text)
    }
  }

  // MARK: - Shell

  private static func tokenizeShell(_ text: String) -> [TerminalToken] {
    var output: [TerminalToken] = []
    var index = text.startIndex

    while index < text.endIndex {
      var lineEnd = index
      while lineEnd < text.endIndex && text[lineEnd] != "\n" {
        lineEnd = text.index(after: lineEnd)
      }

      let line = text[index..<lineEnd]
      if !line.isEmpty {
        tokenizeShellLine(line, into: &output)
      }

      if lineEnd < text.endIndex && text[lineEnd] == "\n" {
        let afterNewline = text.index(after: lineEnd)
        appendToken(String(text[lineEnd..<afterNewline]), kind: .plain, to: &output)
        index = afterNewline
      } else {
        index = lineEnd
      }
    }

    return output
  }

  private static func tokenizeShellLine(_ line: Substring, into output: inout [TerminalToken]) {
    if let sshSplit = detectSSHTrailingRemoteArgument(in: line) {
      tokenizeShellSegment(line[line.startIndex..<sshSplit.remoteArgStart], into: &output)
      let openEnd = line.index(after: sshSplit.remoteArgStart)
      appendToken(String(line[sshSplit.remoteArgStart..<openEnd]), kind: .punctuation, to: &output)
      if openEnd < sshSplit.remoteArgCloseQuote {
        tokenizeEscapedSingleQuotedRemoteCommand(
          line[openEnd..<sshSplit.remoteArgCloseQuote],
          into: &output
        )
      }
      let afterClose = line.index(after: sshSplit.remoteArgCloseQuote)
      appendToken(
        String(line[sshSplit.remoteArgCloseQuote..<afterClose]),
        kind: .punctuation,
        to: &output
      )
      if afterClose < line.endIndex {
        appendToken(String(line[afterClose..<line.endIndex]), kind: .plain, to: &output)
      }
      return
    }

    tokenizeShellSegment(line, into: &output)
  }

  private struct SSHTrailingRemoteSplit {
    let remoteArgStart: String.Index
    let remoteArgCloseQuote: String.Index
  }

  private static func detectSSHTrailingRemoteArgument(in line: Substring) -> SSHTrailingRemoteSplit?
  {
    var index = line.startIndex
    var expectCommand = true
    var seenSSH = false
    var argCountAfterSSH = 0
    var lastTokenRange: Range<String.Index>?
    var lastTokenWasSingleQuoted = false

    while index < line.endIndex {
      if line[index].isWhitespace {
        while index < line.endIndex && line[index].isWhitespace {
          index = line.index(after: index)
        }
        continue
      }

      let isComment =
        line[index] == "#"
        && (index == line.startIndex || line[line.index(before: index)].isWhitespace)
      if isComment {
        return nil
      }

      let ch = line[index]
      if ch == "|" || ch == ";" || ch == "&" {
        return nil
      }

      if ch == "'" {
        let end = scanSingleQuoted(in: line, from: index)
        guard seenSSH else { return nil }
        argCountAfterSSH += 1
        lastTokenRange = index..<end
        lastTokenWasSingleQuoted = true
        expectCommand = false
        index = end
        continue
      }

      if ch == "\"" {
        let end = scanDoubleQuoted(in: line, from: index)
        if seenSSH {
          argCountAfterSSH += 1
        }
        lastTokenRange = index..<end
        lastTokenWasSingleQuoted = false
        expectCommand = false
        index = end
        continue
      }

      let start = index
      while index < line.endIndex {
        let cur = line[index]
        if cur.isWhitespace || cur == "'" || cur == "\"" || cur == "|" || cur == ";" || cur == "&" {
          break
        }
        index = line.index(after: index)
      }
      let word = line[start..<index]

      if expectCommand {
        if word == "sudo" {
          continue
        }
        if word == "ssh" || word.hasSuffix("/ssh") {
          seenSSH = true
          expectCommand = false
        } else {
          return nil
        }
      } else if seenSSH {
        argCountAfterSSH += 1
        lastTokenRange = start..<index
        lastTokenWasSingleQuoted = false
      }
    }

    guard seenSSH,
      argCountAfterSSH >= 2,
      lastTokenWasSingleQuoted,
      let range = lastTokenRange,
      range.lowerBound < line.index(before: range.upperBound)
    else {
      return nil
    }

    let closeQuoteIndex = line.index(before: range.upperBound)
    guard line[range.lowerBound] == "'", line[closeQuoteIndex] == "'" else {
      return nil
    }
    return SSHTrailingRemoteSplit(
      remoteArgStart: range.lowerBound,
      remoteArgCloseQuote: closeQuoteIndex
    )
  }

  private static func tokenizeEscapedSingleQuotedRemoteCommand(
    _ rawInterior: Substring,
    into output: inout [TerminalToken]
  ) {
    // Decode `'\''` sequences back into logical single quotes while preserving the exact
    // Range<String.Index> inside `rawInterior` for each logical character.
    var logical = ""
    var rawRanges: [Range<String.Index>] = []
    var cursor = rawInterior.startIndex

    while cursor < rawInterior.endIndex {
      if rawInterior[cursor...].hasPrefix("'\\''") {
        let end = rawInterior.index(cursor, offsetBy: 4)
        logical.append("'")
        rawRanges.append(cursor..<end)
        cursor = end
      } else {
        let next = rawInterior.index(after: cursor)
        logical.append(rawInterior[cursor])
        rawRanges.append(cursor..<next)
        cursor = next
      }
    }

    let rangeArrayOffset = logical.indices
    let logicalIndices = Array(rangeArrayOffset)
    var indexByLogicalPos: [String.Index: Int] = [:]
    indexByLogicalPos.reserveCapacity(logicalIndices.count)
    for (offset, strIdx) in logicalIndices.enumerated() {
      indexByLogicalPos[strIdx] = offset
    }

    func rawSubstring(for logicalRange: Range<String.Index>) -> Substring {
      let lowerOffset = indexByLogicalPos[logicalRange.lowerBound] ?? rawRanges.count
      let upperOffset =
        logicalRange.upperBound == logical.endIndex
        ? rawRanges.count
        : (indexByLogicalPos[logicalRange.upperBound] ?? rawRanges.count)
      guard lowerOffset < upperOffset else {
        return rawInterior[rawInterior.endIndex..<rawInterior.endIndex]
      }
      return rawInterior[rawRanges[lowerOffset].lowerBound..<rawRanges[upperOffset - 1].upperBound]
    }

    let logicalTokens = tokenizeShellSegmentToTokens(logical[...])
    var logicalCursor = logical.startIndex

    for token in logicalTokens {
      let endIdx = logical.index(logicalCursor, offsetBy: token.text.count)
      let tokenRange = logicalCursor..<endIdx
      let rawSlice = rawSubstring(for: tokenRange)

      if token.kind == .string,
        let firstChar = token.text.first,
        firstChar == "'" || firstChar == "\"",
        token.text.count >= 2,
        token.text.last == firstChar
      {
        let innerStart = logical.index(after: tokenRange.lowerBound)
        let innerEnd = logical.index(before: tokenRange.upperBound)
        let openRaw = rawSubstring(for: tokenRange.lowerBound..<innerStart)
        let innerRaw = rawSubstring(for: innerStart..<innerEnd)
        let closeRaw = rawSubstring(for: innerEnd..<tokenRange.upperBound)
        appendToken(String(openRaw), kind: .punctuation, to: &output)
        appendStringWithPlaceholders(innerRaw, to: &output)
        appendToken(String(closeRaw), kind: .punctuation, to: &output)
      } else {
        appendToken(String(rawSlice), kind: token.kind, to: &output)
      }

      logicalCursor = endIdx
    }
  }

  private static func tokenizeShellSegmentToTokens(_ segment: Substring) -> [TerminalToken] {
    var result: [TerminalToken] = []
    tokenizeShellSegment(segment, into: &result)
    return result
  }

  private static func tokenizeShellSegment(
    _ segment: Substring,
    into output: inout [TerminalToken]
  ) {
    var index = segment.startIndex
    var expectCommand = true

    while index < segment.endIndex {
      let ch = segment[index]

      if ch.isWhitespace {
        let start = index
        while index < segment.endIndex && segment[index].isWhitespace {
          index = segment.index(after: index)
        }
        appendToken(String(segment[start..<index]), kind: .plain, to: &output)
        continue
      }

      let isComment =
        ch == "#"
        && (index == segment.startIndex || segment[segment.index(before: index)].isWhitespace)
      if isComment {
        appendToken(String(segment[index..<segment.endIndex]), kind: .comment, to: &output)
        return
      }

      if ch == "'" {
        let end = scanSingleQuoted(in: segment, from: index)
        appendStringWithPlaceholders(segment[index..<end], to: &output)
        index = end
        expectCommand = false
        continue
      }

      if ch == "\"" {
        let end = scanDoubleQuoted(in: segment, from: index)
        appendStringWithPlaceholders(segment[index..<end], to: &output)
        index = end
        expectCommand = false
        continue
      }

      if ch == "|" || ch == ";" || ch == "&" {
        let start = index
        index = segment.index(after: index)
        if ch == "&" || ch == "|", index < segment.endIndex, segment[index] == ch {
          index = segment.index(after: index)
        }
        appendToken(String(segment[start..<index]), kind: .punctuation, to: &output)
        expectCommand = true
        continue
      }

      if ch == "<", let placeholderEnd = matchPlaceholder(in: segment, from: index) {
        appendToken(String(segment[index..<placeholderEnd]), kind: .placeholder, to: &output)
        index = placeholderEnd
        expectCommand = false
        continue
      }

      let start = index
      while index < segment.endIndex {
        let cur = segment[index]
        if cur.isWhitespace || cur == "'" || cur == "\"" || cur == "|" || cur == ";" || cur == "&" {
          break
        }
        index = segment.index(after: index)
      }
      let word = segment[start..<index]

      if word.hasPrefix("-") && word.count > 1 {
        appendUnquotedWithPlaceholders(word, baseKind: .flag, to: &output)
        expectCommand = false
      } else if let eqIndex = word.firstIndex(of: "="),
        eqIndex != word.startIndex,
        word.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" }).endIndex == eqIndex
      {
        let afterEq = word.index(after: eqIndex)
        appendToken(String(word[word.startIndex..<afterEq]), kind: .numberOrEnv, to: &output)
        appendStringWithPlaceholders(word[afterEq..<word.endIndex], to: &output)
      } else if expectCommand {
        let kind: TerminalTokenKind = word == "sudo" ? .numberOrEnv : .command
        appendUnquotedWithPlaceholders(word, baseKind: kind, to: &output)
        expectCommand = (word == "sudo")
      } else {
        appendUnquotedWithPlaceholders(word, baseKind: .plain, to: &output)
      }
    }
  }

  private static func appendStringWithPlaceholders(
    _ slice: Substring,
    to output: inout [TerminalToken]
  ) {
    appendUnquotedWithPlaceholders(slice, baseKind: .string, to: &output)
  }

  private static func appendUnquotedWithPlaceholders(
    _ slice: Substring,
    baseKind: TerminalTokenKind,
    to output: inout [TerminalToken]
  ) {
    var cursor = slice.startIndex
    var segmentStart = cursor

    while cursor < slice.endIndex {
      if slice[cursor] == "<", let endPlaceholder = matchPlaceholder(in: slice, from: cursor) {
        if segmentStart < cursor {
          appendToken(String(slice[segmentStart..<cursor]), kind: baseKind, to: &output)
        }
        appendToken(String(slice[cursor..<endPlaceholder]), kind: .placeholder, to: &output)
        cursor = endPlaceholder
        segmentStart = cursor
      } else {
        cursor = slice.index(after: cursor)
      }
    }

    if segmentStart < slice.endIndex {
      appendToken(String(slice[segmentStart..<slice.endIndex]), kind: baseKind, to: &output)
    }
  }

  private static func matchPlaceholder(in text: Substring, from start: String.Index) -> String
    .Index?
  {
    guard start < text.endIndex, text[start] == "<" else { return nil }
    var cursor = text.index(after: start)
    var charCount = 0

    while cursor < text.endIndex {
      let ch = text[cursor]
      if ch == ">" {
        return charCount > 0 ? text.index(after: cursor) : nil
      }
      if ch.isWhitespace || ch == "<" || ch == "'" || ch == "\"" {
        return nil
      }
      charCount += 1
      cursor = text.index(after: cursor)
    }
    return nil
  }

  private static func scanSingleQuoted(in text: Substring, from start: String.Index) -> String.Index
  {
    var index = text.index(after: start)
    while index < text.endIndex {
      if text[index] == "'" {
        if text[index...].hasPrefix("'\\''") {
          index = text.index(index, offsetBy: 4)
          continue
        }
        return text.index(after: index)
      }
      index = text.index(after: index)
    }
    return text.endIndex
  }

  private static func scanDoubleQuoted(in text: Substring, from start: String.Index) -> String.Index
  {
    var index = text.index(after: start)
    var escaped = false
    while index < text.endIndex {
      let ch = text[index]
      if escaped {
        escaped = false
      } else if ch == "\\" {
        escaped = true
      } else if ch == "\"" {
        return text.index(after: index)
      }
      index = text.index(after: index)
    }
    return text.endIndex
  }

  // MARK: - JSON

  private static func tokenizeJSON(_ text: String) -> [TerminalToken] {
    var output: [TerminalToken] = []
    var index = text.startIndex

    while index < text.endIndex {
      let ch = text[index]

      if ch.isWhitespace {
        let start = index
        while index < text.endIndex && text[index].isWhitespace {
          index = text.index(after: index)
        }
        appendToken(String(text[start..<index]), kind: .plain, to: &output)
        continue
      }

      if ch == "\"" {
        let end = scanDoubleQuoted(in: text[...], from: index)
        var lookahead = end
        while lookahead < text.endIndex && text[lookahead].isWhitespace {
          lookahead = text.index(after: lookahead)
        }
        let isKey = lookahead < text.endIndex && text[lookahead] == ":"
        appendToken(String(text[index..<end]), kind: isKey ? .key : .string, to: &output)
        index = end
        continue
      }

      if ch == "{" || ch == "}" || ch == "[" || ch == "]" || ch == ":" || ch == "," {
        let next = text.index(after: index)
        appendToken(String(text[index..<next]), kind: .punctuation, to: &output)
        index = next
        continue
      }

      let start = index
      while index < text.endIndex {
        let current = text[index]
        if current.isWhitespace || current == "," || current == "}" || current == "]"
          || current == "\""
        {
          break
        }
        index = text.index(after: index)
      }
      let word = text[start..<index]
      if word == "true" || word == "false" || word == "null" {
        appendToken(String(word), kind: .flag, to: &output)
      } else if word.first?.isNumber == true || word.first == "-" {
        appendToken(String(word), kind: .numberOrEnv, to: &output)
      } else {
        appendToken(String(word), kind: .plain, to: &output)
      }
    }

    return output
  }

  // MARK: - TOML

  private static func tokenizeTOML(_ text: String) -> [TerminalToken] {
    var output: [TerminalToken] = []
    var index = text.startIndex

    while index < text.endIndex {
      var lineEnd = index
      while lineEnd < text.endIndex && text[lineEnd] != "\n" {
        lineEnd = text.index(after: lineEnd)
      }

      let line = text[index..<lineEnd]
      tokenizeTOMLLine(line, into: &output)

      if lineEnd < text.endIndex && text[lineEnd] == "\n" {
        let next = text.index(after: lineEnd)
        appendToken("\n", kind: .plain, to: &output)
        index = next
      } else {
        index = lineEnd
      }
    }

    return output
  }

  private static func tokenizeTOMLLine(_ line: Substring, into output: inout [TerminalToken]) {
    let trimmed = line.drop(while: \.isWhitespace)
    let leadingWhitespace = line[line.startIndex..<trimmed.startIndex]

    if trimmed.isEmpty {
      appendToken(String(line), kind: .plain, to: &output)
      return
    }
    if trimmed.hasPrefix("#") {
      appendToken(String(leadingWhitespace), kind: .plain, to: &output)
      appendToken(String(trimmed), kind: .comment, to: &output)
      return
    }
    if trimmed.hasPrefix("[") && trimmed.contains("]") {
      appendToken(String(leadingWhitespace), kind: .plain, to: &output)
      appendToken(String(trimmed), kind: .command, to: &output)
      return
    }

    guard let eqIndex = line.firstIndex(of: "=") else {
      appendToken(String(line), kind: .plain, to: &output)
      return
    }

    let keyPart = line[line.startIndex..<eqIndex]
    let trimmedKey = keyPart.drop(while: \.isWhitespace)
    let keyLeading = keyPart[keyPart.startIndex..<trimmedKey.startIndex]
    let keyTrailingStart =
      trimmedKey.reversed().prefix(while: \.isWhitespace).count
    let keyWordEnd = keyPart.index(eqIndex, offsetBy: -keyTrailingStart)
    appendToken(String(keyLeading), kind: .plain, to: &output)
    appendToken(String(keyPart[trimmedKey.startIndex..<keyWordEnd]), kind: .key, to: &output)
    appendToken(String(keyPart[keyWordEnd..<eqIndex]), kind: .plain, to: &output)

    let afterEq = line.index(after: eqIndex)
    appendToken("=", kind: .punctuation, to: &output)
    tokenizeTOMLValue(line[afterEq..<line.endIndex], into: &output)
  }

  private static func tokenizeTOMLValue(_ rhs: Substring, into output: inout [TerminalToken]) {
    var index = rhs.startIndex
    while index < rhs.endIndex {
      let ch = rhs[index]
      if ch.isWhitespace {
        let start = index
        while index < rhs.endIndex && rhs[index].isWhitespace {
          index = rhs.index(after: index)
        }
        appendToken(String(rhs[start..<index]), kind: .plain, to: &output)
        continue
      }

      if ch == "#" {
        appendToken(String(rhs[index..<rhs.endIndex]), kind: .comment, to: &output)
        return
      }

      if ch == "[" || ch == "]" || ch == "," || ch == "{" || ch == "}" || ch == "=" {
        let next = rhs.index(after: index)
        appendToken(String(rhs[index..<next]), kind: .punctuation, to: &output)
        index = next
        continue
      }

      if ch == "\"" {
        let end = scanDoubleQuoted(in: rhs, from: index)
        appendToken(String(rhs[index..<end]), kind: .string, to: &output)
        index = end
        continue
      }

      if ch == "'" {
        var end = rhs.index(after: index)
        while end < rhs.endIndex && rhs[end] != "'" {
          end = rhs.index(after: end)
        }
        if end < rhs.endIndex {
          end = rhs.index(after: end)
        }
        appendToken(String(rhs[index..<end]), kind: .string, to: &output)
        index = end
        continue
      }

      let start = index
      while index < rhs.endIndex {
        let cur = rhs[index]
        if cur.isWhitespace || cur == "," || cur == "]" || cur == "}" || cur == "#" {
          break
        }
        index = rhs.index(after: index)
      }
      let atom = rhs[start..<index]
      if atom == "true" || atom == "false" {
        appendToken(String(atom), kind: .flag, to: &output)
      } else if atom.first?.isNumber == true || atom.first == "-" || atom.first == "+" {
        appendToken(String(atom), kind: .numberOrEnv, to: &output)
      } else {
        appendToken(String(atom), kind: .plain, to: &output)
      }
    }
  }

  private static func appendToken(
    _ text: String,
    kind: TerminalTokenKind,
    to output: inout [TerminalToken]
  ) {
    guard !text.isEmpty else { return }
    if let last = output.last, last.kind == kind {
      output[output.count - 1] = TerminalToken(text: last.text + text, kind: kind)
    } else {
      output.append(TerminalToken(text: text, kind: kind))
    }
  }
}
