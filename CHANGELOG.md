# Changelog

## 0.3.1 — Technical preview

Build 9, Apple silicon. Setup opens on existing Apple pairing over VPN. A second option starts experimental USB/IP setup for a new Builder. The paired cable bridge and updated setup guides are included.

## 0.3.0 — Technical preview

Build 5, Apple silicon. Published 12 November 2026.

Audit fixes:

- Fixed readiness deadlines, structured device errors and uncertain install outcomes.
- Added `--installed-apps`, `--launch-app`, deeper `--diagnose` output, `--version`
  and an optional local stdio MCP interface (`--mcp`) with no network listener.
- Shared relay listener lifecycle, bounded UDP/TCP resources, added backpressure
  and native Bonjour registration.
- Improved Settings validation, saved configuration, keyboard shortcuts, copy
  feedback and responsiveness.
- Added a free personal/internal evaluation licence with no redistribution.
- Pinned CI tooling, reproducible plugin packaging and strict-concurrency
  regression checking.
- Added forwarding, Bonjour, CLI and setup regression checks.

Connection design:

- Combined Connection, Agent tools and Preferences in one window with a status menu.
- Added guided existing pairing (Pairing, Connection, Review) with explicit
  confirmation that the device, wireless service and VPN endpoint are the same
  physical device. With no saved device, setup opens on this path.
- Added Builder and Client discovery and role linking between two Macs, with
  signed role updates and pinned peer keys. Linking Macs does not transfer
  Apple trust.
- Added experimental temporary USB setup through USB/IP or VirtualHere. Both
  paths are labelled Experimental and state their requirements before starting:
  two Macs running Debagr 0.3.0, a separately installed USB tool, and for USB/IP
  an administrator password on both Macs and System Integrity Protection turned
  off on the Builder. "SIP off" is no longer shown as a good state.
- Agent tools provides the shared Debagr skill and installation links; generated
  deployment prompts and per-device command copying are removed.

Network behaviour:

- Peer discovery (TCP 49388, `_debagr._tcp`) and role sync (TCP 49389,
  `_debagr-role._tcp`) run only while the Builder and Client setup screen is open
  or a machine role is saved on this Mac. Otherwise there is no listener, Bonjour
  advertisement, periodic process or USB inventory, or tailnet probing. The
  foreground commands `debagr --usbip discover` and `advertise` still start both
  while they run.
- The unauthenticated discovery reply to an ordinary private-network client
  contains only protocol version, node ID, Mac name, process roles, machine
  role, paired node ID and role-pairing public key. SIP status and plugged-in
  Apple device product names go only to loopback and to a connection verified
  as the same Tailscale user's own device.
- Pairing without a code requires the Tailscale network map to show the remote
  Mac is owned by the same Tailscale user. Tagged devices and other users'
  devices in a shared tailnet use the pairing-code prompt on both Macs: the Mac
  that starts a first link now also asks before it saves the role and pins the key.

USB/IP hardening:

- `debagr --usbip probe` and `attach` find the bundled USBIPProbe helper when
  `debagr` is run through a symlink such as the Homebrew link.
- The root USB supervisor acts only on the administrator-approved command line,
  checks the selected tool's SHA-256 and runs a root-owned private copy of it.
- Removed personal build directories under `~/src` as default USB tool locations.

Evidence and gaps:

- Verified on hardware: one remote iPhone install and OS-confirmed launch over
  Tailscale on 10 November 2026, using this version's CLI in a pre-release build.
- Not verified: clean-Mac first launch, offline first launch, iPad, the recovery
  matrix (restart, sleep/wake, network change, revoked trust, denied Local
  Network permission), VPN providers other than Tailscale, macOS 13–15, the
  Homebrew 0.2.0 to 0.3.0 upgrade, and all hardware acceptance of USB/IP,
  VirtualHere and two-Mac Builder/Client linking.

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
