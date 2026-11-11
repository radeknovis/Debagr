# Debagr development

Run these commands from the repository root.




The local menu-bar inventory supports macOS 13 or later. Remote deployment and
the experimental relay retain a macOS 26 support floor pending older-OS acceptance. The preview package targets Apple silicon.

```sh
swift build
swift test
```

The executable is `.build/debug/debagr`.

### Package the app

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
[`docs/RELEASE.md`](RELEASE.md) for the account-bound setup and clean-Mac
acceptance checklist.

### Package the agent plugins

```sh
python3 scripts/package-plugins.py
```

This creates separate Claude Code and Codex ZIP packages and SHA-256 checksums
in `dist/`. Both include the canonical `Skills/debagr-deploy` directory and
onboarding instructions. Plugin versions live in `.claude-plugin/plugin.json`
and `.codex-plugin/plugin.json` and must match. Packaging verifies archive
contents and skill bytes. CI also produces the plugin archives.

See [plugin installation and validation](PLUGINS.md) for local testing.

## Connection details

<details>
<summary>Menu-bar controls and diagnostics</summary>

Use **Pause Wireless Connection** and **Resume Wireless Connection** to control
the managed connection.
Existing private profiles can be imported. Configuration is stored privately at
`~/.config/debagr/managed-device.json` and excluded from public CLI results.
The app owns its relay; CLI invocations use that running connection.

The menu shows discovered devices and prerequisite checks, refreshes discovery,
and copies deployment commands or support reports. Support reports include
app/system status and endpoints, but exclude TXT records and RemotePairing
payloads. A visible Bonjour service alone does not establish deployment readiness.

</details>

<details>
<summary>Experimental cross-Mac relay lab</summary>


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
  --bonjour-host My-Device.local \
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

</details>

<details>
<summary>Relay safety boundaries</summary>


- Tailscale is resolved only from fixed executable paths and a selected peer
  must be online.
- Tailscale profiles and the legacy relay lab restrict destinations to `100.64.0.0/10`.
  Alternative-provider profiles accept explicitly selected RFC1918 or CGNAT IPv4 addresses.
- Listeners bind to the selected local interface, not `0.0.0.0`.
- By default, only this Mac's local interface address and loopback are accepted.
  `--allow-lan` is an explicit opt-in.
- RemotePairing bytes remain opaque. Debagr does not authenticate, decrypt,
  inspect, or log the payload.
- Owned child processes receive argument arrays directly and are stopped by
  process identifier.

These controls do not replace the missing mutual Debagr authorization design.
Do not sell or publicly promise transparent cross-Mac Xcode access. Direct-device
deployment uses the original paired Build Server and relays its dynamic tunnel
ports; it does not transfer Apple pairing or route a different Mac's negotiated
link-local tunnel.

</details>

## Release status

The 0.2.0 technical preview was published on 4 November 2026 through the public
[Homebrew tap and release](https://github.com/radeknovis/homebrew-debagr) and the
[launch site](https://radeknovis.github.io/debagr-site/). The app source stays private. Clean-Mac first launch,
a fresh remote install and launch, iPad, the recovery matrix and Homebrew
upgrades are not yet verified for 0.2.0.

Paid distribution remains gated on packaged install-and-launch tests through
SSH on clean Macs with current iPhone and iPad hardware. Acceptance includes
locked-device recovery, restart, sleep, network changes, revoked trust, and
clear failure reporting. Storefront, domain, and legal review remain
requirements for paid distribution.

The [shipping report](SHIP_STATUS.md) records completed checks and remaining
gaps. The [launch kit](../Marketing/README.md) includes native screenshots,
landscape and vertical promo videos, launch copy, and sponsorship drafts.
The [launch site](../Marketing/site/index.html) keeps funding links in preparation
until they are activated. Earlier pricing
hypotheses in [launch research](LAUNCH_RESEARCH.md) are not an announced price.

Debagr is not affiliated with or endorsed by Apple or Tailscale.

## Development checks

Run `xcrun swift-format lint --strict --recursive Sources Tests`,
`swift test 2>&1 | xcsift -f toon -w -e -E`, `python3 scripts/check-release.py`,
and `python3 scripts/package-plugins.py`. Install the optional formatter with
`brew install xcsift`; the app packaging script also works without it.
Public installation and the first deployment are described in
[the setup guide](../Marketing/site/setup.html).

## Build and validate packages

From a source checkout, run:

```sh
python3 scripts/package-plugins.py
claude plugin validate .claude-plugin/plugin.json
claude plugin validate .claude-plugin/marketplace.json
```

The packaging command creates `dist/debagr-claude-code-VERSION.zip` and
`dist/debagr-codex-VERSION.zip`, each with a `.sha256` checksum. It checks manifest
version agreement, archive integrity, and byte-for-byte shared skill contents.
For a downloaded ZIP, check its checksum before extraction:

```sh
shasum -a 256 -c debagr-codex-VERSION.zip.sha256
```

Both manifests reference `./Skills/`. The app and both plugins share
`Skills/debagr-deploy`; edit that source rather than copies inside ZIPs. Bump
both manifest versions together for a plugin release. These packages contain
only instructions, metadata, and documentation; no private profiles or binaries.

Before publishing, test each client in a new session and verify a real install
and launch while the device and Mac are on separate networks. Check locked-device
and unavailable-network recovery too. Package validation alone is not a hardware
acceptance test. Public catalog submission and the signed app release are
separate release steps.

## Pinned CI tools

`./scripts/setup-ci-tools.sh` selects hosted Xcode 26.6 (17F113) and downloads xcsift
1.7.4 with a pinned SHA-256. Actions are pinned by commit. CI compiles with
complete concurrency diagnostics and rejects diagnostics outside the reviewed
`.ci/concurrency-baseline.json`. The baseline has 58 unique warnings (111 compiler
emissions); it records migration work, not Swift 6 readiness. Update it only
after reviewing each warning, using `scripts/check-concurrency.py LOG --update-baseline`.

The canonical source version is `VERSION`; packaging checks both manifests, the
Info.plist template and changelog against it. Published site/download links stay
on 0.2.0 until the candidate is accepted and released.

Run `python3 scripts/check-menu-bar-shutdown.py` after packaging to verify
normal SIGTERM exit through AppKit deferred termination. It owns and cleans up
its test child; it never signals an existing Debagr instance.

Local candidate signing and iPhone acceptance used Xcode 27.2 (27B48). The
hosted macos-26-arm64 image supplies Xcode 26.6 (17F113); the CI pin follows
[that image inventory](https://github.com/actions/runner-images/blob/macos-26-arm64/20261102.0473/images/macos/macos-26-arm64-Readme.md).
