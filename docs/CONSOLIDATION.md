# Debagr connection consolidation

This worktree brings together three pieces of work without changing the published
0.2.0 release or the source worktrees.

| Source | Incorporated result |
| --- | --- |
| Public launch: <t3-thread://v2/c44be434-b944-4980-839b-9296d0114a88/363292d3-20fa-4f0c-afb6-8c6ab343fec2> | Launch commit `36aeec4` is already included through merge `519fcd8`: public binary/tap/site, private source, GitHub contact routes, deferred funding, and known acceptance gaps |
| RemotePairingd / USB-IP: <t3-thread://v2/c44be434-b944-4980-839b-9296d0114a88/9737cbd3-c5a9-4f98-bf38-936f0d9abfcd> | Native clickable Builder/Client diagram, device discovery, role synchronization and trust, root approval and cancellation, USB/IP process ownership, capability probe, SIP annotation, and regression tests |
| This pairing worktree | Illustrated existing-pairing flow, saved-profile preservation, readiness/recovery, VirtualHere-over-SSH pairing and wireless handoff, cleanup/retry tests |

## Resulting flow

1. New setups and Clients open **Initial device pairing**. Select computers by
   clicking the Builder/Client cards. Device lists update without capturing USB.
2. Use the optional USB/IP setup to establish or refresh Apple trust. Start on
   the Client and then the Builder, approve Trust on the phone when requested,
   check the selected device, and explicitly stop both temporary connections.
3. On the Builder, choose **Set up wireless deployment…**. Existing pairing needs
   no USB session. Select the device, VPN address and matching service/profile,
   review, save, and check connectivity. USB/IP profile transfer remains manual
   when the Builder cannot discover the phone locally.
4. **Use VirtualHere instead…** selects the separate SSH-based USB implementation,
   including remote profile capture and release before the wireless check. Its
   external software and server-license prerequisites remain explicit.

The diagrams use **Builder** and **Client** consistently. Mac linking, Apple trust,
USB process state, device readiness, installation, and launch remain distinct.
Handoff controls reject an active USB/IP session; the VirtualHere session must
end before returning to USB/IP. No Mac pairing, device profile, USB process,
installed app, or system security setting was changed while integrating code.

## Evidence boundaries

The launch thread finished publication of 0.2.0; it did not ship these additions.
The USB/IP thread records wired CoreDevice readiness followed by an unplugged
relay installation and launch. The phone already trusted its Builder; the
successful result does not prove brand-new pairing or the final GUI workflow.
See [the recorded experiment](DIRECT_DEVICE.md#usbip-refresh-and-relay-deployment-6-november-2026).

Validation on 7 November 2026 passed:

- 104 Swift tests, including both source suites and cross-workflow handoff gating.
- Strict Swift formatting and diff whitespace checks.
- Native light/dark Builder/Client captures, plus VirtualHere and wireless review screens.
- Release-mode packaging and strict signatures for the app and bundled USB controller probe.
- Four packaged agent CLI cases, the unprivileged probe gate, USB/IP dispatch,
  and the private service helper's JSON schema.
- Eight mocked release safety scenarios and both agent plugin packages.

These checks did not start a privileged USB session.
Physical acceptance remains required for the combined app, both USB backends,
and the final wireless handoff. The generated local app is ad-hoc signed and
must pass the normal release process before public distribution.

Before the integration, both uncommitted trees were copied under `.build/consolidation-*`
with content hashes and patches. The source worktrees remain unchanged. No new
release, commit, PR, public-site change, or machine installation is part of this consolidation.

## Interface restoration, 9 November 2026

The initial-pairing entry point again uses the polished connection shell, including
the sidebar, heading, and custom phone/Client/Builder diagram. The live Mac pickers,
USB/IP controls, SIP annotation, and native approval sheets remain in the same
window. This replaces the plain standalone window introduced during consolidation.
105 tests, strict lint, release packaging and bundle verification pass.
The MacBook Air update is pending because its Tailscale node is offline.

The initial and existing pairing paths now share the same sidebar, choice cards,
diagram and progress components. Initial pairing shows Macs, Device trust and
Wireless stages based on confirmed roles and device checks. The full padded
choice-card area participates in hit testing; decorative borders do not.

Switching between initial pairing and existing pairing now replaces content in
one shared connection window. Both controllers retain their own content and
state; native sheets use that same window. The 106-test suite includes a
round-trip navigation check that asserts unchanged window identity.

Layout stabilization aligns sidebar and content widths across both paths, reserves
a common diagram height, and keeps the path cards visible through later steps.
SwiftUI content sizing no longer controls the shared window. Navigation tests
assert that switching paths preserves the user-sized window frame.

## Shared screen cleanup

Both paths now render inside the same persistent `DeviceSetupView`. The shared
`DeviceConnectionView` owns the header, path cards, diagram, progress content,
and single scroll area. `ConnectionActionBar` owns the footer layout for both.
Navigation changes model state and never replaces the root view or reparents windows.

`InitialPairingCoordinator` supplies `InitialPairingPresentation`: native Mac/device
controls, progress, status, and identified actions. It retains USB/IP discovery,
role authorization, approval and cancellation, and device checks. SwiftUI renders
its actions in the same footer as the existing-pairing actions. Native sheets
use the connection window. The separate `InitialPairingShell`, fixed overlay
coordinates, duplicate sidebar, and screen-swapping methods were removed.

Regression coverage switches paths while asserting the same root view and window
frame, invokes the shared footer's missing-device action, and verifies a running
Builder's Check Device and Stop actions without launching a real USB backend.
