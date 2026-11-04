# Debagr launch research

> Historical pricing research. The 22 October launch kit uses an unpriced
> technical preview with optional sponsorship drafts. No checkout, subscription
> price, or funding channel is active. See [shipping status](SHIP_STATUS.md).

_Verified 22 September 2026. Prices and platform rules can change; recheck linked first-party pages before launch._

## Decision

Do **not** sell transparent remote Xcode access. Debagr now targets the narrower
supported workflow: a paired Build Server installs and launches signed apps
when invoked locally or through the user's SSH access. Ship a free, invite-only
technical preview until repeatable iPhone and iPad deployments pass locally and
through SSH. At that point, sell a notarized Developer ID build directly for
**$99 per user/year with a 14-day trial**, using Lemon Squeezy for checkout and
licence keys.

This is a recommendation, not a verified market fact. It is the smallest channel and pricing model consistent with the product's present architecture and maintenance risk.

Implementation update: the repository now includes a branded menu-bar build,
`devicectl` plus Bonjour inventory, first-run/support UX, policy drafts, a static
launch site, CI, credential-driven signing/notarization scripts, and an explicit
`devicectl` install-and-launch command. SSH remains the caller authentication
boundary. Hardware-matrix, updater, commerce, and account-bound release gates
remain open.

## Verified facts

### What exists in this repository

- The menu-bar shell merges physical iPhone/iPad inventory from Apple `devicectl` with local Bonjour services, displays friendly names and availability, refreshes discovery, provides redacted diagnostics and first-run guidance, and supports Launch at Login ([`MenuBarApplication.swift`](../Sources/Debagr/MenuBarApplication.swift), [`CoreDeviceInventory.swift`](../Sources/Debagr/CoreDeviceInventory.swift)).
- The deployment command validates a signed `.app`, preflights an explicit
  paired UDID, installs with `devicectl`, confirms the bundle identifier from
  Apple's result, and optionally launches it. The legacy relay remains research
  code and is not part of the product promise ([`DeviceDeployer.swift`](../Sources/Debagr/DeviceDeployer.swift), [`README.md`](../README.md#build-server-deployment)).
- Local packaging defaults to an ad-hoc Hardened Runtime signature; the release script and workflow add Developer ID signing, DMG creation, notarisation, stapling, Gatekeeper verification, and a checksum once publisher credentials are supplied ([`build-macos-app.sh`](../scripts/build-macos-app.sh), [`release-macos-app.sh`](../scripts/release-macos-app.sh)). A signed update channel remains absent.
- The app declares local-network and `_remotepairing._tcp` usage, but its metadata says macOS 13 while the README says exact endpoint binding requires macOS 26; the supported-OS promise must be made consistent before sale ([`Info.plist`](../Packaging/Debagr.app/Contents/Info.plist), [`README.md`](../README.md#build)).
- There is no customer account, live billing/licence enforcement, or updater. Privacy, EULA, support, security, compatibility, and release documents now exist as explicit pre-publication drafts; owner/legal details remain incomplete.

### Apple distribution and platform boundary

- Apple documents wireless pairing and post-cable Xcode use when the Target Device and Mac are on the same Bonjour-compatible network. Its public Device Hub documentation does **not** establish cross-Mac pairing or RemotePairing over a VPN/tailnet as a supported transport ([Apple: Managing devices in Device Hub](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac)). Therefore, any cross-Mac claim is Debagr's tested compatibility claim, not an Apple-supported capability.
- Direct distribution requires a Developer ID Application signature, Hardened Runtime, a secure timestamp, notarisation, and testing the packaged download; Apple recommends stapling the ticket so Gatekeeper can validate it offline ([Apple: notarisation requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Apple: packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), [Apple: Developer ID](https://developer.apple.com/developer-id/)). Apple Developer Program membership is currently **US$99/year** ([Apple membership details](https://developer.apple.com/programs/whats-included/)).
- Mac App Store apps must enable App Sandbox. Unlocking app features there normally requires Apple In-App Purchase rather than external licence keys ([Apple: App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox), [App Review Guideline 3.1.1](https://developer.apple.com/app-store/review/guidelines/uk/#in-app-purchase)). Direct distribution is therefore the lower-risk channel for the current process-spawning, local-network tool.
- macOS local-network access requires a clear usage description and declared Bonjour service types; users can deny or later revoke access ([Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)). Onboarding and diagnostics must handle that state rather than report generic discovery failure.

### Optional Tailscale transport

- Tailscale ships three macOS variants. It recommends the Standalone variant, while the CLI path/packaging differs between Standalone, Mac App Store, and open-source installs ([Tailscale: macOS variants](https://tailscale.com/docs/concepts/macos-variants), [Tailscale CLI](https://tailscale.com/docs/reference/tailscale-cli?tab=macos)). Debagr detects it only to report optional remote-SSH readiness; deployments do not call its API.
- Tailscale's current Personal plan is free but described as non-commercial. Standard is **$8/user/month**, so professional customers may have a separate Tailscale bill ([Tailscale pricing](https://tailscale.com/pricing)). Customers who choose it supply their own compliant account; Debagr does not include or resell Tailscale service ([Tailscale Terms, section 2.3](https://tailscale.com/terms)).
- Tailscale is a registered trademark and offers a partnership/contact route for co-branding ([Tailscale press assets](https://tailscale.com/press), [Tailscale partnerships](https://tailscale.com/partnerships)). Until permission is obtained, use plain-text nominative wording such as “Requires Tailscale,” no Tailscale logo, and an explicit “not affiliated with or endorsed by Tailscale” notice. Legal review is still required.

### Adjacent products and current public prices

These are alternatives, not exact substitutes:

| Product | First-party offer | Relevance |
| --- | --- | --- |
| [FlexiHub](https://www.flexihub.com/remote-usb-access/) | General remote USB access, starting at **$39/month** | Broad hardware forwarding; not an Xcode-native Target Device workflow. |
| [USB Network Gate](https://www.eltima.com/products/usb-over-ethernet/free-version/) | **$159.95** single commercial licence, up to 10 shared USB devices | A perpetual remote-USB anchor for price comparison. |
| [BrowserStack](https://www.browserstack.com/pricing?cycle=annual&product=testing-toolkit) | Desktop & Mobile automation from **$175/month** billed annually | Cloud real-device testing, not use of the customer's already-paired device in local Xcode. |

## Positioning inference

Own the narrow category: **a private deployment endpoint for the physical Apple devices already paired to your build Mac**.

Target solo developers and small Apple-platform teams that have a Target Device connected to an always-on Mac elsewhere. Do not position Debagr as a VPN, device cloud, USB-over-IP product, Apple pairing replacement, or enterprise fleet manager.

Recommended launch line, only after the hardware gate passes:

> Pair once with your build Mac, then install and launch signed builds from any authorized SSH caller.

Required qualifier near every purchase CTA:

> Requires a Mac with Xcode, a locally paired developer-enabled iPhone or iPad,
> and a signed device build on that Mac. Remote invocation requires the user's
> own SSH access; Tailscale is optional.

Never claim “works anywhere,” “zero configuration,” “Apple-supported,” or “secure” without a defined test matrix and an authenticated connection design.

## Pricing recommendation

- **Technical preview:** free, invite-only, no paid preorders. The purpose is to measure successful deployments, locked/offline-device recovery, and support load.
- **General availability:** one plan, **$99/user/year**, all Macs and Target Devices owned by that user, 14-day full trial, 30-day refund policy. No monthly, lifetime, device-count, or team tiers at launch.
- Annual pricing funds compatibility work against macOS, Xcode, `devicectl`, iOS, and iPadOS.
- Use **Lemon Squeezy**, not two billing systems. Both Lemon Squeezy and Paddle currently list **5% + 50¢** per transaction and act as merchant of record ([Lemon Squeezy pricing](https://www.lemonsqueezy.com/pricing), [Paddle pricing](https://www.paddle.com/pricing)). Lemon Squeezy additionally exposes built-in software licence keys, activation limits, and subscription-linked validity, and supports Czech bank payouts ([licence-key docs](https://docs.lemonsqueezy.com/help/licensing/generating-license-keys), [supported countries](https://docs.lemonsqueezy.com/help/getting-started/supported-countries)). Revisit Paddle only when enterprise invoicing or procurement becomes a demonstrated need.

## Minimum paid-launch gate

All items are release blockers unless explicitly marked later:

1. **Core outcome:** one signed device `.app` installs and launches on an explicit paired iPhone and iPad when invoked locally and through SSH.
2. **Reliability:** documented passing matrix for supported macOS/Xcode/iOS combinations; recovery after a locked/offline device, sleep, app restart, Mac restart, and revoked pairing; deterministic failure reporting; two Target Devices tested.
3. **Security:** no deployment listener, explicit artifact and UDID, argument-array process execution, documented SSH least privilege and revocation, no pairing-secret or app-content logging, and redacted diagnostics.
4. **Product UX:** first-run requirements check, status per Target Device, copied deployment command, actionable locked/offline/signing errors, version/about/support links, and an uninstall path.
5. **Release engineering:** unique production bundle ID, coherent minimum OS, icon and copyright metadata, Developer ID signature with timestamp, notarised and stapled DMG/ZIP, Gatekeeper verification on a clean Mac, signed update path, reproducible versioning, rollback artefact, and checksum.
6. **Commerce/legal:** Lemon Squeezy store and licence activation with an offline grace period; privacy policy, EULA/terms, refund policy, support email, data inventory/retention statement, dependency disclosures, Debagr name/trademark clearance, and counsel review of Tailscale/Apple wording.
7. **Marketing/support:** one-page site, real-hardware demo video, requirements and limitations above the checkout, setup guide, troubleshooting guide, compatibility/status page, changelog, and opt-in crash/diagnostic reporting. Publish no customer logo without permission.

## Launch sequence

1. **Private technical preview:** 10–20 developers, free. Exit when at least 90% of fresh installs complete one SSH-triggered deployment and the same users survive restart/sleep tests without developer intervention.
2. **Paid early access:** $99/year with the same explicit compatibility matrix and refund policy. Exit after 30 days without a security-critical issue and support demand is sustainable by one operator.
3. **General availability:** publish the demo, documentation, and paid download. Add team administration, other VPNs, cloud relay, analytics, and enterprise features only after customers repeatedly ask and pay for them.

## Legal and technical risks

| Risk | Severity | Required response |
| --- | --- | --- |
| Apple changes `devicectl` behavior | High | Maintain a narrow OS/Xcode matrix, fail closed on unconfirmed installs, and ship compatibility updates. |
| Marketing outruns the product | High | Keep checkout closed until the local and SSH hardware gates pass; state that devices do not appear on callers' machines. Apple also requires accurate app metadata and rejects misleading claims ([App Review Guidelines 2.3](https://developer.apple.com/app-store/review/guidelines/uk/#accurate-metadata)). |
| Over-broad SSH access | High | Document public-key authentication, least-privilege accounts, private networking, audit, and revocation; Debagr opens no listener. |
| Tailscale commercial terms, trademark, or packaging changes | High | Customer supplies their own compliant account; do not resell; seek written brand/partnership guidance; re-test every supported macOS variant. |
| OS/Xcode churn creates high support load | High | Annual licence, compatibility matrix, signed updater, rollback, and tested release cadence. |
| Hostnames, device identifiers, diagnostics, or licence data become personal data | Medium | Collect nothing by default; document every field, purpose, processor, retention period, deletion route, and opt-in before telemetry. |
| “Debagr” conflicts with an existing mark or is hard to find/spell | Medium | Perform US/EU/UK trademark and domain clearance before purchasing brand assets or announcing GA. No clearance was performed in this research. |
