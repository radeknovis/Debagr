# Debagr

Debagr is a native macOS build-server agent for deploying signed iOS and iPadOS
apps to devices paired with that Mac. Any computer, CI job, or agent that can
SSH into the build server can invoke the same deployment command; the iPhone
does not need to appear on the caller's machine.

The app ships two deliberately separate surfaces:

- The product UI merges Apple `devicectl` inventory with visible
  `_remotepairing._tcp` services, shows human-readable Target Device details,
  explains first-run requirements, supports Launch at Login, and copies a
  diagnostics report without Bonjour TXT values.
- The command line preflights a specific paired device, installs a signed
  device `.app` with Apple's `devicectl`, confirms the installed bundle ID, and
  optionally launches it.
- The old cross-Mac RemotePairing relay remains only as a research lab. It is
  not part of the deployment product.

## Build and test

The menu-bar monitor supports macOS 13 or later. The experimental relay's exact
Network.framework address binding requires macOS 26 or later.

```sh
swift build
swift test
```

The executable is `.build/debug/debagr`.

## Package the app

```sh
./scripts/build-macos-app.sh release
./scripts/verify-macos-app.sh
open Debagr.app
```

The default build is ad-hoc signed for local testing. A customer release must
use a Developer ID Application identity and Apple's notarization service:

```sh
VERSION=1.0.0 \
BUILD_NUMBER=42 \
CODESIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)" \
NOTARY_PROFILE="debagr-notary" \
DEBAGR_WEBSITE_URL="https://example.com/debagr" \
DEBAGR_SUPPORT_URL="https://example.com/debagr/support" \
./scripts/release-macos-app.sh
```

That produces a notarized, stapled DMG and SHA-256 checksum in `dist/`. See
[`docs/RELEASE.md`](docs/RELEASE.md) for the account-bound setup and clean-Mac
acceptance checklist.

## Menu-bar behavior

On first launch Debagr explains the required Xcode, Developer Mode, USB trust,
and wireless-device steps. Its menu then:

- reports `Looking`, `No Target Devices found`, a Target Device count, or a
  discovery failure;
- lists each Target Device with kind, Bonjour host, identifier, and port;
- shows Developer Tools and Tailscale prerequisite checks;
- refreshes discovery, toggles Launch at Login, and opens native About;
- copies an agent-ready deployment command for each Apple-identified device;
- copies a support report containing app/system status and endpoints, but no
  TXT records or RemotePairing payloads.

“Visible” is intentional. A Bonjour record does not prove that Xcode can list,
install, launch, or debug on a Target Device.

## Build-server deployment

Build a signed device `.app` on the paired Mac, then run:

```sh
/Applications/Debagr.app/Contents/MacOS/Debagr \
  --deploy-app /absolute/path/MyApp.app \
  --device DEVICE_UDID \
  --launch
```

Remote callers use the same command through the build server's existing SSH
authentication. Tailscale is recommended as the private network, but Debagr
does not require a custom client or expose its own network listener:

```sh
ssh build-server \
  "/Applications/Debagr.app/Contents/MacOS/Debagr \
  --deploy-app /absolute/path/MyApp.app --device DEVICE_UDID --launch"
```

The `.app` must already exist on the build server and be signed for the Target
Device. This keeps source checkout, signing, and build configuration under the
project's existing Xcode or CI workflow.

## Experimental relay lab

Select a Tailscale peer and known RemotePairing port explicitly:

```sh
debagr --peer paired-mac --remote-port 49640
```

On the Mac that can already see the Target Device locally, the peer-side lab
forwarder is:

```sh
debagr --forward-remote --peer developer-mac --remote-port 49152
```

If more than one Target Device is present, constrain the captured service:

```sh
debagr --forward-remote \
  --peer developer-mac \
  --bonjour-host My-iPhone.local \
  --remote-port 49152
```

Discover all physical iPhones and iPads known to `devicectl`, enriched with any
complete local Bonjour services:

```sh
debagr --discover --timeout 5
```

The peer-side command now writes the captured instance name and TXT metadata to
the selected profile. Copy that profile to the Developer Mac before starting
its relay so the local projection preserves the Apple service identity.

This proves the fixed RemotePairing control port can be projected through a
tailnet. It does **not** make the Target Device usable from a differently paired
Mac: Apple pairing state belongs to each Mac, and CoreDevice negotiates a
dynamic link-local IPv6 tunnel after the control connection. Tailscale's macOS
transport and Debagr's layer-4 relay do not route that endpoint.

Before any future end-to-end experiment, require an honest relay-off baseline:

```sh
./scripts/verify-remote-environment.sh paired-mac paired-mac-tailnet-name DEVICE_UDID
```

The check refuses to continue when the Developer Mac can already reach the
Target Device directly, which prevents a shared-LAN false positive.

## Safety boundaries

- Tailscale is resolved only from fixed executable paths and a selected peer
  must be online.
- Relay destinations are restricted to the peer's `100.64.0.0/10` IPv4 address.
- Listeners bind to the selected local interface, not `0.0.0.0`.
- By default, only this Mac's local interface address and loopback are accepted.
  `--allow-lan` is an explicit opt-in.
- RemotePairing bytes remain opaque. Debagr does not authenticate, decrypt,
  inspect, or log the payload.
- Owned child processes receive argument arrays directly and are stopped by
  process identifier.

These controls do not replace the missing mutual Debagr authorization design.
Do not sell or publicly promise transparent cross-Mac Xcode access. The current
layer-4 architecture cannot carry CoreDevice's negotiated link-local tunnel.

## Product and launch material

- [`docs/LAUNCH_RESEARCH.md`](docs/LAUNCH_RESEARCH.md) — primary-source channel,
  pricing, competitor, and risk research.
- [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) — exact supported and
  experimental claims.
- [`docs/PRIVACY.md`](docs/PRIVACY.md), [`docs/EULA.md`](docs/EULA.md),
  [`docs/SUPPORT.md`](docs/SUPPORT.md), and [`docs/SECURITY.md`](docs/SECURITY.md)
  — release-policy drafts requiring owner/legal review.
- [`Marketing/site/index.html`](Marketing/site/index.html) — dependency-free
  launch site. Checkout remains closed until its hardware and security gates
  pass; one URL in `config.js` opens it later.

## Paid-launch gate

Debagr is not ready for paid distribution until the packaged app passes
install-and-launch tests through SSH on clean build-server Macs with current
iPhone and iPad hardware, including locked-device recovery, restart, sleep,
network change, revoked trust, and deterministic failure reporting. Developer
ID, notarization, storefront, domain, and legal-owner credentials remain
account-bound release gates.
