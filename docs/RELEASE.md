# Debagr release runbook

## One-time account setup

1. Enroll the legal publisher in the Apple Developer Program.
2. Register `com.debagr.app` and create a Developer ID Application certificate.
3. Store notarization credentials in Keychain:

   ```sh
   xcrun notarytool store-credentials debagr-notary
   ```

4. Choose the production website, support, security, privacy, and terms URLs.
5. Create the merchant-of-record product only after the paid-launch gate in
   [`COMPATIBILITY.md`](COMPATIBILITY.md) passes.
6. Configure `Marketing/site/config.js` with the live checkout URL.

## Build

Start from a clean tagged commit on the supported macOS/Xcode toolchain. Then:

```sh
VERSION=1.0.0 \
BUILD_NUMBER=42 \
CODESIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)" \
NOTARY_PROFILE="debagr-notary" \
DEBAGR_WEBSITE_URL="https://example.com/debagr" \
DEBAGR_SUPPORT_URL="https://example.com/debagr/support" \
./scripts/release-macos-app.sh
```

The command builds and tests through the repository workflow, signs with
Hardened Runtime and a secure timestamp, creates a DMG, submits it to Apple,
staples and validates the ticket, checks Gatekeeper, and writes a SHA-256 file.

## Release acceptance

- Verify the DMG checksum after downloading it from the production host.
- On a clean Mac, open the DMG, drag Debagr to Applications, and launch it.
- Confirm Gatekeeper shows the expected publisher and no bypass is required.
- Complete first-run onboarding, local-network permission, device discovery,
  Launch at Login, About/version, Copy Diagnostics, support link, and uninstall.
- Run the full real-hardware matrix and record exact versions and evidence.
- Confirm the website shows requirements, limitations, annual price, refund
  policy, privacy, terms, and the exact notarized version before opening checkout.
- Keep the previous notarized DMG available for rollback.

The current machine has no usable Developer ID Application identity or notary
profile, so local ad-hoc packaging can be verified but a sellable notarized DMG
cannot be produced without publisher credentials.
