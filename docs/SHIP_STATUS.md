# Debagr 0.2.0 shipping status

## Unreleased consolidation, 7 November 2026

The launch work is already part of this branch through merge `519fcd8` (launch
commit `36aeec4`). The current source combines Builder/Client discovery and role
trust, temporary USB/IP setup, illustrated wireless setup, and a VirtualHere/SSH
alternative. These changes are **not** in the notarized 0.2.0 build described below.
The local app is ad-hoc signed; no release asset, public site, tap, installed app,
or signing credential was changed by consolidation.

The research thread records a newer unplugged iPhone relay install-and-launch
after a USB/IP refresh of existing trust. [Recorded hardware evidence](DIRECT_DEVICE.md)
preserves its limits. The combined UI, first-ever Apple pairing, VirtualHere,
clean-Mac installation, iPad, and the recovery matrix still require acceptance.
See [consolidation details](CONSOLIDATION.md) before preparing the next release.

## Published release baseline

Updated 4 November 2026. **Published as a technical preview.** The notarized
0.2.0 build 2 is public through the
[`radeknovis/homebrew-debagr`](https://github.com/radeknovis/homebrew-debagr) tap
and its [v0.2.0 prerelease](https://github.com/radeknovis/homebrew-debagr/releases/tag/v0.2.0), with the
[launch site](https://radeknovis.github.io/debagr-site/) served from the public
`radeknovis/debagr-site` repository. The application source stays private.
Clean-Mac, fresh-device, iPad and recovery acceptance were not re-run before
publication; the release notes and site list them as known gaps. Paid checkout
and sponsorship activation have not occurred.

Publisher: the personal Apple Developer team **Radek Novak**. Its Developer ID
Application certificate is installed and has successfully signed build 2. The
private key and validated notarization credentials remain in the local login
Keychain; neither has been exported.
GitHub Sponsors and Ko-fi are the selected funding channels; their activation
is explicitly deferred and does not block releasing the app.

## Publication, 4 November 2026

| Check | Result |
| --- | --- |
| Release | Draft prerelease published by release ID; tag `v0.2.0` created at tap commit `47061a8`. Before publishing, the asset digests matched the local notarized DMG and plugin ZIPs |
| Anonymous download | DMG and `.sha256` fetched without GitHub credentials (HTTP 200); `shasum -a 256 -c` passed for `eb9e3284…f9e0`; anonymous `git ls-remote` and release API access passed |
| Public tap | `brew tap radeknovis/debagr` cloned over HTTPS; `brew install --cask` into a temporary Applications directory passed: 0.2.0 (2), strict signature, stapled ticket, Gatekeeper `Notarized Developer ID` with Homebrew quarantine set, and JSON inventory through the `debagr` link. Uninstalled, untapped and cached downloads removed afterwards |
| Cask | Homepage set to the launch site; `brew style` passed. `brew audit --cask --strict --online` reports two expected findings: GitHub prerelease, and the deliberate macOS 26 floor above the app's macOS 13 minimum |
| Contacts | Support through tap Issues; security, privacy and requested diagnostics through GitHub private vulnerability reporting, now enabled; `SECURITY.md` in the tap; publisher named Radek Novak; no email or postal address published |
| Website | GitHub Pages serves `radeknovis/debagr-site`; download button points at the versioned DMG; absolute `og:image`; every page and asset returned HTTP 200 with the expected content type |

## Completed and checked before publication

| Area | Evidence |
| --- | --- |
| Existing work | Original native settings/Agent tools changes preserved as a separate checkpoint on `release/0.2.0-preparation`; no device settings or profiles changed |
| Swift | 41 tests passed, no warnings/errors; strict Swift format lint and diff whitespace checks pass |
| App | Release 0.2.0, build 2, arm64; app bundle, icon, embedded skill and plist verified; Developer ID signature for Radek Novak (XBSPGPE6R6), Hardened Runtime and Apple timestamp verified |
| Local signing identity | Developer ID Application certificate issued through the personal team, valid until 22 November 2027; issued public key matches the local CSR; matching private key stays in the login Keychain; no key exported |
| Packaged CLI | Four read-only JSON smoke cases pass: inventory, unavailable-device readiness, missing artifact and missing device argument |
| Notarized DMG | `dist/Debagr-0.2.0.dmg` and SHA-256 created; app and DMG submissions both Accepted with no issues; both tickets stapled/validated; both Gatekeeper assessments accepted as Notarized Developer ID |
| Packaged candidate | Final notarized DMG mounted read-only; Applications link checked; app copied and its strict signature, stapled ticket, Gatekeeper acceptance, version/build and JSON inventory verified; image detached |
| Homebrew | Separate `radeknovis/homebrew-debagr` tap with pinned version/final DMG SHA-256, Apple-silicon/macOS 26 requirements and `debagr` CLI link; style and strict audit pass; temporary-appdir install, reinstall, signature/ticket/Gatekeeper/JSON and uninstall/cleanup pass; same DMG via local file URL during test |
| Release channel | Draft prerelease contained the notarized DMG/checksum and both plugin ZIPs/checksums; authenticated download round-trip matched the DMG SHA-256 while the repository was private |
| Signing pipeline | App notarization/stapling before DMG creation; signed/notarized/stapled DMG; both Gatekeeper checks; explicit Accepted gates and Apple logs; final artifact only after success; no overwriting an existing release |
| Release failure checks | Eight mocked scenarios pass: successful sequencing/checksum, app rejection, DMG rejection, Gatekeeper failure, dirty tree, invalid version, invalid build number and wrong signing identity; cleanup verified |
| CI preparation | Tag/version and missing-secret checks, scoped temporary Keychain, always-run credential cleanup, plugin packaging, artifact retention and draft prerelease creation prepared; live signed workflow has not run |
| Native screenshots | Four 2000 × 1680 captures, setup and Agent tools in light/dark; synthetic device data, actual source views, no shipped demo mode; source provenance recorded |
| Promo videos | Landscape 1920 × 1080 and vertical 1080 × 1920, each 24 seconds at 24 fps, H.264/yuv420p, web fast-start, silent; English VTT and SRT captions plus posters |
| Marketing | Social card and sponsor cover, both 1200 × 630; launch copy, storyboard and release notes prepared; self-contained launch site and local gallery |
| Website | Desktop and 390-pixel embedded mobile viewport rendering verified with no horizontal overflow; MP4 playback verified; local asset links and five URL activation scenarios pass, including rejected javascript/http/relative URLs; payment links remain in preparation |
| Sponsorship | GitHub Sponsors and Ko-fi profile, tier and welcome-message drafts; FUNDING template; verified-URL integration prepared without sending money or publishing unverified handles |
| Documentation | Remote macOS 26+ requirement clarified; profile/receipt retention and uninstall documented; old price research marked historical |

The screenshot/video data is illustrative. It is not a new hardware deployment
result. The older `LOCAL-UNNOTARIZED` DMG is a rehearsal artifact; use the
versioned, accepted and stapled `Debagr-0.2.0.dmg` for candidate acceptance.
The 390-pixel check uses an embedded browser viewport; a physical mobile browser
has not been tested. Before publication, Homebrew was tested with the final DMG
through a local file URL; the public download and tap install were verified
after publication. A version-to-version upgrade remains untested.

## Open gaps

| Gate | Current finding | Next concrete step |
| --- | --- | --- |
| CI signing (optional) | No repository/environment release secrets configured | Configure the six secrets only if using hosted signing. A local notarized release can use Keychain credentials without exporting the private key to CI |
| Fresh device acceptance | After the owner unlocked the iPhone and connected Wi-Fi/Tailscale, authenticated readiness passed with `ok: true` and state `ready`; the next deployment correctly stopped after the phone auto-locked (`device_locked`), with no installation confirmed | Verify installation and launch with a signed device build, including SSH and separate-network conditions |
| Recovery and iPad | Restart/sleep/trust/permission matrix and current iPad remote acceptance are incomplete | Run and record the matrix in RELEASE.md; keep unverified providers and iPad labeled accordingly |
| Customer installation | Notarized candidate passed local DMG copy/signature/ticket/Gatekeeper/CLI checks; a clean supported Mac has not been tested | Install the accepted/stapled candidate from its downloaded DMG on a clean Mac; verify publisher, online/offline Gatekeeper and setup/recovery/uninstall |
| Homebrew upgrade | Only 0.2.0 exists, so `brew upgrade --cask` between versions is untested | Install the current version, then upgrade, when the next version ships |
| Policies | Publisher named and contact routes set; EULA, processor terms, refund policy, governing law and counsel review remain drafts | Complete before any sale or commercial launch |

## Funding activation deferred

GitHub Sponsors and Ko-fi are selected. Their profiles, tiers, graphics and
website integration are prepared; authentication, payout setup, provider terms
and approval are deferred at the owner's request. Keep payment URLs empty and
resume activation only when requested. Funding is optional for the app release.

## Handoff

1. Post from [`Marketing/launch-copy.md`](../Marketing/launch-copy.md); its preview
   links point at the live site. Leave funding placeholders until activation.
2. Close the open gaps above with the published DMG; do not treat a green build as
   authenticated deployment or notarization proof. When a gap closes, update the
   release notes, the site and this report.
3. Follow [`RELEASE.md`](RELEASE.md) for the next release; retain Apple logs and
   previous signed installers for rollback.

No Intel/universal build, cellular transport, new updater, paid licensing system,
or additional cloud backend was added. Updates remain manual for the preview.
