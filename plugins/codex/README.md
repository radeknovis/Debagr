# Debagr Plugin for Codex

This plugin equips Codex with:
1. The `debagr-deploy` skill (`skills/debagr-deploy/SKILL.md`).
2. Local stdio MCP configuration (`debagr mcp`) exposing all 7 Debagr device inspection and deployment tools.

## MCP Config Snippet (`~/.codex/config.toml`)
```toml
[mcp_servers.debagr]
command = "debagr"
args = ["mcp"]
```

## Prerequisites
- `Debagr.app` installed and configured on your paired macOS Builder, with `/usr/local/bin/debagr` linked to `/Applications/Debagr.app/Contents/MacOS/Debagr`.
- For remote agents connecting over SSH, follow the SSH CLI workflow documented in `skills/debagr-deploy/SKILL.md`.
