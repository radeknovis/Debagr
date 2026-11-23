# Debagr Plugin for Claude Code

This plugin equips Claude Code with:
1. The local `debagr` stdio MCP server (`debagr mcp`) configured in [`.mcp.json`](.mcp.json).
2. The `debagr-deploy` skill teaching Claude Code the safe `check -> build -> deploy -> recover` workflow for remote physical iPhones and iPads.

## Prerequisites
- Install `Debagr.app` on your paired **Builder Mac** and ensure `debagr` is on your `PATH` (for example `/usr/local/bin/debagr` symlinked to `/Applications/Debagr.app/Contents/MacOS/Debagr`).
- Complete Wireless Setup in Debagr once while your already-paired iPhone or iPad is nearby.

## Usage
- Locally on the Builder Mac: add or enable this plugin in Claude Code so the `debagr` MCP tools (`debagr_check_readiness`, `debagr_deploy_app`, `debagr_launch_app`, etc.) are available directly.
- Over SSH from another Mac/Linux workstation: run `ssh <builder> debagr ...` using the workflow in `skills/debagr-deploy/SKILL.md`.
