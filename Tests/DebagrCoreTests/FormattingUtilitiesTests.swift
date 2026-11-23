import DebagrCore
import Testing

@Suite("Port, Shell & Terminal Highlighter Utilities")
struct FormattingUtilitiesTests {
  @Test("PortValidation accepts strictly 1...65535 and rejects 0 or non-ASCII digits")
  func tcpPortValidation() {
    #expect(PortValidation.parseTCPPort("1") == 1)
    #expect(PortValidation.parseTCPPort("62078") == 62078)
    #expect(PortValidation.parseTCPPort(" 22078 ") == 22078)
    #expect(PortValidation.parseTCPPort("65535") == 65535)

    #expect(PortValidation.parseTCPPort("") == nil)
    #expect(PortValidation.parseTCPPort("   ") == nil)
    #expect(PortValidation.parseTCPPort("0") == nil)
    #expect(PortValidation.parseTCPPort("0000") == nil)
    #expect(PortValidation.parseTCPPort("65536") == nil)
    #expect(PortValidation.parseTCPPort("-1") == nil)
    #expect(PortValidation.parseTCPPort("62078a") == nil)
    #expect(PortValidation.parseTCPPort("٣") == nil)
    #expect(PortValidation.parseTCPPort("３") == nil)
  }

  @Test("ShellFormatting quotes SSH host only when needed")
  func sshCommandFormatting() {
    let simple = ShellFormatting.formatRemoteSSHCommand(
      host: "dev@builder-mac.local",
      remoteCommand: "/usr/local/bin/debagr ready"
    )
    #expect(simple == "ssh dev@builder-mac.local '/usr/local/bin/debagr ready'")

    let spacedHost = ShellFormatting.formatRemoteSSHCommand(
      host: "user name@host",
      remoteCommand: "/usr/local/bin/debagr deploy --app '/path/My App.app' --terminate-existing"
    )
    #expect(
      spacedHost
        == "ssh 'user name@host' '/usr/local/bin/debagr deploy --app '\\''/path/My App.app'\\'' --terminate-existing'"
    )
  }

  @Test("TerminalTokenizer highlights nested SSH remote command and preserves exact text")
  func nestedSSHCommandHighlighting() {
    let command = ShellFormatting.formatRemoteSSHCommand(
      host: "dev@builder.local",
      remoteCommand:
        "/usr/local/bin/debagr deploy --app \(ShellFormatting.singleQuote("/Users/me/My App.app")) --terminate-existing"
    )
    let tokens = TerminalTokenizer.tokenize(command, syntax: .shell)

    #expect(tokens.map(\.text).joined() == command)
    #expect(tokens.contains(TerminalToken(text: "ssh", kind: .command)))
    #expect(tokens.contains(TerminalToken(text: "/usr/local/bin/debagr", kind: .command)))
    #expect(tokens.contains(TerminalToken(text: "--app", kind: .flag)))
    #expect(tokens.contains(TerminalToken(text: "--terminate-existing", kind: .flag)))
    #expect(tokens.contains(TerminalToken(text: "/Users/me/My App.app", kind: .string)))
  }

  @Test("TerminalTokenizer detects and highlights Cable Bridge placeholders")
  func placeholderDetectionAndHighlighting() {
    let template = "ssh -N -L 22078:127.0.0.1:22078 <user>@<client-vpn-ip>"
    #expect(TerminalTokenizer.containsShellPlaceholders(template))

    let tokens = TerminalTokenizer.tokenize(template, syntax: .shell)
    #expect(tokens.map(\.text).joined() == template)
    #expect(tokens.contains(TerminalToken(text: "<user>", kind: .placeholder)))
    #expect(tokens.contains(TerminalToken(text: "<client-vpn-ip>", kind: .placeholder)))

    let concrete = "ssh dev@100.64.0.1 '/usr/local/bin/debagr ready'"
    #expect(!TerminalTokenizer.containsShellPlaceholders(concrete))
  }

  @Test("TerminalTokenizer highlights TOML arrays and JSON keys losslessly")
  func tomlAndJsonHighlighting() {
    let toml = """
      [mcp_servers.debagr]
      command = "/usr/local/bin/debagr"
      args = ["mcp"]
      enabled = true
      """
    let tomlTokens = TerminalTokenizer.tokenize(toml, syntax: .toml)
    #expect(tomlTokens.map(\.text).joined() == toml)
    #expect(tomlTokens.contains(TerminalToken(text: "[mcp_servers.debagr]", kind: .command)))
    #expect(tomlTokens.contains(TerminalToken(text: "args", kind: .key)))
    #expect(tomlTokens.contains(TerminalToken(text: "\"mcp\"", kind: .string)))
    #expect(tomlTokens.contains(TerminalToken(text: "[", kind: .punctuation)))
    #expect(tomlTokens.contains(TerminalToken(text: "]", kind: .punctuation)))
    #expect(tomlTokens.contains(TerminalToken(text: "true", kind: .flag)))

    let json = """
      {
        "ready": true,
        "port": 62078,
        "name": "iPhone"
      }
      """
    let jsonTokens = TerminalTokenizer.tokenize(json, syntax: .json)
    #expect(jsonTokens.map(\.text).joined() == json)
    #expect(jsonTokens.contains(TerminalToken(text: "\"port\"", kind: .key)))
    #expect(jsonTokens.contains(TerminalToken(text: "62078", kind: .numberOrEnv)))
    #expect(jsonTokens.contains(TerminalToken(text: "\"iPhone\"", kind: .string)))

    let huge = String(repeating: "a", count: TerminalTokenizer.maxHighlightedBytes + 128)
    let hugeTokens = TerminalTokenizer.tokenize(huge, syntax: .shell)
    #expect(hugeTokens == [TerminalToken(text: huge, kind: .plain)])
  }
}
