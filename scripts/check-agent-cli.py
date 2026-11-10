"""Read-only packaged CLI smoke check. No device install, pairing, or config writes.

Run: python3 scripts/check-agent-cli.py [path/to/Debagr]
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    binary = sys.argv[1] if len(sys.argv) > 1 else "Debagr.app/Contents/MacOS/Debagr"
    cases = [
        (["--devices", "--json"], 0),
        (["--status", "--device", "debagr-nonexistent-device", "--timeout", "5", "--json"], 2),
        (["--deploy-app", "/missing/No.app", "--device", "udid", "--json"], 65),
        (["--status", "--json"], 64),
        (["--devices", "--timeout", "5", "--json"], 64),
        (["--launch-app", "com.example.not-installed", "--device", "debagr-nonexistent-device", "--json"], 2),
        (["--installed-apps", "--device", "debagr-nonexistent-device", "--json"], 2),
    ]
    messages = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
    ]
    mcp = subprocess.run([binary, "--mcp"], input="\n".join(map(json.dumps, messages)) + "\n", capture_output=True, text=True, timeout=20)
    replies = [json.loads(line) for line in mcp.stdout.splitlines()]
    assert mcp.returncode == 0 and len(replies) == 2
    assert len(replies[1]["result"]["tools"]) == 6
    print("MCP initialization and tools/list passed")
    for arguments, expected in cases:
        result = subprocess.run([binary, *arguments], capture_output=True, text=True, timeout=20)
        output = json.loads(result.stdout)
        if result.returncode != expected and arguments[0] == "--devices":
            # Preserve the real hosted-runner failure before changing inventory behavior.
            try:
                with tempfile.TemporaryDirectory() as directory:
                    path = Path(directory) / "inventory.json"
                    probe = subprocess.run(
                        ["/usr/bin/xcrun", "devicectl", "list", "devices", "--json-output", str(path)],
                        capture_output=True, text=True, timeout=20)
                    inventory = json.loads(path.read_text()) if path.exists() else {}
                    print("CoreDevice inventory diagnostic:", json.dumps({
                        "exitCode": probe.returncode, "stderr": probe.stderr,
                        "resultKeys": sorted(inventory.get("result", {})),
                        "error": inventory.get("error"),
                    }), flush=True)
            except (OSError, ValueError, subprocess.TimeoutExpired) as error:
                print("CoreDevice inventory diagnostic unavailable:", str(error), flush=True)
        assert result.returncode == expected, (arguments[0], result.returncode, output)
        assert output["schemaVersion"] == 1
        assert output["ok"] == (expected == 0)
        if arguments[0] == "--status" and "--device" in arguments:
            assert output["error"]["code"] == "apple_device_error", output
            assert output["error"]["underlyingCode"] == 1000, output
        assert "authTag" not in result.stdout
        assert "bonjourTXT" not in result.stdout
        print(arguments[0], "passed", "exit", result.returncode)


if __name__ == "__main__":
    main()
