# Debagr release runbook

Updated 12 November 2026. **0.3.0, build 5** is published as a
technical preview for Apple silicon. Managed remote deployment requires macOS 26
or later on the Mac. See
[SHIP_STATUS.md](SHIP_STATUS.md) for what is done and what remains.

The order is: pre-tag checklist, tag, release run, post-notarization
acceptance, publish. Acceptance on a clean Mac and through Homebrew needs the
notarized DMG, so it comes after the tag and the release run, not before.

## Publisher credentials

The selected publisher is the personal Apple Developer team **Radek Novak**
(`XBSPGPE6R6`). On 23 October 2026, a **Developer ID Application** certificate
was issued through Apple's portal and imported into the local login Keychain.
Its public key matches the locally generated CSR; its matching private key
remains in Keychain and has not been exported or copied. The certificate expires
on **22 November 2027**.

Release 0.2.0, build 2 was signed with
`Developer ID Application: Radek Novak (XBSPGPE6R6)` and notarized on
23 October 2026. Apple accepted both the app and DMG submissions without
issues, both tickets were stapled and validated, and both Gatekeeper assessments
reported Notarized Developer ID. Release 0.3.0, build 5 uses the same identity
and notarization profile; both app and DMG were accepted on 12 November 2026. CI signing remains optional.

The owner accepted the updated Program License Agreement on 22 October 2026.
Xcode's creation menu was disabled, so the certificate was created with Keychain
Certificate Assistant and the personal team's portal using the G2 intermediary.
No existing certificates were revoked.

For a future certificate replacement, the publisher's Apple Developer Account
Holder must create the certificate and its matching private key. An Apple Development or Apple Distribution
certificate does not replace it.
[Apple Developer ID certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates).

Use Xcode Settings → Apple Accounts → Radek Novak → Manage Certificates →
Create a certificate → Developer ID Application when available. Otherwise use
Keychain Access → Certificate Assistant → Request a Certificate From a
Certificate Authority, save the CSR to disk, and upload it to the personal
team's Developer ID Application request. Select the G2 intermediary for current
Xcode, download the issued certificate and import it into the same Keychain.
[Apple CSR instructions](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request).

Keep the private key in the login Keychain. Do not revoke existing development
certificates, export keys, or provide passwords in chat. Check availability with:

```sh
security find-identity -v -p codesigning
```

The owner configured `debagr-notary` in the local Keychain and validation passed.
For future setup, generate an app-specific password at Apple Account → Sign-In
and Security → App-Specific Passwords, then enter it only at the secure local
prompt.
[Apple app-specific password instructions](https://support.apple.com/en-ie/102654).
Store credentials in Keychain using the publisher's Apple ID and team ID; omit
`--password` so the command prompts without placing the secret in shell history:

```sh
xcrun notarytool store-credentials debagr-notary \
  --apple-id YOUR_APPLE_ID --team-id XBSPGPE6R6
xcrun notarytool history --keychain-profile debagr-notary
```

The interactive command keeps credentials out of the repository. Never commit
P12/P8 files, app-specific passwords, Keychain exports, or pairing profiles.

## 1. Pre-tag checklist

1. The release commit is on `main` and the **CI** workflow is green on that
   exact commit, not on an earlier one:

   ```sh
   gh run list --workflow ci.yml --commit "$(git rev-parse HEAD)"
   ```

2. On the release Mac, check out that commit with a clean working tree. Use an
   idle machine: stop other builds and heavy jobs. The test suite uses real
   local sockets and Bonjour with deadlines, and the release script runs it
   again and stops on the first failure. Quit any running Debagr; two instances
   running at once produced misleading device state during earlier candidate
   tests.
3. Run the checks by hand. Each must pass:

   ```sh
   git status --porcelain                         # prints nothing
   cat VERSION                                    # 0.3.0
   python3 scripts/check-release.py
   python3 scripts/check-docs.py
   python3 scripts/check-marketing.py
   VERSION=0.3.0 python3 scripts/package-plugins.py
   ./scripts/build-macos-app.sh release
   ./scripts/verify-macos-app.sh
   python3 scripts/check-agent-cli.py
   python3 scripts/check-menu-bar-shutdown.py
   ```

   `check-agent-cli.py` and `check-menu-bar-shutdown.py` test the packaged
   `Debagr.app` that `build-macos-app.sh` leaves in the repository root; that
   local build is ad-hoc signed. The shutdown check starts its own menu-bar
   process from that bundle, sends it SIGTERM and never signals another
   instance. `check-marketing.py` needs `ffprobe` and `node`. It fails at the
   screenshot provenance assertion when `Sources/Debagr/DeviceSetupWindow.swift`
   has changed since the last capture; recapture with
   `python3 scripts/capture-marketing.py` and `python3 scripts/render-marketing.py`
   (rendering needs Pillow; see [Marketing/README.md](../Marketing/README.md)
   if the default `python3` lacks it), review the images and commit them before
   tagging.
4. Confirm the signing identity and notarization profile with the two commands
   in [Publisher credentials](#publisher-credentials).
5. Confirm `dist/Debagr-0.3.0.dmg` does not exist. Earlier 0.3.0 candidates used
   the same file name and the release script refuses to overwrite it. Move any
   earlier candidate and its Apple logs out of `dist/` first.
6. Open the website, support, privacy, terms and private security-reporting
   destinations and confirm each one loads.

## 2. Tag

Tag the checked commit and push the tag. If the release run fails and the
source must change, fix it on `main`, repeat the pre-tag checklist, then delete
the unpublished tag and tag the new commit. Raise the build number if Apple
accepted any build 5 submission. Never move the tag after publication.

```sh
git tag -a v0.3.0 -m "Debagr 0.3.0 technical preview"
git push origin v0.3.0
```

## 3. Release run

Run from the tagged, clean checkout. Keep previous signed artifacts.

```sh
VERSION=0.3.0 \
BUILD_NUMBER=5 \
CODESIGN_IDENTITY="Developer ID Application: Radek Novak (XBSPGPE6R6)" \
NOTARY_PROFILE=debagr-notary \
DEBAGR_WEBSITE_URL="https://radeknovis.github.io/debagr-site/" \
DEBAGR_SUPPORT_URL="https://github.com/radeknovis/homebrew-debagr/issues" \
./scripts/release-macos-app.sh
VERSION=0.3.0 python3 scripts/package-plugins.py
```

Both URLs are required for this release. `scripts/build-macos-app.sh` writes
the `DebagrWebsiteURL` and `DebagrSupportURL` Info.plist keys only when the
variables are set, and the **Support…** menu item appears only when
`DebagrSupportURL` is present. Confirm the result before going further:

```sh
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Debagr.app/Contents/Info.plist   # 0.3.0
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Debagr.app/Contents/Info.plist              # 5
/usr/libexec/PlistBuddy -c "Print :DebagrSupportURL" Debagr.app/Contents/Info.plist
```

`NOTARY_KEYCHAIN` optionally selects a dedicated Keychain. The script refuses
nonnumeric bundle versions/build numbers, a `VERSION` that differs from the
`VERSION` file, dirty worktrees, non-Developer-ID identities, and overwriting an
existing versioned DMG. `ALLOW_DIRTY_RELEASE=1` is only for a deliberate local
rehearsal; never publish such a build as a reproducible tagged release.

The script lints, tests, builds and verifies the bundle; notarizes the app ZIP;
retrieves Apple's result and log; requires `Accepted`; staples and validates the
app and checks Gatekeeper; packages it with an Applications link; signs,
notarizes and staples the DMG; assesses that image; and writes a portable SHA-256
file. The final DMG is moved into `dist/` only after those gates pass.
[Apple's custom workflow and stapling guidance](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

The run leaves these files in `dist/`:

- `Debagr-0.3.0.dmg` and `Debagr-0.3.0.dmg.sha256`
- `debagr-claude-code-0.3.0.zip`, `debagr-codex-0.3.0.zip` and their `.sha256` files
- `Debagr-0.3.0-{app,dmg}-{submission,notary-log}.json`

The four Apple JSON files are diagnostic artifacts, not public release assets.
The release safety test uses mocked Apple tools to check sequencing and
failures; it cannot establish real notarization.

## 4. Post-notarization acceptance

On 11 November 2026 the owner waived pre-release hardware acceptance for the
known gaps of 0.3.0, as was done for 0.2.0. The gaps are listed in
[SHIP_STATUS.md](SHIP_STATUS.md), the release notes and the changelog. Run the
checks below as far as the available machines allow and record each result. A
check that is not run stays a listed gap and does not block publication. The
waiver covers hardware acceptance only. It does not cover the signing,
notarization, stapling and Gatekeeper gates that the release script enforces.

Record exact Mac, macOS, Xcode, device, iOS/iPadOS, network/provider, artifact
checksum, and each result. Private device IDs and pairing metadata belong in a
private test record, not marketing assets or public issue reports.

1. **Notarization of the USBIPProbe helper.** Build 5 is the first notarized
   bundle that contains `Contents/MacOS/USBIPProbe`. Read both Apple logs even
   though the status is `Accepted`, and look for any issue or warning that names
   the helper. Then check it in the stapled app:

   ```sh
   codesign --verify --strict --verbose=2 Debagr.app/Contents/MacOS/USBIPProbe
   codesign -dv --verbose=4 Debagr.app/Contents/MacOS/USBIPProbe
   ```

   The second command must show the Developer ID authority, a secure timestamp
   and the hardened runtime flag.
2. **Local DMG check.** Verify the SHA-256 from `dist/`, mount the DMG
   read-only, check the Applications link, copy the app out and verify its
   strict signature, `xcrun stapler validate`, Gatekeeper acceptance, version
   0.3.0 (5) and `--devices --json`. Detach the image.
3. **Clean Mac.** On a clean supported Mac, verify the checksum, mount the DMG,
   drag Debagr to Applications and launch it. Gatekeeper must show the expected
   publisher and need no bypass. With no saved device, the setup window must
   open on the existing-pairing form, and the USB path must be labelled
   Experimental. Then check Local Network permission, Agent tools, Launch at
   Login, About and version, diagnostics, the Support… item and uninstall.
4. **Offline first launch.** Repeat the first launch on a clean Mac with
   networking off. It must open without contacting Apple, which shows the
   stapled ticket is used.
5. **Homebrew install and the 0.2.0 to 0.3.0 upgrade.** On this Mac,
   `/Applications/Debagr.app` is an ad-hoc design build that Homebrew has
   registered under the 0.2.0 cask. Upgrading from it would not test the
   published 0.2.0. Quit Debagr and restore the published build first:

   ```sh
   brew reinstall --cask radeknovis/debagr/debagr
   /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" /Applications/Debagr.app/Contents/Info.plist   # 2
   spctl --assess --type execute --verbose=2 /Applications/Debagr.app                               # Notarized Developer ID
   ```

   The reinstall replaces the design build in `/Applications`; keep a copy if
   it is still needed. Before publication, test with the 0.2.0 method recorded
   in [DISTRIBUTION_HISTORY.md](DISTRIBUTION_HISTORY.md): a temporary copy of
   the cask with version 0.3.0, the final SHA-256 and a local file URL for the
   final DMG. Never commit a file URL to the tap. Otherwise run the upgrade
   from the public tap immediately after publication and record it as a
   post-publication result:

   ```sh
   brew upgrade --cask radeknovis/debagr/debagr
   debagr --version          # 0.3.0 (5), through the Homebrew link
   debagr --usbip probe      # without sudo: JSON state requires_root, exit status 2
   debagr --devices --json
   ```

   The `requires_root` state is printed by the bundled helper, so it shows that
   `debagr`, run through the Homebrew symlink, found USBIPProbe. Also confirm
   the installed app's strict signature, stapled ticket and Gatekeeper
   acceptance, that `~/.config/debagr/` is unchanged, and that a device saved
   in 0.2.0 is still shown. Test a fresh `brew install --cask` as well.
6. **Hardware, covered by the waiver.** With USB disconnected and the iPhone on
   another Wi-Fi network, require authenticated readiness, then an install
   result confirming the expected bundle ID and a separate successful launch.
   Repeat through SSH from another computer. Repeat with iPad before claiming
   it validated, and for each VPN provider before promoting it from implemented
   to verified. Check app and Mac restart, sleep/wake, a locked or offline
   device, network changes, revoked and restored trust, and denied Local
   Network permission. Run USB/IP, VirtualHere and two-Mac Builder and Client
   linking on real hardware before describing any of them as verified. Keep
   unsupported cellular-only operation explicit and the one-device scope visible.

When a gap closes before publication, remove it from
`Marketing/release-notes.md`, `CHANGELOG.md`, the site text below and
[SHIP_STATUS.md](SHIP_STATUS.md), and edit the draft release body to match.

## 5. Publish

The public [homebrew-debagr repository](https://github.com/radeknovis/homebrew-debagr)
contains the pinned cask and the releases. The app source repository stays
private; this channel does not need it. See [DISTRIBUTION.md](DISTRIBUTION.md)
for the release boundaries. Keep the 0.2.0 release and its assets for rollback.

1. Create a draft prerelease in the tap with the accepted artifacts and the
   release notes:

   ```sh
   gh release create v0.3.0 --repo radeknovis/homebrew-debagr --draft --prerelease \
     --title "Debagr 0.3.0 — Technical Preview" --notes-file Marketing/release-notes.md \
     dist/Debagr-0.3.0.dmg dist/Debagr-0.3.0.dmg.sha256 \
     dist/debagr-*-0.3.0.zip dist/debagr-*-0.3.0.zip.sha256
   ```

   Download the draft's assets with authenticated access and compare their
   digests with the local files.
2. In the tap, update `Casks/debagr.rb` to version 0.3.0 and the SHA-256 from
   `dist/Debagr-0.3.0.dmg.sha256`. Update the tap's `README.md` and
   `SECURITY.md` for 0.3.0: the version, the requirements, the known gaps, the
   two private-network listeners and when they run, and the statement that only
   the latest release receives fixes. Run `brew style radeknovis/debagr` and
   `brew audit --cask --strict radeknovis/debagr/debagr`, then push.
3. Publish the draft immediately after the push, so the cask never points at a
   missing download for long. `gh release edit` cannot find a draft by its tag,
   so publish by release ID:
   `gh api -X PATCH repos/radeknovis/homebrew-debagr/releases/ID -F draft=false`.
4. Without GitHub credentials, download the DMG and its `.sha256` from the
   release and run `shasum -a 256 -c`. Run
   `brew audit --cask --strict --online radeknovis/debagr/debagr`;
   for 0.2.0 it reported two expected findings, the GitHub prerelease and the
   macOS 26 floor above the app's macOS 13 minimum. Run the Homebrew upgrade
   from the public tap if it was not tested before publication.
5. Update this repository. Only now may it say that 0.3.0 is available. Find
   the statements that call 0.2.0 the published version:

   ```sh
   grep -rn "0\.2\.0" README.md CHANGELOG.md docs Marketing --include="*.md" --include="*.html" --include="*.js"
   ```

   Statements about 0.2.0 that are history stay as they are. In `CHANGELOG.md`,
   replace the "Unreleased until published" sentence with the publication date.
   Record the publication in [SHIP_STATUS.md](SHIP_STATUS.md) the way the 0.2.0
   record does. The site and launch kit need these exact changes:

   - `Marketing/site/config.js`, `DEBAGR_DOWNLOAD_URL`: replace
     `https://github.com/radeknovis/homebrew-debagr/releases/download/v0.2.0/Debagr-0.2.0.dmg`
     with
     `https://github.com/radeknovis/homebrew-debagr/releases/download/v0.3.0/Debagr-0.3.0.dmg`.
   - `Marketing/site/index.html`, availability heading (line 64 on 11 November): replace
     `Technical preview 0.2.0<br>is available.` with
     `Technical preview 0.3.0<br>is available.`
   - `Marketing/site/index.html`, release link in the same section (line 65): replace
     `releases/tag/v0.2.0">0.2.0 release</a>` with
     `releases/tag/v0.3.0">0.3.0 release</a>`.
   - `Marketing/site/index.html`, fine print in the same section (line 65): replace the
     paragraph that starts `Not yet re-verified for 0.2.0:` with
     `Verified on hardware for 0.3.0: one remote iPhone install and launch over Tailscale, using a pre-release build. Not yet verified: first launch on a clean Mac, offline first launch, iPad, the recovery matrix, VPN providers other than Tailscale, macOS 13 to 15, the Homebrew upgrade from 0.2.0, and the experimental USB setup and two-Mac linking on hardware.`
     Remove any gap that has closed.
   - `Marketing/index.html`, the eyebrow and warning that name 0.2.0.
   - `Marketing/README.md` and `Marketing/launch-copy.md`: the status lines at
     the top, and remove the "do not post before publication" note from the
     0.3.0 posts.
6. Run `python3 scripts/check-marketing.py` and `python3 scripts/check-docs.py`,
   commit, then copy the whole `Marketing/site/` directory to
   `radeknovis/debagr-site` and push. Load the live page and follow its
   download link.

## GitHub Actions release (optional hosted signing)

The private repository currently has no release secrets or configured release
environment. Prepare a protected `release` environment with a required reviewer
if the repository's plan supports it. Add these secrets through GitHub's UI or
`gh secret set NAME < /secure/local/file`; do not paste values into chat or
command history:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 of the password-protected Developer ID P12 |
| `DEVELOPER_ID_P12_PASSWORD` | P12 export password |
| `DEVELOPER_ID_APPLICATION_IDENTITY` | Exact Developer ID Application identity |
| `APP_STORE_CONNECT_KEY_P8` | Notarization API private key |
| `APP_STORE_CONNECT_KEY_ID` | Its key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Its issuer ID |

The workflow creates a random temporary build-Keychain password; no stored
`BUILD_KEYCHAIN_PASSWORD` is needed. It scopes notarization credentials to that
Keychain and removes the Keychain and imported files in an `always()` cleanup.
Set the repository or environment variables `DEBAGR_WEBSITE_URL` and
`DEBAGR_SUPPORT_URL` to the same two values as the local command; without
`DEBAGR_SUPPORT_URL` the built app has no Support… menu item.

After the final commit and tag are pushed, invoke **Release** from the tag,
not a branch. For example, from the approved checkout:

```sh
gh workflow run release.yml --ref v0.3.0 -f version=0.3.0 -f build_number=5
```

The workflow enforces the tag/version match, checks required credentials, runs
release safety checks, builds the notarized app/DMG and plugin ZIPs, saves
artifacts and logs, and creates a **draft prerelease** in this private
repository. Review the download and acceptance evidence, then publish through
the tap as described in [Publish](#5-publish). The workflow does not open
checkout, activate funding accounts, change repository visibility, or publish
the static site.
The `macos-26` runner is Apple silicon; Intel/universal builds are not promised.
[GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

## Launch materials and funding

Open [`Marketing/index.html`](../Marketing/index.html) to review screenshots,
both video cuts, captions, social graphics, copy and sponsorship drafts. The
site's download link points at the published, anonymously downloadable 0.2.0
DMG until the publish step above changes it, and the site is served from
`radeknovis/debagr-site`. Do not copy `Marketing/site/` to the live site before
that step: its screenshots may already show the 0.3.0 interface while its
download is still 0.2.0. Keep the application source private. Funding
activation is explicitly deferred; those links remain in preparation.

Follow [`Marketing/sponsorship/README.md`](../Marketing/sponsorship/README.md)
for the selected GitHub Sponsors and Ko-fi profiles and tiers. Resume account
activation only when the owner requests it. Owner authentication,
identity, payout/tax data, agreement acceptance, and provider approval cannot be
invented. Sponsorship supports development independently of future commercial
licensing; there is no active paid checkout or announced subscription price.
