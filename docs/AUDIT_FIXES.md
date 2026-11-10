# Audit fix status

Source candidate: 0.3.0. Work is committed in focused batches on
`t3/project-improvements`; the published app and public site still serve 0.2.0.
No real-device install or public release was performed during the source fixes.

## Implemented

- Owner-selected free personal/internal evaluation licence, no redistribution;
  full text on the public site and bundled in the app, with paid draft terms separate.

- Valid minimum Apple timeouts with independent outer readiness deadlines;
  fail fast on Apple's explicit unknown-device error.
- Structured Apple error code/domain/message, deployment timeout with unknown
  outcome, runtime device selection errors, consistent text/JSON exit codes,
  duplicate-option rejection, explicit deployment timeout rejection, --version,
  complete help, and simulator/macOS artifact rejection.
- TCP waiting deadline, keepalive, backpressure and cancellation handling;
  UDP idle expiry, datagram preservation and per-listener flow cap.
- Serial listener/connection ownership, health propagation and managed refresh
  rebuilds; bounded learned-port windows and increased descriptor allowance;
  self-destination rejection and parsed source-address policy.
- Bounded Tailscale subprocess, directly testable peer selection, current Apple
  device-name schema, split-UTF8 line buffering, watcher retry on exit and
  failed-port forgetting, native in-process Bonjour registration and health reporting.
- Private files created with mode 0600 before writing and atomically renamed;
  default private-directory permissions repaired on write.
- Settings keyboard shortcuts, reliable connect refresh, connection-state icon,
  actionable managed-error titles, saved-device summary/removal/profile reuse,
  preserved selections, discovery feedback, VPN name matching and sorting,
  improved selected text contrast and accessibility selection, saved-page status,
  menu refresh/wake handling, managed diagnostics and public plugin links.
- Explicit workflow version/tag/build gates, CI permissions/concurrency/deadlines,
  pipefail shell, archived app permissions, cross-artifact version checks,
  reproducible plugin ZIPs, optional packaging formatter, signing-file ignores,
  and remote environment CLI-path/ping handling.
- Public-site setup guide, legal-page icon sizing, corrected cellular language
  and architecture decision, scrubbed employer bundle identifier, artifact
  transfer/deploy deadlines/readiness recheck and documented failure codes.

## Verification

- 62 Swift tests passed, with zero compile warnings or errors.
- TCP and UDP tests send data through real local relay sockets; these do not
  establish CoreDevice or remote-device acceptance. A native Bonjour integration
  test verifies the advertised service is visible and registration stops.
- Swift format strict lint and git diff whitespace checks passed.
- Packaged debug app built, signature/bundle verified, JSON CLI smoke checks passed.
- Preview licence bundled and compared byte-for-byte with the public-site text.
- Release script: eight mocked Apple-tool scenarios passed. Workflow input gates
  checked with valid version and invalid version, build and ref inputs.
- Both plugin archives verified and byte-reproducibility checked.

## Additional completed work

- Shared TCP/UDP listener lifecycle and one persistent network-path monitor.
- Off-main-thread tool discovery and diagnostics, refreshed System Check,
  owned-command cancellation and asynchronous quit cleanup.
- Inline invalid-address feedback, explicit physical-device confirmation,
  correctly quoted deploy commands using the actual executable path and copy feedback.
- Allowed-option matrix, launch-only and installed-app CLI commands, detailed
  configuration/network/inventory/VPN diagnostics and injected-clock wait tests.
- Optional local stdio MCP tools, protocol/argument tests and packaged handshake
  plus read-only tool-call validation. No network endpoint is exposed.
- Tests grouped by responsibility. Pinned action commits, Xcode 27.2 (27B48),
  checksum-verified xcsift 1.7.4 and a strict-concurrency regression gate.
- Active user docs separated from development and historical distribution notes;
  plugin archives omit maintainer instructions. Public setup labels, local links
  and website assets are checked in CI. Primary site action leads to setup.
- Source version 0.3.0 is checked across VERSION, app template and plugin manifests.
  Published download links stay on 0.2.0 until release acceptance.

## Additional verification

- Native Settings was inspected visually. Paste/select-all, invalid-address
  feedback, valid-address recovery, selection reset and Cmd-Q passed. The
  computer-use observer reopens a closed accessory window, so Cmd-W closure was
  not independently confirmed by that observer.
- Pinned CI tool installer rehearsed locally with verified archive SHA-256 and
  exact Xcode selection. Concurrency gate rejects new warnings and ignores line shifts.
- A clean complete-concurrency build recorded 111 diagnostic emissions / 58
  unique warnings. The reviewed baseline blocks new diagnostics; this is not a
  completed Swift 6 migration and existing warnings were not suppressed.
- The configured physical iPhone readiness probe returned device_locked (exit 2).
  The device panel exposes simulators only; neither proves remote hardware acceptance.

## Remaining external acceptance and delivery

- A signed device artifact and the intended unlocked device are needed for real
  remote iPhone/iPad installation and launch. The owner has been asked to select them.
- Sleep/wake, trust revocation, alternative VPNs, older macOS and clean-Mac /
  Homebrew-upgrade acceptance require an appropriate controlled test environment.
  The advertised remote support floor remains unchanged.
- Public site, tap/catalogue and binary publication await release acceptance.
  Plugin archives contain public-safe metadata and canonical instructions but
  public marketplace-source publication has not been performed.
- Full Swift 6 migration remains tracked by .ci/concurrency-baseline.json.
