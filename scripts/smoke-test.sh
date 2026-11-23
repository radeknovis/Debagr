#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH="${1:-$ROOT_DIR/dist/Debagr.app/Contents/MacOS/Debagr}"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Binary not executable at $BIN_PATH" >&2
  exit 1
fi

TEMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TEMP_HOME"' EXIT
export DEBAGR_HOME="$TEMP_HOME"

EXPECTED_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"

echo "Running CLI smoke checks against $BIN_PATH..."

VER_JSON="$("$BIN_PATH" version --compact)"
python3 - <<PY "$VER_JSON" "$EXPECTED_VERSION"
import json, sys
doc = json.loads(sys.argv[1])
assert doc["ok"] is True
assert doc["data"]["version"] == sys.argv[2], doc
PY

CFG_JSON="$("$BIN_PATH" config show --compact)"
python3 - <<PY "$CFG_JSON"
import json, sys
doc = json.loads(sys.argv[1])
assert doc["ok"] is True
assert doc["data"]["configured"] is False
PY

DOC_JSON="$("$BIN_PATH" doctor --compact)"
python3 - <<PY "$DOC_JSON"
import json, sys
doc = json.loads(sys.argv[1])
assert doc["ok"] is True
assert doc["data"]["redacted"] is True
assert doc["data"]["storagePermissionsOK"] is True
PY

set +e
READY_JSON="$("$BIN_PATH" ready --compact)"
READY_EXIT=$?
set -e
if [[ "$READY_EXIT" -ne 3 ]]; then
  echo "Expected exit code 3 for unconfigured 'ready', got $READY_EXIT" >&2
  exit 1
fi
python3 - <<PY "$READY_JSON"
import json, sys
doc = json.loads(sys.argv[1])
assert doc["data"]["ready"] is False
assert doc["data"]["blockers"][0]["code"] == "DEVICE_NOT_CONFIGURED"
PY

EXP_GUIDE="$("$BIN_PATH" experimental cable-bridge guide --compact)"
python3 - <<PY "$EXP_GUIDE"
import json, sys
doc = json.loads(sys.argv[1])
assert doc["ok"] is True
assert "EXPERIMENTAL" in doc["data"]["experimentalNotice"]
PY

echo "Running MCP stdio smoke test..."
python3 - <<PY "$BIN_PATH"
import json, subprocess, sys

bin_path = sys.argv[1]
requests = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-03-26", "clientInfo": {"name": "smoke", "version": "1.0"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
    {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "debagr_diagnose", "arguments": {"redact": True}}},
]
stdin_payload = "\n".join(json.dumps(r) for r in requests) + "\n"
proc = subprocess.run(
    [bin_path, "mcp"],
    input=stdin_payload,
    text=True,
    capture_output=True,
    timeout=15,
)
assert proc.returncode == 0, f"MCP exited with {proc.returncode}: {proc.stderr}"
lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
assert len(lines) == 3, f"Expected 3 JSON-RPC responses, got {len(lines)}: {lines}"

init_resp = json.loads(lines[0])
assert init_resp["result"]["serverInfo"]["name"] == "debagr"

tools_resp = json.loads(lines[1])
names = {t["name"] for t in tools_resp["result"]["tools"]}
expected = {
    "debagr_list_devices",
    "debagr_check_readiness",
    "debagr_diagnose",
    "debagr_list_apps",
    "debagr_install_app",
    "debagr_launch_app",
    "debagr_deploy_app",
}
assert names == expected, f"Mismatch MCP tools: {names}"

diag_resp = json.loads(lines[2])
assert diag_resp["result"]["isError"] is False
assert diag_resp["result"]["structuredContent"]["redacted"] is True
PY

echo "CLI and MCP smoke tests passed."
