Debagr turns the Mac already paired with your iPhone into a private deployment endpoint for Claude Code, Codex, and your terminal. 0.3.0 is the second public technical preview and replaces 0.2.0.

## What is new

- **Reliability fixes from a full audit.** Readiness checks have working deadlines and fail fast when Apple reports an unknown device. Device errors carry Apple's code, domain and message. A deployment that times out is reported as an unknown outcome, not as a failed installation. The relay has TCP backpressure, keepalive and cancellation handling, bounded UDP flows, native in-process Bonjour registration, and rebuilds unhealthy listeners, including after wake.
- **More CLI commands.** `--installed-apps` lists installed developer apps, `--launch-app` launches one without reinstalling, `--diagnose` reports configuration, network, inventory and VPN detail, and `--version` prints the version. Text and JSON modes return the same exit codes.
- **Optional local MCP interface.** `debagr --mcp` serves the same operations as tools over stdin and stdout. It opens no network listener.
- **One window.** Connection, Agent tools and Preferences share one window. First run opens on **Use existing pairing**, a guided Pairing, Connection and Review flow. Before saving, you confirm that the device, its wireless service and its VPN address belong to the same physical device. A saved profile can be reused when the device is already remote.
- **Builder and Client Macs.** Two Macs running Debagr can find each other and link as Builder (builds and deploys) and Client (has the device plugged in). Role changes are signed by each Mac and checked against the other Mac's pinned key. Linking two Macs is not Apple device pairing and does not transfer Apple trust.
- **Experimental temporary USB setup.** For a device that has not yet trusted the Builder, the Client can forward its USB connection to the Builder through USB/IP or VirtualHere. These paths are labelled **Experimental** in the path picker, need extra software and have no hardware acceptance. See the requirements below.
- **Agent tools.** The screen provides the shared Debagr skill and installation links for Claude Code and Codex. Generated deployment prompts and per-device command copying are removed.
- **Licence.** The preview is free for personal and internal evaluation, with no redistribution. The text is in the app as `Preview-Licence.txt` and on the [legal page](https://radeknovis.github.io/debagr-site/legal.html). Paid terms remain a separate draft and nothing is for sale.

## Network behaviour that changed

0.2.0 had no Debagr-to-Debagr network service. 0.3.0 adds two, used to find and link Builder and Client Macs:

- Peer discovery on TCP 49388, advertised over Bonjour as `_debagr._tcp`.
- Role sync on TCP 49389, advertised over Bonjour as `_debagr-role._tcp`.

Both run only while the Builder and Client setup screen (**Initial device pairing**) is open, or while a Builder or Client role is saved on this Mac. At any other time, unless you run `debagr --usbip discover` or `debagr --usbip advertise` yourself, Debagr opens neither listener, advertises neither service, runs no periodic process or USB inventory, and does not probe your tailnet. If you only use existing pairing and never save a role, they do not start.

The discovery reply is not authenticated. To an ordinary private-network client it contains only the protocol version, a node ID, the Mac's name, its process roles, its machine role, the paired node ID and the role-pairing public key. The Mac's System Integrity Protection status and the product names of plugged-in Apple devices are sent only to loopback and to a connection verified as coming from a device owned by the same Tailscale user. Serial numbers and device identifiers are never sent.

Two Macs link without a pairing code only when the Tailscale network map shows that the other Mac is owned by the same Tailscale user as this Mac. Tagged devices, other users' devices in a shared tailnet and ordinary local-network connections show a pairing code on both Macs. Compare the codes and confirm on each Mac.

## Requirements

This is a **technical preview for Apple silicon**. Managed remote deployment requires macOS 26 or later, current Xcode, initial USB pairing and trust, Developer Mode, an unlocked device on Wi-Fi, a private VPN on both endpoints, and Debagr running in a logged-in session on the paired Mac. Your signed device `.app` must exist on that Mac. Remote agents use your existing SSH access. One managed remote device is supported. Cellular-only operation is unsupported. Apple pairing stays on its original Mac; devices do not become Xcode destinations on other Macs.

The experimental USB setup also requires two Macs running Debagr 0.3.0 and a separately installed USB tool: a patched Longcable server plus usbip-macos, or VirtualHere. USB/IP additionally requires an administrator password on both Macs and System Integrity Protection turned off on the Builder. Debagr does not install or redistribute these tools and never changes System Integrity Protection. Turning it off weakens that Mac's security, so use this path only on a Mac where you accept that.

## Verified and not verified

Verified on real hardware: one remote iPhone install and OS-confirmed launch over Tailscale on 10 November 2026. That run used this version's CLI in a pre-release build, not the published build.

Not verified for 0.3.0:

- First launch on a clean Mac, and an offline first launch.
- iPad.
- The recovery matrix: restart, sleep and wake, network change, revoked trust, and denied Local Network permission.
- VPN providers other than Tailscale.
- macOS 13 to 15.
- The Homebrew upgrade from 0.2.0 to 0.3.0.
- All hardware acceptance of USB/IP, VirtualHere and two-Mac Builder and Client linking.

Automated tests cover these paths where they can. They are not hardware acceptance.

## Install and upgrade

**Download:** choose the versioned Debagr DMG from the attached assets; source-code ZIPs are not the app. Verify the matching SHA-256 file, open the disk image, then drag Debagr to Applications. The app and DMG are Developer ID signed, notarized and stapled. No security bypass is required.

Or use `brew install --cask radeknovis/debagr/debagr` to install the same notarized app and its `debagr` CLI link.

To upgrade from 0.2.0, quit Debagr, then replace the app from the new DMG or run `brew upgrade --cask radeknovis/debagr/debagr`, and open Debagr again. Saved connection profiles in `~/.config/debagr/` are not removed. This upgrade has not been tested; if your saved device is missing afterwards, set it up again and report it. 0.2.0 stays available in Releases for rollback. There is no automatic updater.

## Plugins

Install the matching `debagr-claude-code-0.3.0.zip` or `debagr-codex-0.3.0.zip` using the instructions inside it. Agent tools in Debagr links to the same installation steps. Use the plugin version that matches the app.

## Support and security

Report problems in [Issues](https://github.com/radeknovis/homebrew-debagr/issues) with the exact macOS, Xcode, and iOS versions. Do not post pairing material, device identifiers, hostnames, or diagnostics publicly. Send security and privacy reports, and diagnostics when asked, through [private vulnerability reporting](https://github.com/radeknovis/homebrew-debagr/security/advisories/new).

There is no Debagr cloud, analytics or paid checkout. Sponsorship, when enabled, supports development and does not buy a license or guaranteed support.

Website: https://radeknovis.github.io/debagr-site/
