# AI-first deployment milestone

Install Debagr on the paired Build Server. The human configures the iPhone once
in the menu bar; an agent uses the same app's CLI locally or through existing
SSH access. No new network API, cloud account, or companion iPhone app is needed.

## Human setup

1. Install Xcode, pair the device over USB, grant trust, and enable Developer Mode.
2. Connect both endpoints to Tailscale. Keep the iPhone on Wi-Fi and unlocked.
3. Open Debagr and choose **Configure Remote iPhone…**. Select the Apple device,
   its real local Bonjour service, and the corresponding Tailscale device.
   Use **Import Private Profile…** to reuse a captured profile while remote.
4. Leave Debagr running and optionally enable **Launch at Login**. It restores
   the enabled configuration at the next login. **Disconnect Remote Device**
   stops Debagr's relay; it does not disable native USB/Wi-Fi Apple connectivity.
5. Use **Show AI Deployment Skill…** to locate
   `Contents/Resources/Skills/debagr-deploy/SKILL.md`. Copy the enclosing
   `debagr-deploy` folder into the skill directory of the AI client on the caller.
   The skill contains instructions only; private device configuration stays on
   the Build Server. Supply the agent with the Build Server's existing SSH alias
   and project build instructions.

## Agent commands

The installed binary is `/Applications/Debagr.app/Contents/MacOS/Debagr`.
Run it as the same user that owns Apple's pairing and runs the menu-bar app.

```sh
Debagr --devices --json
Debagr --status --device DEVICE_UDID --timeout 30 --json
Debagr --deploy-app /absolute/device/App.app --device DEVICE_UDID --launch --json
Debagr --diagnose --device DEVICE_UDID --json
```

Each command emits exactly one JSON object on stdout. Human-readable diagnostics
belong on stderr. Inventory states are not readiness assertions. `--status`
verifies Apple's trusted connection and unlocked state; its wait is bounded by
`--timeout` (1–60 seconds). Installation and launch have separate 120-second and
30-second deadlines and are never retried automatically.

```json
{"schemaVersion":1,"ok":true,"operation":"deploy","result":{"state":"installed_and_launched","deviceIdentifier":"DEVICE_UDID","bundleIdentifier":"com.example.app","installed":true,"launched":true}}
```

Failure responses contain `error.code`, `message`, and `recovery`.
`installationConfirmed: false` means installation is not established, not that
an interrupted installation necessarily had no effect. `launch_failed` carries
`installed: true` and the bundle ID: retry launch only. A successful launch is
an OS-confirmed launch, not evidence that the app's UI behaves correctly.

| Exit | Meaning |
| --- | --- |
| 0 | Requested operation confirmed |
| 2 | Device or network needs human attention |
| 64 | Invalid arguments |
| 65 | Invalid app artifact |
| 1 | Command, installation, or launch failure |

For CLI setup, use `--configure --device DEVICE_UDID --peer iphone-peer
--bonjour-host My-iPhone.local --json`. An existing private profile can instead
be imported with `--profile /private/path/device-profile.json`. Captured identity
and selected peer must belong to the same phone. Configuration does not prove
that the selected Apple device is reachable; check `--status` afterward.

## Runtime and limits

The menu-bar app polls readiness every 10 seconds on a serial work queue.
When an Apple connection is already usable, it does not start a proxy. Otherwise
it binds relays to the active Wi-Fi/Ethernet IPv4 address, honors the saved peer,
and restarts its own relay when the Build Server's address changes. File locking
prevents two new Debagr relays from owning the same control port.

A log watcher opens observed tunnel ports and pre-opens a small neighboring
allocation window. That window is persisted for later startups. The first
attempt outside the saved range can fail; subsequent bounded status attempts
can use the learned relays. This is heuristic calibration, not a guarantee of
Apple's port allocator. Private profiles can preserve a known verified range.

This milestone manages one remote device. It does not install Tailscale or change
Apple trust, signing credentials, SSH configuration, or unrelated Apple daemons.
The app must be running in the paired user's logged-in session. A standalone
headless daemon, simultaneous remote phones sharing the same control port,
cellular operation, and an MCP server are outside this milestone.
