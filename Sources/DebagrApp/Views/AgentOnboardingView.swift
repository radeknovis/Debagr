import DebagrCore
import SwiftUI

public struct AgentOnboardingView: View {
  @ObservedObject var model: AppModel

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Agent & SSH Onboarding")
            .font(.title2.weight(.semibold))
          Text(
            "Debagr opens no deployment network listener. Developers, CI jobs, and AI coding agents invoke Debagr locally via stdio MCP or over your existing SSH boundary."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }

        commandConfiguratorCard
        step1LinkBinary
        step2ClientCommands
        step3LiveTestCard
        step4RecoveryTable
      }
      .frame(maxWidth: DesignTokens.maxContentWidth, alignment: .leading)
      .frame(maxWidth: .infinity)
      .padding(DesignTokens.pagePadding)
    }
  }

  private var commandConfiguratorCard: some View {
    let trimmedHost = model.agentDraft.builderSSHHost.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let hostValidation: DebagrFieldValidation =
      trimmedHost.isEmpty ? .warning("Empty host falls back to user@builder-mac") : .none
    let trimmedAppPath = model.agentDraft.builderAppPath.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let appPathValidation: DebagrFieldValidation =
      trimmedAppPath.isEmpty ? .warning("Empty path falls back to /path/to/MyApp.app") : .none

    return SurfaceCard {
      VStack(alignment: .leading, spacing: 14) {
        Text("Command & Path Builder")
          .font(.headline)

        HStack(alignment: .top, spacing: 12) {
          DebagrTextField(
            label: "Builder SSH Target (user@hostname)",
            text: $model.agentDraft.builderSSHHost,
            prompt: "user@builder-mac.local",
            leadingIcon: "network",
            validation: hostValidation,
            trailingActionIcon: "arrow.counterclockwise",
            trailingActionHelp: "Reset to this Mac's default SSH target"
          ) {
            model.resetAgentSSHHostToDefault()
          }

          DebagrTextField(
            label: "Signed .app Path on Builder Mac's Filesystem",
            text: $model.agentDraft.builderAppPath,
            prompt: "/path/to/My App.app",
            leadingIcon: "shippingbox",
            validation: appPathValidation,
            acceptsFileDrop: true,
            trailingActionIcon: "folder",
            trailingActionHelp: "Choose signed .app bundle on this Mac…"
          ) {
            Task {
              if let path = await DebagrFilePicker.pickApplicationBundle(
                initialPath: model.agentDraft.builderAppPath
              ) {
                model.agentDraft.builderAppPath = path
              }
            }
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Target Caller")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
          DebagrSegmentedControl(
            "Target Caller",
            selection: $model.agentDraft.selectedClient,
            options: AgentClientKind.allCases,
            title: \.rawValue,
            systemImage: { client in
              switch client {
              case .sshCLI: "terminal"
              case .claudeCode: "sparkles"
              case .codex: "chevron.left.forwardslash.chevron.right"
              }
            }
          )
        }
      }
    }
  }

  private var step1LinkBinary: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 10) {
        Text("Step 1 · Link debagr onto PATH")
          .font(.headline)
        Text(
          "Exposes the embedded CLI and MCP binary at /usr/local/bin/debagr for non-login SSH shells and local MCP clients."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        let quotedBinary = DebagrFormatters.shellSingleQuote(model.binaryPathForAgents)
        TerminalCommandField(
          code: "sudo ln -sf \(quotedBinary) /usr/local/bin/debagr",
          contextTag: "Run on This Builder Mac",
          syntax: .shell
        )
      }
    }
  }

  private var step2ClientCommands: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 10) {
        let hostTrimmed = model.agentDraft.builderSSHHost.trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        let effectiveHost = hostTrimmed.isEmpty ? "user@builder-mac" : hostTrimmed
        let rawAppPath = model.agentDraft.builderAppPath.trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        let effectiveAppPath = rawAppPath.isEmpty ? "/path/to/MyApp.app" : rawAppPath
        let quotedAppInsideRemote = DebagrFormatters.shellSingleQuote(effectiveAppPath)

        switch model.agentDraft.selectedClient {
        case .sshCLI:
          Text("Step 2 · SSH Deployment Commands")
            .font(.headline)
          Text(
            "Run from your laptop, remote workstation, or CI runner. Invokes /usr/local/bin/debagr explicitly and preserves spaces inside Builder filesystem paths."
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          DebagrSegmentedControl(
            "SSH Deploy Behavior",
            selection: $model.agentDraft.sshDeployMode,
            options: SSHDeployMode.allCases,
            title: \.rawValue,
            systemImage: { mode in
              switch mode {
              case .deployAndLaunch: "play.circle"
              case .installOnly: "square.and.arrow.down"
              }
            }
          )

          TerminalCommandField(
            code: DebagrFormatters.formatRemoteSSHCommand(
              host: effectiveHost,
              remoteCommand: "/usr/local/bin/debagr ready"
            ),
            contextTag: "Run on Remote Machine (Check Readiness)",
            syntax: .shell
          )
          TerminalCommandField(
            code: DebagrFormatters.formatRemoteSSHCommand(
              host: effectiveHost,
              remoteCommand:
                "/usr/local/bin/debagr deploy --app \(quotedAppInsideRemote) \(model.agentDraft.sshDeployMode.flagSuffix)"
            ),
            contextTag: model.agentDraft.sshDeployMode.commandContextTag,
            syntax: .shell
          )

        case .claudeCode:
          Text("Step 2 · Claude Code MCP & Plugin")
            .font(.headline)
          Text(
            "Debagr runs over local stdio (zero open ports) and includes a packaged Claude Code plugin at plugins/claude-code."
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          TerminalCommandField(
            code: """
              {
                "mcpServers": {
                  "debagr": {
                    "command": "/usr/local/bin/debagr",
                    "args": ["mcp"]
                  }
                }
              }
              """,
            contextTag: "Add to .mcp.json on Builder Mac",
            syntax: .json
          )

        case .codex:
          Text("Step 2 · Codex MCP & Plugin")
            .font(.headline)
          Text(
            "Add Debagr's stdio MCP server to Codex on the Builder Mac or load the packaged plugin at plugins/codex."
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          TerminalCommandField(
            code: """
              [mcp_servers.debagr]
              command = "/usr/local/bin/debagr"
              args = ["mcp"]
              """,
            contextTag: "Add to ~/.codex/config.toml on Builder Mac",
            syntax: .toml
          )
        }
      }
    }
  }

  private var step3LiveTestCard: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Step 3 · Verify Local Readiness Output")
              .font(.headline)
            Text("Runs an in-process readiness check matching what `debagr ready` reports.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            Task { await model.runOnboardingReadinessTest() }
          } label: {
            DebagrButtonLabel(
              title: model.isRunningOnboardingTest ? "Running…" : "Test Readiness Now",
              systemImage: "play.fill",
              isLoading: model.isRunningOnboardingTest
            )
          }
          .buttonStyle(DebagrPrimaryButtonStyle(isLoading: model.isRunningOnboardingTest))
        }

        if let err = model.onboardingTestError {
          InlineNotice(
            symbolName: "xmark.octagon.fill",
            color: .red,
            title: "Readiness Check Failed",
            message: err
          )
        } else if let json = model.onboardingTestJSON {
          HStack(spacing: 6) {
            Image(
              systemName: model.onboardingTestReady == true
                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(model.onboardingTestReady == true ? .green : .orange)
            Text(
              model.onboardingTestReady == true
                ? "Ready (exit code 0)" : "Not ready yet (see blockers below)"
            )
            .font(.caption.weight(.semibold))
          }
          TerminalCommandField(
            code: json,
            contextTag: "Live Readiness Output",
            syntax: .json,
            wrapLines: true,
            maxHeight: 280
          )
        }
      }
    }
  }

  private var step4RecoveryTable: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 10) {
        Text("Step 4 · Structured Recovery Exit Codes")
          .font(.headline)
        Text(
          "Agents inspect JSON `error.code` and `partialSuccess` instead of blindly retrying builds."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        VStack(spacing: 8) {
          exitRow(
            code: "Exit 3",
            name: "DEVICE_LOCKED / DEVICE_UNREACHABLE",
            recovery: "Ask user to unlock phone and re-run `debagr ready`, or pass `--no-launch`."
          )
          Divider()
          exitRow(
            code: "Exit 4",
            name: "INSTALL_SUCCEEDED_LAUNCH_FAILED",
            recovery:
              "App is already installed and verified. Unlock or trust profile, then run `debagr launch --bundle-id <id>`."
          )
          Divider()
          exitRow(
            code: "Exit 5",
            name: "OPERATION_TIMEOUT_UNCERTAIN",
            recovery: "Check `partialSuccess` and `debagr apps --bundle-id <id>` before retrying."
          )
        }
        .padding(.top, 2)
      }
    }
  }

  private func exitRow(code: String, name: String, recovery: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      HStack(spacing: 4) {
        Circle()
          .fill(Color.orange)
          .frame(width: 6, height: 6)
        Text(code)
          .font(.caption.monospaced().weight(.semibold))
          .foregroundStyle(.primary)
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
      .frame(width: 72, alignment: .center)

      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.caption.monospaced().weight(.semibold))
        Text(LocalizedStringKey(recovery))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}
