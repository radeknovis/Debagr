# Debagr 0.2.0 shipping status

Checked 22 October 2026. **Prepared for review; not yet cleared for public release.**
The app, launch kit and signing pipeline are prepared. No notarized customer
release, public launch, paid checkout, or sponsorship channel has been activated.

Publisher: the personal Apple Developer team **Radek Novak**. No existing
Developer ID Application certificate or notarization credentials are available.
GitHub Sponsors and Ko-fi are the selected funding channels; their activation
is explicitly deferred and does not block releasing the app.

## Completed and checked

| Area | Evidence |
| --- | --- |
| Existing work | Original native settings/Agent tools changes preserved as a separate checkpoint on `release/0.2.0-preparation`; no device settings or profiles changed |
| Swift | 41 tests passed, no warnings/errors; strict Swift format lint and diff whitespace checks pass |
| App | Release build packaged as 0.2.0; app bundle, icon, embedded skill, plist and ad-hoc Hardened Runtime signature verified; arm64 |
| Packaged CLI | Four read-only JSON smoke cases pass: inventory, unavailable-device readiness, missing artifact and missing device argument |
| Local DMG | Created clearly labeled `Debagr-0.2.0-LOCAL-UNNOTARIZED.dmg`; mounted read-only, verified Applications link, copied app, verified signature/resources and ran its CLI; portable checksum created |
| Signing pipeline | App notarization/stapling before DMG creation; signed/notarized/stapled DMG; both Gatekeeper checks; explicit Accepted gates and Apple logs; final artifact only after success; no overwriting an existing release |
| Release failure checks | Eight mocked scenarios pass: successful sequencing/checksum, app rejection, DMG rejection, Gatekeeper failure, dirty tree, invalid version, invalid build number and wrong signing identity; cleanup verified |
| CI preparation | Tag/version and missing-secret checks, scoped temporary Keychain, always-run credential cleanup, plugin packaging, artifact retention and draft prerelease creation prepared; live signed workflow has not run |
| Native screenshots | Four 2000 × 1680 captures, setup and Agent tools in light/dark; synthetic device data, actual source views, no shipped demo mode; source provenance recorded |
| Promo videos | Landscape 1920 × 1080 and vertical 1080 × 1920, each 24 seconds at 24 fps, H.264/yuv420p, web fast-start, silent; English VTT and SRT captions plus posters |
| Marketing | Social card and sponsor cover, both 1200 × 630; launch copy, storyboard and release notes prepared; self-contained launch site and local gallery |
| Website | Desktop and 390-pixel embedded mobile viewport rendering verified with no horizontal overflow; MP4 playback verified; local asset links and five URL activation scenarios pass, including rejected javascript/http/relative URLs; download and payment links remain in preparation |
| Sponsorship | GitHub Sponsors and Ko-fi profile, tier and welcome-message drafts; FUNDING template; verified-URL integration prepared without sending money or publishing unverified handles |
| Documentation | Remote macOS 26+ requirement clarified; profile/receipt retention and uninstall documented; old price research marked historical |

The screenshot/video data is illustrative. It is not a new hardware deployment
result. The local DMG is a rehearsal artifact and must not be published as the
notarized customer installer. The 390-pixel check uses an embedded browser viewport; a physical mobile
browser has not been tested.

## Gates that still need real access or hardware

| Gate | Current finding | Next concrete step |
| --- | --- | --- |
| Developer ID | Owner accepted the updated Program License Agreement; certificate access is restored. The personal team Radek Novak can request Developer ID Application through the Apple Developer portal. No certificate or notary credentials have been created yet. | Complete the prepared certificate request, keep its private key in the local login Keychain, then store notarization credentials locally; see RELEASE.md |
| CI signing (optional) | No repository/environment release secrets configured | Configure the six secrets only if using hosted signing. A local notarized release can use Keychain credentials without exporting the private key to CI |
| Fresh device acceptance | Current configured iPhone returned `device_unavailable` on a read-only readiness check | Connect/unlock that phone on Wi-Fi with its private VPN; get authenticated readiness and verify installation and launch with a known signed device build, including SSH and separate-network conditions |
| Recovery and iPad | Restart/sleep/trust/permission matrix and current iPad remote acceptance are incomplete | Run and record the matrix in RELEASE.md; keep unverified providers and iPad labeled accordingly |
| Customer installation | No notarized candidate or clean supported Mac available | Install the accepted/stapled candidate from its downloaded DMG on a clean Mac; verify publisher, online/offline Gatekeeper and setup/recovery/uninstall |
| Public distribution | Repository is private, no production domain or public binary destination confirmed | Choose public binary hosting or an explicit repository visibility/license plan; verify support/private security contacts and update URLs |
| Policies | Privacy/EULA/support are clearly labeled drafts with owner/legal details missing | Owner supplies the actual publisher/contact details and reviews terms before public distribution or any commercial launch |

## Funding activation deferred

GitHub Sponsors and Ko-fi are selected. Their profiles, tiers, graphics and
website integration are prepared; authentication, payout setup, provider terms
and approval are deferred at the owner's request. Keep payment URLs empty and
resume activation only when requested. Funding is optional for the app release.

## Handoff

1. Review [`Marketing/index.html`](../Marketing/index.html) and the sponsor drafts.
2. Complete the access and hardware gates above; do not treat a green build as
   authenticated deployment or notarization proof.
3. Follow [`RELEASE.md`](RELEASE.md) for the tagged signing run and clean-Mac
   acceptance. Retain Apple logs and the previous signed installer for rollback.
4. Set the verified download URL, add production social metadata, verify the
   site on the intended production host, and approve the draft release and site
   for publication. Leave funding links in preparation until activation resumes.

No Intel/universal build, cellular transport, new updater, paid licensing system,
or additional cloud backend was added. Updates remain manual for the preview.
