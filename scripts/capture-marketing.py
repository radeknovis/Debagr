#!/usr/bin/env python3
"""Render the actual native views with synthetic data, without touching user config or the shipped app."""
import hashlib
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    output = ROOT / "Marketing/screenshots"
    output.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".debagr-marketing-", dir=ROOT) as directory:
        fixture = Path(directory)
        shutil.copy2(ROOT / "Package.swift", fixture)
        shutil.copytree(ROOT / "Sources", fixture / "Sources")
        shutil.copytree(ROOT / "Tests", fixture / "Tests")
        main = fixture / "Sources/Debagr/main.swift"
        source = main.read_text()
        marker = "var runningApplication: (any ApplicationLifecycle)?"
        assert source.count(marker) == 1
        main.write_text(source.split(marker)[0] + (ROOT / "Marketing/Capture.swift").read_text())
        view = fixture / "Sources/Debagr/DeviceSetupWindow.swift"
        source = view.read_text()
        automatic_discovery = ".onAppear { model.loadPeers() }"
        assert source.count(automatic_discovery) == 1
        view.write_text(source.replace(automatic_discovery, ""))
        # A build-only fixture: no menu runtime, device probes, profiles, or network calls.
        build = subprocess.Popen(["swift", "build", "--package-path", str(fixture)],
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        formatter = subprocess.run(["xcsift", "-f", "toon", "-w", "-E"], stdin=build.stdout)
        build.stdout.close()
        assert build.wait() == 0 and formatter.returncode == 0, "Screenshot harness build failed"
        subprocess.run([str(fixture / ".build/debug/debagr"), str(output)], check=True, timeout=30)
    for name in ("device-setup-light", "agent-tools-light", "device-setup-dark", "agent-tools-dark"):
        assert (output / f"{name}.png").stat().st_size > 20_000
    (output / "provenance.json").write_text(json.dumps({
        "kind": "Native AppKit/SwiftUI view captures with synthetic device data",
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "view_sha256": hashlib.sha256((ROOT / "Sources/Debagr/DeviceSetupWindow.swift").read_bytes()).hexdigest(),
        "fixture": "Marketing/Capture.swift; automatic peer discovery disabled only in the temporary copy",
        "note": "Product UI illustrations, not hardware deployment evidence. No user profiles were read or changed."
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
