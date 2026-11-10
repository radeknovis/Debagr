# Changelog

## 0.3.0 — Unreleased audit fixes

- Fixed readiness deadlines, structured device errors and uncertain install outcomes.
- Added launch-only and installed-app queries, deeper diagnostics and optional local stdio MCP.
- Shared relay listener lifecycle, bounded UDP/TCP resources, added backpressure and native Bonjour registration.
- Improved Settings validation, saved configuration, keyboard shortcuts, copy feedback and responsiveness.
- Added a free personal/internal evaluation licence with no redistribution.
- Pinned CI tooling, reproducible plugin packaging and strict-concurrency regression checking.
- Added forwarding, Bonjour, CLI and setup regression checks; live remote hardware acceptance remains pending.

## 0.2.0 — Technical preview (4 November 2026)

- Added native macOS settings for device setup and agent onboarding.
- Added a JSON CLI for inventory, readiness, diagnostics, installation, and launch.
- Added Claude Code and Codex plugin archives with the same deployment workflow.
- Added Tailscale and Headscale peer discovery, plus manual private IPv4 entry
  for ZeroTier, NetBird, and WireGuard.
- Published a Developer ID signed, notarized Apple-silicon DMG and the
  `radeknovis/debagr/debagr` Homebrew cask.
- Not yet verified for this release: clean-Mac first launch, a fresh remote
  install and launch, iPad, and the recovery matrix.

## 0.1.0 — Technical preview

- Added a native menu-bar inventory that merges physical iPhone/iPad results
  from Apple `devicectl` with visible Bonjour services.
- Added first-run requirements, bounded empty state, accessible device details,
  Launch at Login, native About, support links, and redacted diagnostics copy.
- Added a branded app icon and reproducible app/DMG packaging scripts.
- Added compatibility, privacy, EULA, support, security, release, and launch
  research documents.
- Kept cross-Mac RemotePairing as an explicitly experimental command-line lab.
