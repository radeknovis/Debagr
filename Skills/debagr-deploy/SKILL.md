---
name: debagr-deploy
description: Deploy a signed iOS or iPadOS app to a physical device using Debagr on its paired Mac, including across separate Wi-Fi networks through a private VPN. Use when asked to install or launch a build on a device, deploy through a remote Mac build server, or diagnose Debagr device readiness.
---

# Deploy with Debagr

Debagr runs on the Mac that owns Apple's device pairing. The menu-bar app owns
the remote-device relay. Invoke its CLI locally on that Mac or through existing
SSH access; the AI caller does not need to see the device in its own Xcode.
The device and paired Mac can be on separate Wi-Fi networks when connected
through a private VPN. Complete USB pairing and local device configuration before
taking the device remote; keep Debagr running on the paired Mac.

The current deployment path supports iPhone and iPad. A Mac can be the build
server or agent's computer; deploying macOS apps to a Mac target is not yet
implemented. Explain that boundary if asked to deploy to a Mac target.

## Deployment

1. Resolve the Build Server, project build instructions, and Debagr executable
   from the user's project configuration. The installed executable is
   `/Applications/Debagr.app/Contents/MacOS/Debagr`. If the Build Server is
   unspecified, ask which paired Mac to use. Run `--help` to check capabilities.
2. Run `--devices --json` on the Build Server. Select the intended stable
   `deviceIdentifier`; ask if multiple devices match. Inventory state and
   VPN reachability are not proof of readiness.
3. Run `--status --device <UDID> --timeout 30 --json`. Proceed only when
   `ok` is true and `result.state` is `ready`. For failures, use the returned
   recovery instruction. Human actions include unlocking the device, enabling
   Wi-Fi/the selected VPN, opening Debagr, and granting Apple trust over USB.
4. Build the signed device `.app` using the project's existing workflow on the
   Build Server, or use the explicit artifact supplied by the user. Confirm its
   absolute path on that Mac. If built elsewhere, copy the complete signed .app
   with its contents preserved to that Mac using existing SSH/SCP access, and
   verify its Info.plist bundle identifier there. A simulator build is not a device artifact.
5. Re-run the readiness check after the build or transfer; the device may have
   locked in the meantime. Run `--deploy-app <absolute-device.app> --device <UDID> --launch --json`.
   Allow at least 180 seconds for this command; do not interrupt an active install.
   The result must have `ok: true`, the expected bundle identifier,
   `installed: true`, and `launched: true` to report installation and launch.
   For an install-only request omit `--launch` and report installation only.

Pass paths as single arguments. When using SSH, shell-quote each remote
argument, including the executable and artifact path. Run under the same macOS
user that runs Debagr and owns the Apple pairing. SSH authentication remains
the existing authorization mechanism; request any additional access from the user.

## Recovery

Use `--diagnose --device <UDID> --timeout 30 --json`. All machine commands emit one JSON object
on stdout with `schemaVersion: 1`; check both `ok` and the process exit code.
Exit codes: `0` success, `2` device/network needs attention, `64` invalid
arguments, `65` invalid artifact, `1` command/deployment failure.

`launch_failed` reports `installed: true` and the bundle identifier. Retry
launch only with `--launch-app <bundleID> --device <UDID> --json` when that
command appears in `--help`. On published 0.2.0, use Apple's `xcrun devicectl
device process launch --device <UDID> --timeout 30 <bundleID>` instead.
For an uncertain installation outcome, use `--installed-apps --device <UDID>
--json` when available, or Apple's `devicectl device info apps` before retrying. A timed-out
installation has an uncertain outcome: inspect installed apps before retrying.

Remote deployment requires the device to be on Wi-Fi. Cellular-only
RemotePairing is excluded by iOS. Describe an unavailable service without
assuming cellular is the cause: Wi-Fi, lock state, VPN state, and trust can
produce similar symptoms.

## Setup boundary

The human installs Debagr, pairs the device over USB, and uses **Set Up
Remote Device** to select the Apple device, its local Bonjour service, and the
same physical device in the selected VPN. **Connect Remote Device** enables the relay;
**Launch at Login** restores the app after login. One remote device is supported
by this milestone; ordinary local Apple device deployment remains available.

Use `--configure` only when the user requests setup or a configuration change.
For setup/capture, `--provider` accepts `tailscale` (default), `headscale`,
`zerotier`, `netbird`, or `wireguard`. Tailscale and Headscale resolve `--peer`
through the local Tailscale client. Other providers require the device’s explicit
private VPN IPv4 address as `--peer`; they do not run the Tailscale client.
Imported profiles must match the selected provider and address. Keep the
existing provider unless the user requests a change.

The local capture requires the real device's Bonjour service. A private existing
profile can instead be imported with `--profile <path>`. Readiness must still
be verified against the explicit Apple device ID.

Keep private profiles and pairing records on the Build Server. Export only
the public JSON results. Do not alter signing credentials, replace device trust,
or restart unrelated Apple daemons to make a deployment pass.

An OS-confirmed launch is not a visual UI test. Report screenshots or app
behavior only when separately verified with appropriate device tools.
