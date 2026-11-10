# Audit fix status

Source candidate: 0.3.0. Work is committed in focused batches on
`t3/project-improvements`; the published app and public site still serve 0.2.0.
A remote iPhone install and OS-confirmed launch were verified; no public release was performed.

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

- 64 Swift tests passed, with zero compile warnings or errors.
- TCP and UDP tests send data through real local relay sockets; these do not
  establish CoreDevice or remote-device acceptance. A native Bonjour integration
  test verifies the advertised service is visible and registration stops.
- Swift format strict lint and git diff whitespace checks passed.
- Packaged debug app built, signature/bundle verified, JSON CLI smoke checks passed.
- Preview licence bundled and compared byte-for-byte with the public-site text.
- Release script: nine mocked Apple-tool scenarios passed. Workflow input gates
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
- Tests grouped by responsibility. Pinned action commits, hosted Xcode 26.6 (17F113),
  checksum-verified xcsift 1.7.4 and a strict-concurrency regression gate.
- Active user docs separated from development and historical distribution notes;
  plugin archives omit maintainer instructions. Public setup labels, local links
  and website assets are checked in CI. Primary site action leads to setup.
- Source version 0.3.0 is checked across VERSION, app template and plugin manifests.
  Published download links stay on 0.2.0 until release acceptance.

## Additional verification

- Native Settings was inspected visually. Paste/select-all, invalid-address
  feedback, valid-address recovery and selection reset passed. The
  computer-use observer reopens a closed accessory window, so Cmd-W closure was
  not independently confirmed by that observer.
- Pinned CI tool installer rehearsed locally with verified archive SHA-256 and
  exact Xcode selection. Concurrency gate rejects new warnings and ignores line shifts.
- A clean complete-concurrency build recorded 111 diagnostic emissions / 58
  unique warnings. The reviewed baseline blocks new diagnostics; this is not a
  completed Swift 6 migration and existing warnings were not suppressed.
- Early iPhone probes returned device_locked / CoreDevice 4016. A matching orphaned
  legacy advertisement was stopped after checking its owner, service identity,
  hostname and port. Two app copies were also found running. The installed copy
  was stopped and the candidate was verified as the only control-port owner.
  Readiness then passed; no Apple daemons, trust or signing credentials were reset.

## Signed candidate evidence

A local 0.3.0 build 2 candidate was built with the available Developer ID and
Keychain notarization profile. Both app and DMG were accepted by Apple's notary
service, stapled, validated and accepted by Gatekeeper as Notarized Developer ID.
The versioned DMG and SHA-256 are in `dist/`; no public binary was uploaded.
This establishes distribution integrity, not device deployment behavior.

## Remote iPhone acceptance

Using the signed 0.3.0 build 2 candidate as relay owner and CLI, SmartSaver
SSStaging was built from the separate checkout's clean main branch. Its device
build signature was verified and its provisioning profile included the selected
Radek's iPhone 16 Pro. The owner confirmed different Wi-Fi networks and no USB.
Readiness returned ready; deployment returned ok, the expected bundle identifier,
installed true and launched true. This is a fresh remote iPhone installation and
OS-confirmed launch, not visual verification of SmartSaver's screen behavior.
No SmartSaver source changes were made. Private result JSON stays under .build/.

Real devicectl errors use typed userInfo.NSLocalizedDescription.string values;
the CLI now preserves those descriptions, with a captured-shape regression test.
Native Bonjour tests also exercise the all-interface, non-trailing-dot hostname
shape used in production.

## Remaining external acceptance and delivery

- Remote iPad installation and launch remain unverified; the iPhone acceptance above is complete.
- Sleep/wake, trust revocation, alternative VPNs, older macOS and clean-Mac /
  Homebrew-upgrade acceptance require an appropriate controlled test environment.
  The advertised remote support floor remains unchanged.
- Public site, tap/catalogue and binary publication await release acceptance.
  Plugin archives contain public-safe metadata and canonical instructions but
  public marketplace-source publication has not been performed.
- Full Swift 6 migration remains tracked by .ci/concurrency-baseline.json.

## Deferred-quit regression

The remote test's cleanup exposed a real deferred-quit issue: the process had
released its relay resources but remained inside AppKit's nested termination
loop. A process sample showed terminate running inside the main dispatch queue.
The reply is now scheduled through the main run loop, which can deliver it in
that nested loop. The signal entry point uses the run loop as well.
`scripts/check-menu-bar-shutdown.py` reproduced the old bundle's failure (no exit
within eight seconds after SIGTERM), then passed with the rebuilt bundle. It
launches and signals only its own child process and is included in CI.

Hosted CI initially rejected the local Xcode 27.2 pin because that version is not
on the runner. Its exact macos-26-arm64/20261102.0473 inventory was inspected;
the hosted pin is now Xcode 26.6 (17F113). Local signing and device acceptance
retain their separately recorded Xcode 27.2 (27B48) evidence.
