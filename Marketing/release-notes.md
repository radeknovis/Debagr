# Debagr 0.3.0 technical preview — release candidate

This source branch fixes readiness timeouts, structured Apple errors, relay
resource leaks and backpressure, and Settings responsiveness. It adds native
Bonjour registration, explicit setup confirmation, launch-only and installed-app
commands, deeper diagnostics and an optional local stdio MCP interface.

The app is free for personal and internal evaluation, with no redistribution.
Read the included Preview-Licence.txt and the public licence page. Paid terms
remain a separate draft.

Local verification: 64 Swift tests, including TCP/UDP forwarding and native
Bonjour, strict lint, packaged CLI/MCP smoke checks, bundle verification and
reproducible plugin archives. A reviewed baseline exposes existing strict
concurrency warnings and prevents new ones; Swift 6 migration is incomplete.

Fresh remote iPhone install and OS-confirmed launch passed with SmartSaver SSStaging,
with separate Wi-Fi networks and USB disconnected as confirmed by the owner.
iPad, sleep/wake, revoked trust, other VPNs,
clean-Mac installation, older-macOS transport and Homebrew upgrade acceptance
remain pending. Early device-state and duplicate-instance issues were resolved before the successful deployment.
Do not treat local tests as hardware acceptance. Cellular-only operation is
unsupported. One managed remote device, Apple silicon, supported remote macOS
26+ and current Xcode; device Wi-Fi, private VPN and Apple trust are required.

Release assets and notarization status must be verified before publishing this
candidate. Source-code ZIPs are not the app. Keep published 0.2.0 available for
rollback and do not update its cask checksum to an unverified candidate.
