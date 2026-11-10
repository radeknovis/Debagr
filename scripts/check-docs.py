#!/usr/bin/env python3
"""Check shipped local links and keep the public setup label aligned with the app."""
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
for source in [ROOT / "docs/PLUGINS.md", ROOT / "Marketing/site/setup.html"]:
    assert "Save &amp; Connect" not in source.read_text() and "Save & Connect" not in source.read_text(), source
assert "Build and validate packages" not in (ROOT / "docs/PLUGINS.md").read_text()
if errors:
    raise SystemExit("\n".join(errors))
print("Documentation links, website assets and public setup labels passed.")
