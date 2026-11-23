# Debagr Architecture

## 1. Single Binary, Three Execution Modes

`Debagr.app/Contents/MacOS/Debagr` routes execution cleanly in `Sources/DebagrApp/main.swift`:
- **GUI Mode** (no CLI subcommands or `--gui`, stripping macOS `-psn_*` launch flags): starts `DebagrGUIApp` (`MenuBarExtra` + SwiftUI settings window).
- **CLI Mode** (`debagr <subcommand>`): never initializes AppKit; emits versioned JSON envelopes (`schemaVersion: "1.0"`) to `stdout` and exits with deterministic status codes (`0`–`5`).
- **MCP Mode** (`debagr mcp`): runs a local stdio JSON-RPC 2.0 server (`MCPStdioServer`) without initializing AppKit or binding any TCP port.

## 2. Module Dependency Graph

```text
DebagrCore (models, 0600/0700 storage, redactor, private-IP validation, devicectl, bundle validator, DeploymentCoordinator)
   ▲
   ├── DebagrBridge (dns-sd browse/proxy, NWConnection probe, NWPath + sleep/wake monitor, WirelessBridgeSupervisor)
   │      ▲
   │      ├── DebagrCLI (argument parser, JSON envelopes, CLIRunner)
   │      ├── DebagrMCP (JSON-RPC 2.0 stdio transport, 7-tool MCPToolRegistry)
   │      └── DebagrExperimental (Cable Service Bridge over usbmuxd + CryptoKit USB/IP pairing)
   │             ▲
   └─────────────┴── DebagrApp (multi-mode entrypoint, MenuBarExtra, SwiftUI views, SMAppService)
```

## 3. Wireless Bridge State Machine (`WirelessBridgeSupervisor`)

1. **`unconfigured`**: No managed device saved; any active `dns-sd -P` proxy is stopped.
2. **`nativeLocalStandby`**: `yieldWhenNativelyLocal` is enabled and CoreDevice shows the managed device is connected natively via USB (`wired`) or already has an active native local Wi-Fi tunnel when no proxy is running. Debagr steps aside cleanly.
3. **`bridgingActive`**: Device is absent locally, VPN TCP probe (`<vpnIP>:<lockdownPort>`, default `62078`) succeeds, and `/usr/bin/dns-sd -P` advertises the saved `_apple-mobdev2._tcp` identity pointing to the VPN IP.
4. **`deviceOffline` / `vpnUnavailable`**: Probe fails or `NWPathMonitor` reports unsatisfied path; proxy is torn down cleanly.
5. **Sleep/Wake Recovery**: On `NSWorkspace.willSleepNotification`, Debagr tears down the active proxy so stale mDNS records do not linger. On `didWakeNotification` or network restoration, it triggers immediate reconciliation (and tracks Tailscale/Headscale peer IP rotations automatically).

## 4. Dual-Schema `devicectl` Compatibility

`DeviceCtlModels` parses both:
- Modern `devicectl` `properties.hardware` / `properties.connection` / `properties.state` / `properties.software` (Xcode 27+, `devicectl 651+`).
- Legacy `hardwareProperties` / `connectionProperties` / `deviceProperties` (Xcode 15/16/26).

All invocations write structured JSON to a unique temporary file via `--json-output <temp-file>` so progress lines or deprecation notices on stderr never corrupt JSON parsing.

## 5. Deployment & Partial-Success Recovery

`DeploymentCoordinator.deploy`:
1. Validates `.app` directory, `Info.plist`, `DTPlatformName == iphoneos` (rejecting `iphonesimulator` and `macosx`), and strict `codesign --verify --deep --strict`.
2. Ensures bridge readiness, checks Developer Mode, and checks lock state before install when `launchAfterInstall == true` (failing fast with `DEVICE_LOCKED`).
3. Installs via `devicectl device install app` and captures `launchServicesIdentifier`.
4. Verifies presence via `devicectl device info apps --bundle-id <id>`.
5. Launches via `devicectl device process launch`. If launch fails after verified installation (e.g., phone locked mid-install or untrusted profile), returns `INSTALL_SUCCEEDED_LAUNCH_FAILED` (`exit 4`) with `partialSuccess.installed = true, verifiedInstalled = true, launched = false` so callers recover directly with `launch`.
6. If install or launch times out, runs a post-timeout `listApps` probe and returns `OPERATION_TIMEOUT_UNCERTAIN` (`exit 5`) with verified state.
