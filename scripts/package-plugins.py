#!/usr/bin/env python3
"""Package the shared deployment skill for Claude Code and Codex; verify each ZIP."""

import hashlib
import json
from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile


def main():
    root = Path(__file__).resolve().parent.parent
    manifests = {
        "claude-code": ".claude-plugin/plugin.json",
        "codex": ".codex-plugin/plugin.json",
    }
    metadata = {host: json.loads((root / path).read_text()) for host, path in manifests.items()}
    version = metadata["codex"]["version"]
    assert re.fullmatch(r"\d+\.\d+\.\d+", version), "Expected a numeric semantic version"
    for manifest in metadata.values():
        assert manifest["name"] == "debagr" and manifest["version"] == version
        assert manifest["skills"] == "./Skills/"
    assert metadata["codex"]["requires_local_executor"] is True

    skill = "Skills/debagr-deploy/SKILL.md"
    common = {
        "README.md": (root / "docs/PLUGINS.md").read_text().replace(
            "](NETWORK_PROVIDERS.md)", "](docs/NETWORK_PROVIDERS.md)"
        ).encode(),
        "docs/AI_DEPLOYMENT.md": (root / "docs/AI_DEPLOYMENT.md").read_bytes(),
        "docs/PLUGINS.md": (root / "docs/PLUGINS.md").read_bytes(),
        "docs/NETWORK_PROVIDERS.md": (root / "docs/NETWORK_PROVIDERS.md").read_bytes(),
    }
    for path in sorted((root / "Skills/debagr-deploy").rglob("*")):
        assert not path.is_symlink(), "Plugin resources must be self-contained"
        if path.is_file():
            common[path.relative_to(root).as_posix()] = path.read_bytes()
    assert common[skill].startswith(b"---\nname: debagr-deploy\n")

    output = root / "dist"
    output.mkdir(exist_ok=True)
    for host, manifest_path in manifests.items():
        catalog_path = (
            ".claude-plugin/marketplace.json" if host == "claude-code"
            else ".agents/plugins/marketplace.json"
        )
        catalog = json.loads((root / catalog_path).read_text())
        assert catalog["name"] == "debagr-plugins"
        assert catalog["plugins"][0]["name"] == "debagr"
        source = catalog["plugins"][0]["source"]
        assert source == "./" or source == {"source": "local", "path": "./"}
        files = dict(common)
        for name in (manifest_path, catalog_path):
            files[name] = (root / name).read_bytes()
        prefix = f"debagr-{host}-{version}"
        archive = output / f"{prefix}.zip"
        with ZipFile(archive, "w", ZIP_DEFLATED) as bundle:
            for name, content in sorted(files.items()):
                bundle.writestr(f"{prefix}/{name}", content)
        # Verify the exported bytes and allowlist, including the canonical skill.
        with ZipFile(archive) as bundle:
            assert bundle.testzip() is None
            assert set(bundle.namelist()) == {f"{prefix}/{name}" for name in files}
            for name, content in files.items():
                assert bundle.read(f"{prefix}/{name}") == content
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        archive.with_suffix(".zip.sha256").write_text(f"{digest}  {archive.name}\n")
        print(f"Verified {archive}")


if __name__ == "__main__":
    main()
