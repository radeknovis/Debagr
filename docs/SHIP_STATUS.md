# Debagr 0.3.0 shipping status

Updated 11 November 2026. **0.3.0 build 5 is prepared, not tagged, not
notarized and not published.** The published version is still 0.2.0 build 2;
its record is kept below as history. The [release runbook](RELEASE.md) owns the
steps from here to publication.

## Release identity

| Item | Value |
| --- | --- |
| Version and build | 0.3.0, build 5 |
| Channel | Technical preview, Apple silicon |
| Signing | Developer ID signed and notarized by `scripts/release-macos-app.sh`; the script has not been run for this build |
| Licence | Free personal and internal evaluation, no redistribution; paid terms remain a draft |
| Requirement | Managed remote deployment needs macOS 26 or later on the Mac |
| Publisher | Radek Novak (`XBSPGPE6R6`); certificate and notarization profile stay in the local login Keychain |

Earlier documents disagree about 0.3.0 candidate build numbers.
[AUDIT_FIXES.md](AUDIT_FIXES.md) records build 2 as signed and notarized
locally, an earlier version of this file called build 3 the notarized candidate,
and [CONSOLIDATION.md](CONSOLIDATION.md) records build 4 as Developer ID signed
and not notarized. None of them was published, and the 11 November audit found
none retained on disk. The release uses build 5 so that its number is above
every earlier candidate.

## Done

| Area | State |
| --- | --- |
| Audit fixes | Merged in PR #15 (`2c9d975`); details in [AUDIT_FIXES.md](AUDIT_FIXES.md) |
| Connection design | Builder and Client discovery and linking, guided existing pairing and temporary USB setup merged in PR #16 (`97978e7`); details in [CONSOLIDATION.md](CONSOLIDATION.md) |
| Release decisions of 11 November | Discovery and role sync run only while the Builder and Client setup screen is open or a machine role is saved; the unauthenticated discovery reply is reduced; pairing without a code needs the same Tailscale user; first run opens on existing pairing with the USB paths labelled Experimental; USB/IP helper lookup, root supervisor inputs and default tool locations are hardened. These are part of the release-readiness change set. This file records no test result for them; the evidence is the green CI run on the release commit required by the pre-tag checklist |
| Hardware | One remote iPhone install and OS-confirmed launch over Tailscale on 10 November 2026, with the restored CLI in a locally signed pre-release build. It predates the 11 November changes and is not a result for build 5 |
| Release documents | [Release notes](../Marketing/release-notes.md), [changelog](../CHANGELOG.md) and runbook written for 0.3.0 build 5 |
| Waiver | On 11 November 2026 the owner waived pre-release hardware acceptance for the known gaps below, as for 0.2.0 |

## Remaining before publication

1. Pre-tag checklist: green CI on the exact release commit and the local checks
   on an idle release Mac. The marketing screenshots are recaptured; capture
   them again only if `Sources/Debagr/DeviceSetupWindow.swift` changes.
2. Tag `v0.3.0`.
3. Release run for build 5. This is the first notarization of a bundle that
   contains the USBIPProbe helper.
4. Post-notarization acceptance: notary log review, local DMG check, clean Mac,
   offline first launch, Homebrew install and the 0.2.0 to 0.3.0 upgrade.
5. Publish: tap release and cask, the tap's `README.md` and `SECURITY.md`, the
   site text and `DEBAGR_DOWNLOAD_URL`, then the publication record in this file.

Until step 5, the site, the cask and every download link stay on 0.2.0.

## Known gaps for 0.3.0

None of these is verified. Do not describe any of them as verified until its
result is recorded here.

- First launch on a clean Mac.
- Offline first launch.
- iPad.
- The recovery matrix: restart, sleep/wake, network change, revoked trust and
  denied Local Network permission.
- VPN providers other than Tailscale.
- macOS 13 to 15.
- The Homebrew upgrade from 0.2.0 to 0.3.0.
- All hardware acceptance of USB/IP, VirtualHere and two-Mac Builder and Client
  linking.

CI signing remains optional and unconfigured. Paid terms, processor terms,
refund policy, governing law and counsel review remain drafts and must be
complete before any sale. Funding activation is deferred, as described below.

## 0.2.0 publication record


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

### Publication, 4 November 2026

| Check | Result |
| --- | --- |
| Release | Draft prerelease published by release ID; tag `v0.2.0` created at tap commit `47061a8`. Before publishing, the asset digests matched the local notarized DMG and plugin ZIPs |
| Anonymous download | DMG and `.sha256` fetched without GitHub credentials (HTTP 200); `shasum -a 256 -c` passed for `eb9e3284…f9e0`; anonymous `git ls-remote` and release API access passed |
| Public tap | `brew tap radeknovis/debagr` cloned over HTTPS; `brew install --cask` into a temporary Applications directory passed: 0.2.0 (2), strict signature, stapled ticket, Gatekeeper `Notarized Developer ID` with Homebrew quarantine set, and JSON inventory through the `debagr` link. Uninstalled, untapped and cached downloads removed afterwards |
| Cask | Homepage set to the launch site; `brew style` passed. `brew audit --cask --strict --online` reports two expected findings: GitHub prerelease, and the deliberate macOS 26 floor above the app's macOS 13 minimum |
| Contacts | Support through tap Issues; security, privacy and requested diagnostics through GitHub private vulnerability reporting, now enabled; `SECURITY.md` in the tap; publisher named Radek Novak; no email or postal address published |
| Website | GitHub Pages serves `radeknovis/debagr-site`; download button points at the versioned DMG; absolute `og:image`; every page and asset returned HTTP 200 with the expected content type |

### Completed and checked before publication

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

### Open gaps at 0.2.0 publication

This table is the 0.2.0 record. The current gaps are in [Known gaps for 0.3.0](#known-gaps-for-030).

| Gate | Current finding | Next concrete step |
| --- | --- | --- |
| CI signing (optional) | No repository/environment release secrets configured | Configure the six secrets only if using hosted signing. A local notarized release can use Keychain credentials without exporting the private key to CI |
| Fresh device acceptance | After the owner unlocked the iPhone and connected Wi-Fi/Tailscale, authenticated readiness passed with `ok: true` and state `ready`; the next deployment correctly stopped after the phone auto-locked (`device_locked`), with no installation confirmed | Verify installation and launch with a signed device build, including SSH and separate-network conditions |
| Recovery and iPad | Restart/sleep/trust/permission matrix and current iPad remote acceptance are incomplete | Run and record the matrix in RELEASE.md; keep unverified providers and iPad labeled accordingly |
| Customer installation | Notarized candidate passed local DMG copy/signature/ticket/Gatekeeper/CLI checks; a clean supported Mac has not been tested | Install the accepted/stapled candidate from its downloaded DMG on a clean Mac; verify publisher, online/offline Gatekeeper and setup/recovery/uninstall |
| Homebrew upgrade | Only 0.2.0 exists, so `brew upgrade --cask` between versions is untested | Install the current version, then upgrade, when the next version ships |
| Policies | Publisher and contact routes set; free preview licensed for personal/internal evaluation without redistribution; paid terms, processor terms, refund policy, governing law and counsel review remain drafts | Complete before any sale or commercial launch |

### Funding activation deferred

GitHub Sponsors and Ko-fi are selected. Their profiles, tiers, graphics and
website integration are prepared; authentication, payout setup, provider terms
and approval are deferred at the owner's request. Keep payment URLs empty and
resume activation only when requested. Funding is optional for the app release.

### Handoff after 0.2.0

1. Post from [`Marketing/launch-copy.md`](../Marketing/launch-copy.md); its preview
   links point at the live site. Leave funding placeholders until activation.
2. Close the open gaps above with the published DMG; do not treat a green build as
   authenticated deployment or notarization proof. When a gap closes, update the
   release notes, the site and this report.
3. Follow [`RELEASE.md`](RELEASE.md) for the next release; retain Apple logs and
   previous signed installers for rollback.

No Intel/universal build, cellular transport, new updater, paid licensing system,
or additional cloud backend was added. Updates remain manual for the preview.
