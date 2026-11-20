#!/usr/bin/env python3
"""Verify the launch kit's local links, media formats, and inactive/HTTPS-only calls to action."""
from html.parser import HTMLParser
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent
MARKETING = ROOT / "Marketing"


class Assets(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.scripts = []
        self.inline_script = False

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        self.links.extend(attributes[key] for key in ("href", "src", "poster") if key in attributes)
        if tag == "img":
            assert "alt" in attributes, "Image needs alternative text"
        if tag == "script":
            self.inline_script = "src" not in attributes

    def handle_endtag(self, tag):
        if tag == "script":
            self.inline_script = False

    def handle_data(self, data):
        if self.inline_script:
            self.scripts.append(data)


def main():
    scripts = []
    for page in MARKETING.rglob("*.html"):
        parser = Assets()
        parser.feed(page.read_text())
        for link in parser.links:
            path = urlsplit(link)
            if path.scheme or path.netloc or not path.path:
                continue
            assert (page.parent / unquote(path.path)).exists(), (page.name, link)
        if page == MARKETING / "site/index.html":
            scripts = parser.scripts
    for name in ("device-setup-light", "device-setup-dark", "agent-tools-light", "agent-tools-dark",
                 "connection-saved-light", "connection-saved-dark"):
        data = (MARKETING / f"screenshots/{name}.png").read_bytes()
        assert data[:8] == b"\x89PNG\r\n\x1a\n"
        assert struct.unpack(">II", data[16:24]) == (2000, 1680)
    provenance = json.loads((MARKETING / "screenshots/provenance.json").read_text())
    assert provenance["view_sha256"] == hashlib.sha256((ROOT / "Sources/Debagr/DeviceSetupWindow.swift").read_bytes()).hexdigest()
    assert (MARKETING / "video/debagr-promo.srt").read_text().startswith("1\n00:00:00,000 --> 00:00:06,000")
    for name, size in (("landscape", (1920, 1080)), ("vertical", (1080, 1920))):
        result = json.loads(subprocess.check_output([
            "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json",
            str(MARKETING / f"video/debagr-promo-{name}.mp4")]))
        stream = result["streams"][0]
        assert (stream["width"], stream["height"]) == size
        assert stream["codec_name"] == "h264" and stream["pix_fmt"] == "yuv420p"
        assert float(result["format"]["duration"]) == 24
    # No browser or network access: exercise only the link activation logic.
    script = '\n'.join(scripts)
    test = '''
const assert = require('node:assert/strict');
const vm = require('node:vm');
function check(url, enabled) {
  const links = Object.fromEntries(['download','sponsor','kofi','funding-status'].map(id => [id, {
    href: '#preparing', textContent: 'preparing', disabled: true,
    removeAttribute() { this.disabled = false; }, hasAttribute() { return this.disabled; }
  }]));
  vm.runInNewContext(SCRIPT, {window: {DEBAGR_DOWNLOAD_URL:url, DEBAGR_SPONSOR_URL:url, DEBAGR_KOFI_URL:url},
    document: {getElementById:id=>links[id]}, URL});
  for (const id of ['download','sponsor','kofi']) {
    assert.equal(links[id].disabled, !enabled);
    assert.equal(links[id].href, enabled ? url : '#preparing');
  }
}
for (const url of ['', 'javascript:alert(1)', 'http://example.com/', '/relative']) check(url,false);
check('https://example.com/verified',true);
'''.replace('SCRIPT', json.dumps(script))
    subprocess.run(["node", "-e", test], check=True)
    for file in MARKETING.rglob("*"):
        if file.suffix in (".html", ".js", ".json", ".swift"):
            assert not re.search(r"[0-9A-F]{8}-[0-9A-F]{16}", file.read_text()), "Real-looking device identifier in assets"
    print("Marketing checks passed: local assets, native PNG sizes, both MP4 formats, and 5 URL activation scenarios.")


if __name__ == "__main__":
    main()
