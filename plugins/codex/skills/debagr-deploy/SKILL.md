---
name: debagr-deploy
description: Safe check -> build -> deploy -> recover workflow for installing and launching signed iOS/iPadOS apps onto a remote physical iPhone or iPad via a paired macOS Builder running Debagr.
---

# Debagr Physical Device Deployment Workflow

Use this skill whenever the user wants to deploy, install, launch, or verify a physical iOS or iPadOS app using **Debagr** on a paired macOS **Builder** (either locally on that Mac or over SSH).

## Core Boundaries (Do Not Violate)
1. **Builder owns pairing and signing:** Never attempt to transfer Apple trust records, provisioning profiles, or signing identities to another machine. Always build and sign on the paired Builder Mac.
2. **Signed `iphoneos` `.app` bundles only:** Debagr does not build or code-sign apps. Provide an already-signed `.app` built for physical `iphoneos` (`-sdk iphoneos`, `-destination 'generic/platform=iOS'`), never `iphonesimulator` or `macosx`.
3. **SSH is the remote boundary:** When running from another computer, invoke `debagr` over the user's existing SSH connection to the Builder Mac (`ssh <builder> debagr ...`). Never open a network deployment listener.
4. **One remote physical iPhone or iPad:** Simulators, Apple Watches, Macs, and cellular-only (no Wi-Fi + private VPN) connections are out of scope.

---

## Step-by-Step Safe Workflow

### 1. Check Readiness Before Building or Deploying
Run readiness first so you know whether the device is configured, reachable over the private VPN bridge (or local USB/Wi-Fi), paired, Developer Mode enabled, and unlocked.

- **MCP:** Call `debagr_check_readiness` (or `debagr_list_devices` to inspect available paired hardware).
- **CLI / SSH:**
  ```bash
  debagr ready
  ```
If `ready` is `false`:
- `DEVICE_NOT_CONFIGURED`: Ask the user to run Debagr Wireless Setup on the Builder Mac while the already-paired phone is nearby.
- `DEVICE_LOCKED`: Ask the user to unlock their iPhone/iPad and keep it awake before launching, or deploy with `--no-launch` / `launch: false` if only installing is needed.
- `DEVICE_UNREACHABLE` / `VPN_UNAVAILABLE`: Run `debagr doctor` (MCP `debagr_diagnose`) and `debagr bridge status`, then guide the user to confirm Wi-Fi + private VPN on both Mac and phone.

### 2. Build & Sign on the Builder Mac
Produce a signed physical-device `.app` bundle on the Builder Mac (for example via `xcodebuild`):
```bash
xcodebuild \
  -scheme <AppScheme> \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  build
```
Locate the resulting `build/Build/Products/Debug-iphoneos/<AppName>.app` bundle. Verify it is an `iphoneos` device bundle (never `*-iphonesimulator`).

### 3. Deploy (Validate -> Install -> Verify -> Launch)
Prefer `deploy` over raw `install` + `launch` because Debagr validates the bundle signature/platform, checks lock state up front, installs, verifies the app via `device info apps`, and launches cleanly.

- **MCP:** Call `debagr_deploy_app` with `appPath: "/abs/path/to/MyApp.app"` (optional `terminateExisting: true`).
- **CLI / SSH:**
  ```bash
  debagr deploy --app /abs/path/to/MyApp.app --terminate-existing
  ```
For install-only without foreground launch (works even if you do not want to wake/unlock for launch):
- **MCP:** `debagr_deploy_app` with `launch: false` (or `debagr_install_app`).
- **CLI:** `debagr deploy --app /abs/path/to/MyApp.app --no-launch`

### 4. Recover Cleanly from Structured Error States
Never blindly loop or rebuild when Debagr returns a structured error. Inspect `error.code`, `error.partialSuccess`, and `error.nextSteps`:

| Error Code | Exit Code | Meaning | Recovery Action |
|---|---|---|---|
| `DEVICE_LOCKED` | `3` | Device screen locked before launch | Ask user to unlock phone, run `debagr ready`, then retry `launch` or `deploy` (or pass `--no-launch`). |
| `INSTALL_SUCCEEDED_LAUNCH_FAILED` | `4` | `installed: true`, `verifiedInstalled: true`, `launched: false` | **Do not rebuild or reinstall.** Ask user to unlock device / trust developer profile in iOS Settings, then run `debagr launch --bundle-id <id>` (MCP `debagr_launch_app`). |
| `OPERATION_TIMEOUT_UNCERTAIN` | `5` | Command timed out; post-timeout check ran | Inspect `partialSuccess` and run `debagr ready` + `debagr apps --bundle-id <id>` (MCP `debagr_list_apps`) before deciding whether to `launch` or retry. |
| `APP_BUNDLE_INVALID` | `1` | Simulator/macOS/corrupt `.app` passed | Rebuild with `-sdk iphoneos` on the Builder Mac. |
| `APP_NOT_SIGNED` | `1` | Missing or invalid code signature | Fix Xcode signing/provisioning on the Builder Mac; Debagr never signs apps. |
| `DEVELOPER_MODE_DISABLED` | `3` | iOS Developer Mode off | Ask user to enable Settings > Privacy & Security > Developer Mode and restart the device. |

### 5. Diagnostics
When troubleshooting or escalating to the user, always collect redacted diagnostics (never leak raw pairing metadata):
- **MCP:** `debagr_diagnose` (`redact: true`)
- **CLI:** `debagr doctor`
