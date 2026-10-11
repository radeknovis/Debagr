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
        (["--status", "--device", "debagr-nonexistent-device", "--timeout", "1", "--json"], 2),
        (["--deploy-app", "/missing/No.app", "--device", "udid", "--json"], 65),
        (["--status", "--json"], 64),
    ]
    for arguments, expected in cases:
        result = subprocess.run([binary, *arguments], capture_output=True, text=True, timeout=20)
        output = json.loads(result.stdout)
        assert result.returncode == expected, (arguments[0], result.returncode)
        assert output["schemaVersion"] == 1
        assert output["ok"] == (expected == 0)
        assert "authTag" not in result.stdout
        assert "bonjourTXT" not in result.stdout
        print(arguments[0], "passed", "exit", result.returncode)


if __name__ == "__main__":
    main()
