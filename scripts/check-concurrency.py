#!/usr/bin/env python3
"""Reject new strict-concurrency diagnostics while Swift 5 migration is in progress."""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / ".ci/concurrency-baseline.json"

def normalize_warning(message):
    # Xcode versions move diagnostic IDs between namespaces without changing the warning.
    return re.sub(r"\[#(?:[A-Za-z0-9_]+::)+([A-Za-z0-9_]+)\]", r"[#\1]", message)


def warnings(text):
    # SwiftBuild can splice progress output into a compiler diagnostic path.
    text = re.sub(r"\[\d+\s*/\s*\d+\] [^\n]*\n", "", text)
    found = set()
    for file, message in re.findall(r"^(.+?\.swift):\d+:\d+: warning: (.+)$", text, re.MULTILINE):
        path = Path(file)
        try:
            path = path.relative_to(ROOT)
        except ValueError:
            pass
        found.add(normalize_warning(f"{path}: {message}"))
    return found

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("--update-baseline", action="store_true")
    args = parser.parse_args()
    current = warnings(args.log.read_text())
    if args.update_baseline:
        BASELINE.parent.mkdir(exist_ok=True)
        BASELINE.write_text(json.dumps(sorted(current), indent=2) + "\n")
    expected = {normalize_warning(warning) for warning in json.loads(BASELINE.read_text())}
    added = current - expected
    for warning in sorted(added):
        print(f"New concurrency warning: {warning}")
    print(f"Concurrency diagnostics: {len(current)} unique, {len(added)} new, {len(expected - current)} removed.")
    raise SystemExit(bool(added))
