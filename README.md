# Debagr

Install signed iPhone and iPad apps through the Mac they are paired with, while
the device is on another Wi-Fi network. Debagr runs on that Mac; your agent or
terminal invokes its CLI locally or over your existing SSH access.

## Install and set up

```sh
brew install --cask radeknovis/debagr/debagr
```

The published 0.2.0 technical preview requires Apple silicon, macOS 26+, current
Xcode, USB pairing, Developer Mode and a private VPN on both endpoints.
Keep the device unlocked on Wi-Fi; cellular-only operation is unsupported.

Follow the [setup guide](Marketing/site/setup.html), then install the
[Claude Code or Codex plugin](docs/PLUGINS.md). In Settings, select the paired
device, its nearby service and its VPN address, confirm they refer to the same
physical device, and choose **Connect device**. Leave Debagr running in that
Mac user's logged-in session.

## Deploy

Run on the paired Mac, using the signed device .app's path on that Mac:

```sh
debagr --devices --json
debagr --status --device DEVICE_ID --timeout 30 --json
debagr --deploy-app /absolute/path/App.app --device DEVICE_ID --launch --json
```

Recheck readiness after a build or artifact transfer. Allow 180 seconds for
installation and launch. Success requires the expected bundle identifier,
`installed: true` and `launched: true`. Apple pairing and signing stay on the
paired Mac; devices do not become Xcode destinations on another Mac.

The source branch also provides `--installed-apps`, `--launch-app`, deeper
`--diagnose` checks, and an optional [local MCP interface](docs/MCP.md).
These changes have not yet been released in the published 0.2.0 binary.

## Scope and evidence

One managed remote device is supported. Tailscale has prior remote iPhone
install-and-launch evidence. Headscale, ZeroTier, NetBird, WireGuard and remote
iPad acceptance still need hardware validation. Local tests and a VPN connection
alone do not establish a working Apple deployment path.

- [Compatibility](docs/COMPATIBILITY.md) and [hardware evidence](docs/DIRECT_DEVICE.md)
- [VPN providers](docs/NETWORK_PROVIDERS.md) and [CLI/recovery contract](docs/AI_DEPLOYMENT.md)
- [Distribution](docs/DISTRIBUTION.md), [support](docs/SUPPORT.md) and [security](docs/SECURITY.md)
- [Privacy](docs/PRIVACY.md) and [preview licence](docs/EULA.md): free personal/internal evaluation, no redistribution
- [Development and packaging](docs/DEVELOPMENT.md), [architecture](docs/ARCHITECTURE.md), [release runbook](docs/RELEASE.md)
- [Audit implementation and validation status](docs/AUDIT_FIXES.md)
