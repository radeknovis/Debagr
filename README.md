<p align="center">
  <img src="Marketing/AppIcon.png" alt="Debagr app icon" width="88" height="88">
</p>

<h1 align="center">Debagr</h1>

<p align="center"><strong>Your Mac stays home. Your next build comes with you.</strong></p>

<p align="center">Ask Claude Code, Codex, or your terminal to install and launch a signed iPhone build<br>through its paired Mac—even on another Wi-Fi network.</p>

<p align="center">
  <a href="docs/RELEASE.md"><img src="https://img.shields.io/badge/source-0.3.0_preview-blue" alt="Source: 0.3.0 preview"></a>
  <a href="docs/COMPATIBILITY.md"><img src="https://img.shields.io/badge/remote_deployment-macOS_26%2B-black" alt="Remote deployment: macOS 26+"></a>
  <a href="docs/COMPATIBILITY.md"><img src="https://img.shields.io/badge/Mac-Apple_silicon-black" alt="Apple silicon Mac"></a>
  <a href="#quick-start"><img src="https://img.shields.io/badge/install-Homebrew-FBB040" alt="Install with Homebrew"></a>
  <a href="docs/EULA.md"><img src="https://img.shields.io/badge/licence-free_evaluation-lightgrey" alt="Licence: free evaluation"></a>
</p>

<p align="center"><a href="#quick-start">Get started</a> · <a href="docs/PLUGINS.md">Agent plugins</a> · <a href="docs/COMPATIBILITY.md">Compatibility</a></p>

**Technical preview:** one managed remote device. One iPhone install and
OS-confirmed launch verified over Tailscale with a 0.3.0 candidate. Wi-Fi and a
private VPN required; cellular-only operation is unsupported.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Marketing/screenshots/device-setup-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="Marketing/screenshots/device-setup-light.png">
  <img src="Marketing/screenshots/device-setup-light.png" alt="Debagr Connection screen: select an already paired device to set up remote deployment" width="860">
</picture>

*Connection screen in the 0.3.0 source preview, shown with sample device data.*

## From prompt to pocket

Install the [Claude Code or Codex plugin](docs/PLUGINS.md), then ask:

> Use Debagr on `build-server` to install and launch
> `/Users/me/Builds/MyApp.app` on my iPhone.

The agent checks readiness and invokes Debagr on the paired Mac. An illustrative
CLI call and successful result look like this (result fields excerpted):

```sh
debagr --deploy-app /Users/me/Builds/MyApp.app --device DEVICE_ID --launch --json
```

```json
{"installed": true, "launched": true}
```

Success also requires the expected bundle identifier. If the device needs
unlocking or its connection needs attention, the agent gets a recovery instruction.

## How it works

```mermaid
flowchart LR
    Agent["Claude Code / Codex / terminal"] -->|"SSH or local CLI"| Mac["Paired Builder Mac · Debagr + Xcode"]
    Mac <-->|"Private VPN · separate Wi-Fi networks"| Phone["iPhone"]
```

The paired Mac builds, signs, installs and launches. Apple pairing and signing
stay on that Mac. Your agent can run there or use your existing SSH access;
the phone does not become an Xcode destination on another Mac.

## Quick start

```sh
brew install --cask radeknovis/debagr/debagr
```

The distribution docs currently list **0.2.0** as the published download.
This README's screenshots and experimental pairing features describe **0.3.0
(build 5)** in source; Homebrew does not install that candidate yet. See
[distribution and updates](docs/DISTRIBUTION.md) for release details.

1. **Pair once.** On the Mac that will build and deploy, install Xcode, connect
   your device by USB, grant trust, and enable Developer Mode.
2. **Save the connection.** Connect the Mac and device to your private VPN.
   While the device is nearby, choose **Open Debagr** → **Use existing pairing**.
   Select the paired device, its VPN address and its nearby service, confirm
   they identify the same device, then choose **Save and Check Connection**.
3. **Deploy from anywhere with Wi-Fi.** Leave Debagr running in the paired Mac's
   logged-in session. Install the [agent plugin](docs/PLUGINS.md), give your agent
   the Mac's SSH alias and signed device `.app` path, and ask it to deploy.
   Keep the device unlocked and connected to the VPN.

[Detailed setup instructions](docs/PLUGINS.md#set-up-the-paired-mac-and-device)
include the connection steps and agent configuration.

### What you need

- An Apple-silicon Mac running **macOS 26+** for managed remote deployment.
- Current Xcode and a signed **device** `.app` build.
- A device paired with that Mac over USB once, with Developer Mode enabled.
- A private VPN on both the Mac and device; **Tailscale** is the hardware-verified path.
- Wi-Fi and an unlocked device during deployment.
- Existing SSH access when your agent runs on another computer.

The preview is free for personal/internal evaluation, with no redistribution.
Read the [preview licence](docs/EULA.md).

## CLI and recovery

<details>
<summary>Deploy directly from your terminal</summary>

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

</details>

## Advanced setup

Everyday wireless deployment needs one paired **Builder** Mac.

For an already paired phone plugged into another Mac, use the experimental
[cable service bridge](docs/CABLE_SHARING.md) through `debagr --cable`.
It forwards device services over Tailscale, with SSH controlling the cable host.
It requires an explicit cable endpoint and RemotePairing port. The phone must
already be paired with this Builder.

Authenticated connectivity and signed app installation were verified on one
MacBook Pro cable host with phone Wi-Fi off. Launch, debugger attachment,
automatic discovery and reconnect remain unverified or unimplemented.

For an iPhone or iPad that still needs to trust the Builder, choose **Pair via
USB/IP** on both Macs. The Mac with the cable exports the selected USB device
and the Builder imports it for Apple’s Trust prompt. This experimental route
requires separate USB tools and administrator approval. First-time trust over
USB/IP remains unverified on hardware. See the [USB/IP setup guide](docs/usbip.md).

## Preview limits

<details>
<summary>Hardware evidence and remaining validation</summary>

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
- cable bridge launch/debugger attachment and recovery.

</details>

## Learn more

- [Setup and agent plugins](docs/PLUGINS.md)
- [Compatibility and hardware evidence](docs/COMPATIBILITY.md)
- [VPN providers and network setup](docs/NETWORK_PROVIDERS.md)
- [Support and troubleshooting](docs/SUPPORT.md)
- [Development and packaging](docs/DEVELOPMENT.md)
