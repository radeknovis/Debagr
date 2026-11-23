#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
import json, pathlib, re, sys

root = pathlib.Path(".")
version = (root / "VERSION").read_text().strip()
assert re.fullmatch(r"\d+\.\d+\.\d+", version), f"Invalid VERSION: {version}"

# 1. Version consistency
swift_ver = (root / "Sources/DebagrCore/Version.swift").read_text()
assert f'current = "{version}"' in swift_ver, "Version mismatch in Sources/DebagrCore/Version.swift"

claude_manifest = json.loads((root / "plugins/claude-code/.claude-plugin/plugin.json").read_text())
assert claude_manifest["version"] == version, f"Claude plugin version mismatch: {claude_manifest['version']}"

codex_manifest = json.loads((root / "plugins/codex/plugin.json").read_text())
assert codex_manifest["version"] == version, f"Codex plugin version mismatch: {codex_manifest['version']}"

site_cfg = (root / "site/config.js").read_text()
assert f'version: "{version}"' in site_cfg, "site/config.js version mismatch"
assert f"Debagr-{version}-arm64.dmg" in site_cfg, "site/config.js downloadUrl version mismatch"

# 2. Shared SKILL.md byte identity
canonical_skill = (root / "skills/debagr-deploy/SKILL.md").read_bytes()
claude_skill = (root / "plugins/claude-code/skills/debagr-deploy/SKILL.md").read_bytes()
codex_skill = (root / "plugins/codex/skills/debagr-deploy/SKILL.md").read_bytes()
assert canonical_skill == claude_skill, "Claude plugin SKILL.md diverges from canonical skill"
assert canonical_skill == codex_skill, "Codex plugin SKILL.md diverges from canonical skill"

# 3. Static site zero-dependency & link checks
site_dir = root / "site"
for html_file in sorted(site_dir.glob("*.html")):
    html = html_file.read_text()
    assert not re.search(r'<script[^>]+src=["\']https?://', html, re.I), f"External script in {html_file}"
    assert not re.search(r'<link[^>]+href=["\']https?://', html, re.I), f"External stylesheet in {html_file}"
    for ref in re.findall(r'(?<![A-Za-z0-9_-])(?:href|src)=["\']([^"\']+)["\']', html):
        if ref.startswith(("http://", "https://", "mailto:", "#")):
            continue
        target = (html_file.parent / ref).resolve()
        assert target.exists(), f"Broken local reference '{ref}' in {html_file}"

# 4. Honest experimental labeling across UI, CLI, docs, and site
assert "Experimental" in (root / "Sources/DebagrApp/Views/ExperimentalView.swift").read_text()
assert "EXPERIMENTAL" in (root / "Sources/DebagrCLI/CLIRunner.swift").read_text()
assert "Experimental" in (root / "site/index.html").read_text()
assert "Experimental" in (root / "site/guide.html").read_text()
assert "Experimental" in (root / "docs/cable-bridge.md").read_text()
assert "Experimental" in (root / "docs/usbip-pairing.md").read_text()

print(f"Consistency check passed for Debagr {version}.")
PY
