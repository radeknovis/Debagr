#!/usr/bin/env python3
"""Check shipped local links and keep shipped docs free of removed labels and stale release wording."""
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent
errors = []

def check(source, target):
    parts = urlsplit(target)
    if parts.scheme or parts.netloc or not parts.path:
        return
    path = (source.parent / unquote(parts.path)).resolve()
    if not path.exists():
        errors.append(f"{source.relative_to(ROOT)}: missing {target}")

class Links(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.source = source
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ("href", "src", "poster") and value:
                check(self.source, value)

for source in [ROOT / "README.md", *sorted((ROOT / "docs").rglob("*.md"))]:
    for target in re.findall(r"\]\(([^)\s]+)\)", source.read_text()):
        check(source, target)
for source in sorted((ROOT / "Marketing/site").glob("*.html")):
    Links(source).feed(source.read_text())
# Everything build-macos-app.sh and package-plugins.py copy, plus the public site pages, the
# release notes and README.
shipped = [
    "README.md", "Marketing/site/setup.html", "Marketing/site/preview-licence.txt", "docs/CABLE_SHARING.md",
    "Marketing/site/index.html", "Marketing/site/legal.html", "Marketing/release-notes.md",
    "docs/PLUGINS.md", "docs/AI_DEPLOYMENT.md", "docs/MCP.md", "docs/NETWORK_PROVIDERS.md",
    ".claude-plugin/plugin.json", ".claude-plugin/marketplace.json",
    ".codex-plugin/plugin.json", ".agents/plugins/marketplace.json",
    *(path.relative_to(ROOT) for path in sorted((ROOT / "Skills/debagr-deploy").rglob("*")) if path.is_file()),
]
removed = [
    "Connect device", "Save & Connect", "Copy deployment prompt", "Disconnect Remote Device",
    "Show AI Deployment Skill", "Set Up Remote Device", "Connect Remote Device",
    "a deployment prompt", "unreleased source branch", "published 0.2.0",
]
for name in shipped:
    text = unescape((ROOT / name).read_text())
    for phrase in removed:
        # Labels match exactly; the lower-case release phrases match in any case.
        if phrase in text or phrase in text.lower():
            errors.append(f"{name}: contains removed text {phrase!r}")
assert "Build and validate packages" not in (ROOT / "docs/PLUGINS.md").read_text()
if errors:
    raise SystemExit("\n".join(errors))
print("Documentation links, website assets and shipped-doc labels passed.")
