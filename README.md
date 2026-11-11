# Debagr

Install signed iPhone and iPad apps through the Mac they are paired with, while
the device is on another Wi-Fi network. Debagr runs on that Mac; your agent or
terminal invokes its CLI locally or over your existing SSH access.

## Install and set up

```sh
brew install --cask radeknovis/debagr/debagr
```

Debagr 0.3.0 (build 5) is a technical preview for Apple silicon. Release builds
are Developer ID signed and notarized. Managed remote deployment needs macOS 26
or later on the Mac, current Xcode, USB pairing, Developer Mode and a private
VPN on both endpoints. Keep the device unlocked on Wi-Fi; cellular-only
operation is unsupported.

Follow the [setup guide](Marketing/site/setup.html), then install the
[Claude Code or Codex plugin](docs/PLUGINS.md). In short: choose **Open Debagr**
in the menu-bar menu. With no saved device, the Connections window opens on
**Use existing pairing**. Select the paired device, its VPN address and its
nearby service, confirm that they refer to the same physical device, and choose
**Save & check connection**. Leave Debagr running in that Mac user's logged-in
session.

## Builder and Client

Debagr names two roles for a Mac. The **Builder** compiles apps, holds the Apple
pairing and deploys. Everyday wireless deployment needs only a Builder. A
**Client** is a second Mac that has the device plugged in by cable. It is needed
only to create the first Apple trust when you cannot bring the device to the
Builder.

A role is saved when you link two Macs on the **Initial device pairing** screen.
Debagr listens for other Debagr Macs on your private network (TCP 49388 and
49389, with Bonjour advertisements) only while that screen is open, while a
role is saved on the Mac, or while you run `debagr --usbip discover` or
`debagr --usbip advertise` yourself. Two Macs link without a code only when Tailscale
reports that the same Tailscale user owns both. In every other case both Macs
show a pairing code that you compare before accepting.

## Experimental USB pairing

**Initial device pairing** is the second option in the window's path picker and
is labelled Experimental. It forwards USB from the Client so that the Builder
can pair with a device plugged into the Client. It requires:

- two Macs running Debagr 0.3.0;
- a separately installed USB tool: a patched Longcable server plus usbip-macos,
  or VirtualHere;
- for USB/IP, an administrator password on both Macs and System Integrity
  Protection turned off on the Builder, which lowers that Mac's protection.

No USB path has passed hardware acceptance. See
[USB setup prerequisites](docs/usbip.md) and the
[connection design](docs/CONNECTION_DESIGN.md).

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

For recovery, `--installed-apps` lists installed apps after an uncertain
installation, `--launch-app` retries a launch without reinstalling, and
`--diagnose` reports individual checks. An optional
[local MCP interface](docs/MCP.md) exposes the same commands over stdio.

## Scope and evidence

One managed remote device is supported. Verified on hardware: one remote iPhone
installation and OS-confirmed launch over Tailscale on 10 November 2026 with a
0.3.0 candidate build. Local tests and a VPN connection alone do not establish
a working Apple deployment path.

Not yet verified for 0.3.0:

- first launch on a clean Mac, and first launch offline;
- iPad;
- recovery after restart, sleep and wake, a network change, revoked trust or
  denied Local Network permission;
- Headscale, ZeroTier, NetBird and WireGuard;
- macOS 13 to 15;
- the Homebrew upgrade from 0.2.0 to 0.3.0;
- all hardware use of USB/IP, VirtualHere and two-Mac Builder/Client linking.

## More

- [Compatibility](docs/COMPATIBILITY.md) and [hardware evidence](docs/DIRECT_DEVICE.md)
- [VPN providers](docs/NETWORK_PROVIDERS.md) and [CLI/recovery contract](docs/AI_DEPLOYMENT.md)
- [Distribution](docs/DISTRIBUTION.md), [support](docs/SUPPORT.md) and [security](docs/SECURITY.md)
- [Privacy](docs/PRIVACY.md) and [preview licence](docs/EULA.md): free personal/internal evaluation, no redistribution
- [Development and packaging](docs/DEVELOPMENT.md), [architecture](docs/ARCHITECTURE.md), [release runbook](docs/RELEASE.md)
- [Connection design](docs/CONNECTION_DESIGN.md), [USB setup prerequisites](docs/usbip.md), and [restoration provenance](docs/CONSOLIDATION.md)
- [Audit implementation and validation status](docs/AUDIT_FIXES.md)
