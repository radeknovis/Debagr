#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
OUT_DIR="$ROOT_DIR/dist/plugins"
mkdir -p "$OUT_DIR"

# Sync canonical shared skill into both plugin packages
mkdir -p "$ROOT_DIR/plugins/claude-code/skills/debagr-deploy"
mkdir -p "$ROOT_DIR/plugins/codex/skills/debagr-deploy"
cp "$ROOT_DIR/skills/debagr-deploy/SKILL.md" "$ROOT_DIR/plugins/claude-code/skills/debagr-deploy/SKILL.md"
cp "$ROOT_DIR/skills/debagr-deploy/SKILL.md" "$ROOT_DIR/plugins/codex/skills/debagr-deploy/SKILL.md"

CLAUDE_ZIP="$OUT_DIR/debagr-claude-code-${VERSION}.zip"
CODEX_ZIP="$OUT_DIR/debagr-codex-${VERSION}.zip"
rm -f "$CLAUDE_ZIP" "$CODEX_ZIP"

(cd "$ROOT_DIR/plugins/claude-code" && zip -qr "$CLAUDE_ZIP" .)
(cd "$ROOT_DIR/plugins/codex" && zip -qr "$CODEX_ZIP" .)

echo "Packaged plugins:"
echo "  $CLAUDE_ZIP"
echo "  $CODEX_ZIP"
