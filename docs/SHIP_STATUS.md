# Debagr 0.2.0 shipping status

Checked 23 October 2026. **Prepared for review; not yet cleared for public release.**
The app, launch kit and signing pipeline are prepared. The app and DMG have
passed Apple notarization, stapling and local Gatekeeper checks. Public launch,
paid checkout and sponsorship activation have not occurred.

Publisher: the personal Apple Developer team **Radek Novak**. Its Developer ID
Application certificate is installed and has successfully signed build 2. The
private key and validated notarization credentials remain in the local login
Keychain; neither has been exported.
GitHub Sponsors and Ko-fi are the selected funding channels; their activation
is explicitly deferred and does not block releasing the app.

## Completed and checked

| Area | Evidence |
| --- | --- |
| Existing work | Original native settings/Agent tools changes preserved as a separate checkpoint on `release/0.2.0-preparation`; no device settings or profiles changed |
| Swift | 41 tests passed, no warnings/errors; strict Swift format lint and diff whitespace checks pass |
| App | Release 0.2.0, build 2, arm64; app bundle, icon, embedded skill and plist verified; Developer ID signature for Radek Novak (XBSPGPE6R6), Hardened Runtime and Apple timestamp verified |
| Local signing identity | Developer ID Application certificate issued through the personal team, valid until 22 November 2027; issued public key matches the local CSR; matching private key stays in the login Keychain; no key exported |
| Packaged CLI | Four read-only JSON smoke cases pass: inventory, unavailable-device readiness, missing artifact and missing device argument |
| Notarized DMG | `dist/Debagr-0.2.0.dmg` and SHA-256 created; app and DMG submissions both Accepted with no issues; both tickets stapled/validated; both Gatekeeper assessments accepted as Notarized Developer ID |
| Packaged candidate | Final notarized DMG mounted read-only; Applications link checked; app copied and its strict signature, stapled ticket, Gatekeeper acceptance, version/build and JSON inventory verified; image detached |
| Homebrew | Separate private `radeknovis/homebrew-debagr` tap with pinned version/final DMG SHA-256, Apple-silicon/macOS 26 requirements and `debagr` CLI link; style and strict audit pass; temporary-appdir install, reinstall, signature/ticket/Gatekeeper/JSON and uninstall/cleanup pass; same DMG via local file URL during test |
| Private release channel | Draft prerelease contains the notarized DMG/checksum and both plugin ZIPs/checksums; authenticated download round-trip matches the DMG SHA-256; repository remains private and release remains draft |
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
result. The older `LOCAL-UNNOTARIZED` DMG is a rehearsal artifact; use the
versioned, accepted and stapled `Debagr-0.2.0.dmg` for candidate acceptance.
The 390-pixel check uses an embedded browser viewport; a physical mobile browser
has not been tested. Homebrew was tested with the final DMG through a local file
URL; anonymous public fetching and a version-to-version upgrade remain untested.

## Gates that still need real access or hardware

| Gate | Current finding | Next concrete step |
| --- | --- | --- |
| CI signing (optional) | No repository/environment release secrets configured | Configure the six secrets only if using hosted signing. A local notarized release can use Keychain credentials without exporting the private key to CI |
| Fresh device acceptance | After the owner unlocked the iPhone and connected Wi-Fi/Tailscale, authenticated readiness passed with `ok: true` and state `ready`; the next deployment correctly stopped after the phone auto-locked (`device_locked`), with no installation confirmed | Verify installation and launch with a signed device build, including SSH and separate-network conditions |
| Recovery and iPad | Restart/sleep/trust/permission matrix and current iPad remote acceptance are incomplete | Run and record the matrix in RELEASE.md; keep unverified providers and iPad labeled accordingly |
| Customer installation | Notarized candidate passed local DMG copy/signature/ticket/Gatekeeper/CLI checks; a clean supported Mac has not been tested | Install the accepted/stapled candidate from its downloaded DMG on a clean Mac; verify publisher, online/offline Gatekeeper and setup/recovery/uninstall |
| Public distribution | Application source stays private. `radeknovis/homebrew-debagr` is a separate private cask/binary channel prepared for review; public download and tap activation have not occurred. | Verify support/private security contacts and policies, review publishing only the cask/binary channel, then verify anonymous download and Homebrew fetching; no app-source visibility change is needed |
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
3. Use the existing notarized candidate for clean-Mac acceptance. Follow
   [`RELEASE.md`](RELEASE.md) for future signing runs; retain Apple logs and
   previous signed installers for rollback.
4. Set the verified download URL, add production social metadata, verify the
   site on the intended production host, and approve the draft release and site
   for publication. Leave funding links in preparation until activation resumes.

No Intel/universal build, cellular transport, new updater, paid licensing system,
or additional cloud backend was added. Updates remain manual for the preview.
