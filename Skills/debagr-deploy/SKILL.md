---
name: debagr-deploy
description: Deploy a signed iOS or iPadOS app to a physical device using Debagr on its paired Mac, including across separate Wi-Fi networks through Tailscale. Use when asked to install or launch a build on an iPhone, deploy through a remote Mac build server, or diagnose Debagr device readiness.
---

# Deploy with Debagr

Debagr runs on the Mac that owns Apple's device pairing. The menu-bar app owns
the remote-device relay. Invoke its CLI locally on that Mac or through existing
SSH access; the AI caller does not need to see the iPhone in its own Xcode.
The iPhone and paired Mac can be on separate Wi-Fi networks when connected
through Tailscale. Complete USB pairing and local device configuration before
taking the iPhone remote; keep Debagr running on the paired Mac.

## Deployment

1. Resolve the Build Server, project build instructions, and Debagr executable
   from the user's project configuration. The installed executable is
   `/Applications/Debagr.app/Contents/MacOS/Debagr`. If the Build Server is
   unspecified, ask which paired Mac to use. Run `--help` to check capabilities.
2. Run `--devices --json` on the Build Server. Select the intended stable
   `deviceIdentifier`; ask if multiple devices match. Inventory state and
   Tailscale reachability are not proof of readiness.
3. Run `--status --device <UDID> --timeout 30 --json`. Proceed only when
   `ok` is true and `result.state` is `ready`. For failures, use the returned
   recovery instruction. Human actions include unlocking the phone, enabling
   Wi-Fi/Tailscale, opening Debagr, and granting Apple trust over USB.
4. Build the signed device `.app` using the project's existing workflow on the
   Build Server, or use the explicit artifact supplied by the user. Confirm its
   absolute path on that Mac. A simulator build is not a device artifact.
5. Run `--deploy-app <absolute-device.app> --device <UDID> --launch --json`.
   The result must have `ok: true`, the expected bundle identifier,
   `installed: true`, and `launched: true` to report installation and launch.
   For an install-only request omit `--launch` and report installation only.

Pass paths as single arguments. When using SSH, shell-quote each remote
argument, including the executable and artifact path. Run under the same macOS
user that runs Debagr and owns the Apple pairing. SSH authentication remains
the existing authorization mechanism; request any additional access from the user.

## Recovery

Use `--diagnose --device <UDID> --json`. All machine commands emit one JSON object
on stdout with `schemaVersion: 1`; check both `ok` and the process exit code.
Exit codes: `0` success, `2` device/network needs attention, `64` invalid
arguments, `65` invalid artifact, `1` command/deployment failure.

`launch_failed` reports `installed: true` and the bundle identifier. Retry
launch only, using Apple's `xcrun devicectl device process launch --device
<UDID> --timeout 30 <bundleID>`; installation need not be repeated. A timed-out
installation has an uncertain outcome: inspect installed apps before retrying.

Remote deployment requires the iPhone to be on Wi-Fi. Cellular-only
RemotePairing is excluded by iOS. Describe an unavailable service without
assuming cellular is the cause: Wi-Fi, lock state, VPN state, and trust can
produce similar symptoms.

## Setup boundary

The human installs Debagr, pairs the device over USB, and uses **Configure
Remote iPhone** to select the Apple device, its local Bonjour service, and the
same physical device in Tailscale. **Connect Remote Device** enables the relay;
**Launch at Login** restores the app after login. One remote device is supported
by this milestone; ordinary local Apple device deployment remains available.

Use `--configure` only when the user requests setup or a configuration change.
The local capture requires the real device's Bonjour service. A private existing
profile can instead be imported with `--profile <path>`. Readiness must still
be verified against the explicit Apple device ID.

Keep private profiles and pairing records on the Build Server. Export only
the public JSON results. Do not alter signing credentials, replace device trust,
or restart unrelated Apple daemons to make a deployment pass.

An OS-confirmed launch is not a visual UI test. Report screenshots or app
behavior only when separately verified with appropriate device tools.
