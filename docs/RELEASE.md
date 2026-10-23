# Debagr release runbook

Updated 23 October 2026. See [SHIP_STATUS.md](SHIP_STATUS.md) for the current
verification results and unresolved gates. The prepared preview is 0.2.0 for
Apple silicon; managed remote deployment requires macOS 26 or later.

## Publisher credentials

The selected publisher is the personal Apple Developer team **Radek Novak**
(`XBSPGPE6R6`). On 23 October 2026, a **Developer ID Application** certificate
was issued through Apple's portal and imported into the local login Keychain.
Its public key matches the locally generated CSR; its matching private key
remains in Keychain and has not been exported or copied. The certificate expires
on **22 November 2027**.

Release 0.2.0, build 2 was signed with
`Developer ID Application: Radek Novak (XBSPGPE6R6)`. Strict signature and bundle
verification passed, including Hardened Runtime, the Apple certificate chain
and secure timestamp. On 23 October, Apple accepted both app and DMG submissions
without issues. Both tickets were stapled and validated, and both Gatekeeper
assessments reported Notarized Developer ID. The final DMG passed a local
read-only mount/copy, copied-app verification and JSON CLI check. Clean-Mac and
fresh remote-device acceptance remain open. CI signing remains optional.

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

## Local release

1. Complete the hardware and clean-Mac checks below. Verify production website,
   support, privacy, terms, and private security-reporting destinations.
2. Start from a clean commit tagged `v0.2.0`. Keep previous signed artifacts.
3. Run with the actual identity and confirmed URLs:

```sh
VERSION=0.2.0 \
BUILD_NUMBER=2 \
CODESIGN_IDENTITY="Developer ID Application: Radek Novak (XBSPGPE6R6)" \
NOTARY_PROFILE=debagr-notary \
./scripts/release-macos-app.sh
```

Set `DEBAGR_WEBSITE_URL` and `DEBAGR_SUPPORT_URL` to the verified production
HTTPS URLs if available. `NOTARY_KEYCHAIN` optionally selects a dedicated
Keychain. The script refuses nonnumeric bundle versions/build numbers, dirty
worktrees, non-Developer-ID identities, and overwriting an existing versioned DMG.
`ALLOW_DIRTY_RELEASE=1` is only for a deliberate local rehearsal; never publish
such a build as a reproducible tagged release.

The script lints, tests, builds and verifies the bundle; notarizes the app ZIP;
retrieves Apple's result and log; requires `Accepted`; staples and validates the
app and checks Gatekeeper; packages it with an Applications link; signs,
notarizes and staples the DMG; assesses that image; and writes a portable SHA-256
file. The final DMG is moved into `dist/` only after those gates pass.
[Apple's custom workflow and stapling guidance](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Review both Apple logs even on success. Submission records and logs stay in
`dist/Debagr-0.2.0-{app,dmg}-{submission,notary-log}.json`; they are diagnostic
artifacts, not public release assets. The release safety test uses mocked Apple
tools to check sequencing and failures; it cannot establish real notarization.

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
Configure repository or environment variables `DEBAGR_WEBSITE_URL` and
`DEBAGR_SUPPORT_URL` only for verified destinations.

After the final commit and tag are pushed, invoke **Release** from the tag,
not a branch. For example, from the approved checkout:

```sh
gh workflow run release.yml --ref v0.2.0 -f version=0.2.0 -f build_number=2
```

The workflow enforces the tag/version match, checks required credentials, runs
release safety checks, builds the notarized app/DMG and plugin ZIPs, saves
artifacts and logs, and creates a **draft prerelease**. Review the download and
acceptance evidence before publishing. It does not open checkout, activate
funding accounts, change repository visibility, or publish the static site.
The `macos-26` runner is Apple silicon; Intel/universal builds are not promised.
[GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

## Homebrew cask and binary channel

The separate private [homebrew-debagr repository](https://github.com/radeknovis/homebrew-debagr)
contains the pinned cask and a draft prerelease with the accepted DMG/checksum
and matching plugins. Style, strict audit and temporary local
install/reinstall/uninstall passed, including the CLI link and installed app's
signature, ticket and Gatekeeper assessment. The private release download
round-trip checksum passed. Public download and cask activation remain pending.
See [DISTRIBUTION.md](DISTRIBUTION.md) for the maintenance and publication checks.
Do not change the app source repository's visibility to activate this channel.

## Acceptance evidence

Record exact Mac, macOS, Xcode, device, iOS/iPadOS, network/provider, artifact
checksum, and each result. Private device IDs and pairing metadata belong in a
private test record, not marketing assets or public issue reports.

- Download the published candidate and verify the SHA-256 from its directory.
- On a clean supported Mac, mount the DMG, drag Debagr to Applications and launch.
- Verify the expected publisher, `xcrun stapler validate` on the copied app and
  image, and Gatekeeper acceptance. Check an offline first launch as well.
- Complete setup, local-network permission, discovery, Agent tools, copy prompt,
  Launch at Login, About/version, diagnostics, support links, and uninstall.
- With USB disconnected and the iPhone on another Wi-Fi network, require
  authenticated readiness, then an install result confirming the expected bundle
  ID and a separate successful launch. Repeat through SSH from another computer.
- Repeat with iPad before claiming it validated; repeat for each VPN provider
  before promoting its hardware support from implemented to verified.
- Check app/Mac restart, sleep/wake, locked/offline device, network changes,
  revoked/restored trust and denied local-network permission. Record failures.
- Keep unsupported cellular-only operation explicit and one-device scope visible.

Local mount/copy, signing, notarization and Gatekeeper checks have passed for
0.2.0 build 2. They do not establish clean-Mac first launch, offline acceptance,
or fresh device installation and launch.

## Launch materials and funding

Open [`Marketing/index.html`](../Marketing/index.html) to review screenshots,
both video cuts, captions, social graphics, copy and sponsorship drafts. The
download link stays in preparation until the actual notarized installer is
published and anonymously downloadable. The notarized candidate exists locally;
its separate `radeknovis/homebrew-debagr` cask/binary repository is still private
and prepared for publication review. Keep the application source private.
Funding activation is explicitly deferred; those links can remain in preparation
when the app ships.

Follow [`Marketing/sponsorship/README.md`](../Marketing/sponsorship/README.md)
for the selected GitHub Sponsors and Ko-fi profiles and tiers. Resume account
activation only when the owner requests it. Owner authentication,
identity, payout/tax data, agreement acceptance, and provider approval cannot be
invented. Sponsorship supports development independently of future commercial
licensing; there is no active paid checkout or announced subscription price.
