import DebagrCore
import SwiftUI

public struct AgentOnboardingView: View {
  @ObservedObject var model: AppModel

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Agent & SSH Onboarding")
            .font(.title2.bold())
          Text(
            "Debagr opens no deployment network listener. Developers and AI coding agents invoke the Debagr CLI locally or over your existing SSH session."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }

        commandCard(
          title: "1. Link `debagr` onto your PATH",
          subtitle:
            "Run once on this Builder Mac so SSH callers and MCP clients can invoke `debagr` directly.",
          command: "sudo ln -sf \"\(model.binaryPathForAgents)\" /usr/local/bin/debagr"
        )

        commandCard(
          title: "2. Remote SSH Deployment Commands",
          subtitle:
            "Use these from your laptop, CI job, or remote coding agent connected over SSH.",
          command: """
            ssh <user>@<builder-mac> debagr ready
            ssh <user>@<builder-mac> debagr deploy --app /path/to/Build/Products/Debug-iphoneos/MyApp.app --terminate-existing
            """
        )

        commandCard(
          title: "3. Local Stdio MCP Server Snippet (Claude Code & Codex)",
          subtitle: "Runs `debagr mcp` over stdin/stdout with zero network ports.",
          command: """
            {
              "mcpServers": {
                "debagr": {
                  "command": "debagr",
                  "args": ["mcp"]
                }
              }
            }
            """
        )

        GroupBox("4. Packaged Agent Plugins & Safe Workflow") {
          VStack(alignment: .leading, spacing: 6) {
            Text(
              "• Claude Code plugin: `plugins/claude-code` (includes `.mcp.json` + `debagr-deploy` skill)"
            )
            Text("• Codex plugin: `plugins/codex` (includes `plugin.json` + `debagr-deploy` skill)")
            Text(
              "• Safe agent loop: Check readiness -> Build signed iphoneos .app -> Deploy -> Recover cleanly from DEVICE_LOCKED (exit 3), INSTALL_SUCCEEDED_LAUNCH_FAILED (exit 4), or OPERATION_TIMEOUT_UNCERTAIN (exit 5)."
            )
          }
          .font(.callout)
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(24)
    }
  }

  private func commandCard(title: String, subtitle: String, command: String) -> some View {
    GroupBox(title) {
      VStack(alignment: .leading, spacing: 8) {
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
        HStack(alignment: .top) {
          Text(command)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

          Button("Copy") {
            model.copyToPasteboard(command)
            model.statusBanner = "Copied command snippet."
          }
        }
      }
      .padding(8)
    }
  }
}
