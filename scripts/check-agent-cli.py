"""Read-only packaged CLI smoke check. No device install, pairing, or config writes.

Run: python3 scripts/check-agent-cli.py [path/to/Debagr]
"""
import json
import subprocess
import sys


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
        assert result.returncode == expected, (arguments[0], result.returncode)
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
