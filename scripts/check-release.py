#!/usr/bin/env python3
"""Exercise release ordering and failure gates with mocked Apple tools; never signs or submits."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
MOCK = '''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps([name, *args]) + "\\n")
if name == "git":
    print(" M source.swift" if os.environ.get("DIRTY") else "", end="")
elif name == "xcsift":
    sys.stdin.read()
elif name == "xcrun" and args[:2] == ["notarytool", "submit"]:
    label = "app" if args[2].endswith(".zip") else "dmg"
    invalid = os.environ.get("REJECT") == label
    print(json.dumps({"id": "test-" + label, "status": "Invalid" if invalid else "Accepted"}))
    sys.exit(1 if invalid else 0)
elif name == "xcrun" and args[:2] == ["notarytool", "log"]:
    pathlib.Path(args[-1]).write_text("{}")
elif name == "xcrun" and args[:2] == ["stapler", "staple"] and args[-1].endswith(".app"):
    (pathlib.Path(args[-1]) / "stapled").touch()
elif name == "hdiutil":
    image = pathlib.Path(args[args.index("-srcfolder") + 1])
    assert (image / "Debagr.app/stapled").exists(), "App must be stapled before DMG creation"
    pathlib.Path(args[-1]).write_text("test disk image")
elif name == "spctl" and os.environ.get("FAIL_GATEKEEPER"):
    sys.exit(1)
'''


def run_case(**overrides):
    with tempfile.TemporaryDirectory(prefix="debagr-release-check-") as directory:
        fixture = Path(directory)
        (fixture / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/release-macos-app.sh", fixture / "scripts")
        for script in ("build-macos-app.sh", "verify-macos-app.sh"):
            target = fixture / "scripts" / script
            target.write_text("#!/bin/zsh\nset -eu\nmkdir -p Debagr.app\n")
            target.chmod(0o755)
        commands = fixture / "bin"
        commands.mkdir()
        for command in ("git", "swift", "xcsift", "xcrun", "ditto", "hdiutil", "codesign", "spctl"):
            target = commands / command
            target.write_text(MOCK)
            target.chmod(0o755)
        environment = {**os.environ, "ZDOTDIR": str(fixture), "PATH": f"{commands}:{os.environ['PATH']}",
                       "VERSION": "0.2.0", "BUILD_NUMBER": "2",
                       "CODESIGN_IDENTITY": "Developer ID Application: Test (TEST)",
                       "NOTARY_PROFILE": "fixture", "ALLOW_DIRTY_RELEASE": "0",
                       "CALL_LOG": str(fixture / "calls.jsonl"), **overrides}
        result = subprocess.run(["/bin/zsh", "scripts/release-macos-app.sh"], cwd=fixture,
                                env=environment, capture_output=True, text=True, timeout=30)
        should_pass = not overrides
        assert (result.returncode == 0) == should_pass, result.stderr
        output = fixture / "dist/Debagr-0.2.0.dmg"
        assert output.exists() == should_pass
        assert not list(fixture.glob(".debagr-release.*")), "Temporary files left behind"
        calls_path = fixture / "calls.jsonl"
        calls = [json.loads(line) for line in calls_path.read_text().splitlines()] if calls_path.exists() else []
        if overrides.get("REJECT"):
            label = overrides["REJECT"]
            assert (fixture / f"dist/Debagr-0.2.0-{label}-notary-log.json").exists()
        if should_pass:
            checksum = output.with_suffix(".dmg.sha256")
            assert checksum.read_text().endswith("  Debagr-0.2.0.dmg\n")
            assert subprocess.run(["shasum", "-a", "256", "-c", checksum.name],
                                  cwd=output.parent, capture_output=True).returncode == 0
            assert sum(call[:3] == ["xcrun", "notarytool", "submit"] for call in calls) == 2
            repeated = subprocess.run(["/bin/zsh", "scripts/release-macos-app.sh"], cwd=fixture,
                                      env=environment, capture_output=True, text=True)
            assert repeated.returncode != 0 and "overwrite" in repeated.stderr


def check_workflow_gates():
    lines = (ROOT / ".github/workflows/release.yml").read_text().splitlines()
    gates = "\n".join(line.strip() for line in lines if line.strip().startswith("[["))
    assert len(gates.splitlines()) == 3
    for version, build, ref, expected in [
        ("0.2.0", "2", "refs/tags/v0.2.0", 0),
        ("bad", "2", "refs/tags/v0.2.0", 1),
        ("0.2.0", "bad", "refs/tags/v0.2.0", 1),
        ("0.2.0", "2", "refs/heads/main", 1),
    ]:
        result = subprocess.run(["/bin/bash", "-e", "-c", gates], capture_output=True,
            env={**os.environ, "VERSION": version, "BUILD_NUMBER": build, "GITHUB_REF": ref})
        assert result.returncode == expected


if __name__ == "__main__":
    check_workflow_gates()
    for case in ({}, {"REJECT": "app"}, {"REJECT": "dmg"}, {"FAIL_GATEKEEPER": "1"},
                 {"DIRTY": "1"}, {"VERSION": "../../bad"}, {"BUILD_NUMBER": "invalid"},
                 {"CODESIGN_IDENTITY": "-"}):
        run_case(**case)
    print("Release safety: 8 scenarios passed (mocked Apple tools, no real notarization).")
