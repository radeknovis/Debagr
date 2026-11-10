# Connection design restoration

The restoration starts from audit PR #15, merged as `2c9d975`, rather than replacing
the audited source with the older app. The design source is `a84b122` on
`t3/streamlined-device-pairing`, plus its uncommitted Agent tools/menu refinements.
The older `t3-c43fb51c` worktree was compared for provenance; its consolidated
Builder/Client work is already in `a84b122`. Abandoned alternative layouts were
not added as additional screens.

Before integration, both design worktrees were copied under
`.build/design-restoration/20261110-115905/`, with binary patches, base commits,
changed/untracked files and SHA-256 manifests. Their source files remain untouched.
The previous local candidate bundle was archived before packaging a new build.

## Integration boundaries

- Pairing support is a separate commit from the shared interface and menu.
- Pair and Connect remain separate actions. Mac linking does not establish Apple trust.
- Existing pairing uses the audited relay lifecycle, native DNS-SD, timeout/error
  handling, private atomic files, recovery commands and deferred quit handling.
- Review requires confirmation that device, service and VPN endpoint describe the
  same physical device. Changing device, provider, service or address invalidates
  that confirmation. Saved profiles remain usable when the phone is remote.
- The latest Agent tools screen teaches skill installation and natural requests.
  Generated deployment prompts and per-device command copying remain removed.
- UI state uses the main actor; network protocol state stays on serial queues.
  The existing concurrency baseline is retained without adding warnings.
- Version, preview licence, signing gates and pinned CI toolchain remain unchanged.

## Validation

Local checks on 10 November 2026:

- 139 Swift tests pass with no standard-build warnings, including both source suites,
  identity confirmation, strict private-helper arguments, single-root navigation,
  USB handoff gating, cancellation and asynchronous quit cleanup.
- Eight native fixture renders cover both pairing paths in light/dark appearances
  at 980×860 and 880×740. Live AppKit inspection verified Connection, Agent tools,
  Preferences, keyboard progression and saved-profile reuse. It caught a USB/IP
  accessibility label that incorrectly mentioned VirtualHere; the corrected route
  description has regression coverage.
- A clean complete-concurrency build passes the existing baseline without adding
  diagnostics. The baseline file is unchanged. The checker now removes interleaved
  SwiftBuild progress fragments before matching diagnostic paths, with a regression
  test that retains the original warning identity.
- Release-mode 0.3.0 build 4 is Developer ID signed, including its USB capability
  probe. Bundle verification, packaged CLI/MCP smoke checks, deferred SIGTERM quit,
  nine mocked release-safety scenarios, documentation links and both plugin ZIPs pass.
- Both original design worktrees still match their saved SHA-256 manifests.
- The final signed SmartSaver SSStaging artifact has a valid signature, current
  provisioning and the intended iPhone in its profile. The restored Debagr CLI
  initially reported readiness, then stopped deployment with `device_locked` before
  confirming installation. After the user unlocked the phone, readiness passed and
  installation plus OS-confirmed launch succeeded for `com.monefit.smartsaver.staging`,
  with `ok: true`, `installed: true` and `launched: true`. The existing paused relay
  setting was retained; this verifies the restored CLI against a real device, not
  new USB pairing or a fresh relay-topology acceptance run.

The signed app is a local candidate; build 4 was not notarized or publicly released.
The earlier build 3 DMG and installed app were retained. The previous running
candidate was stopped before launching the new one. No saved configuration, Apple
trust, login preference or system security setting was changed during validation.
Fixture renders and model tests do not establish new Apple trust or acceptance of
either USB backend. Physical USB/IP and VirtualHere workflows, iPad, older OS,
clean-Mac and recovery-matrix acceptance remain outstanding. The earlier remote
iPhone install/launch result applies to the audited candidate recorded in
[DIRECT_DEVICE.md](DIRECT_DEVICE.md), not automatically to this restoration.
