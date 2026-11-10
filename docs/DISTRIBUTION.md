# Debagr distribution

The published app is the 0.2.0 technical preview in the public
[Homebrew tap and releases](https://github.com/radeknovis/homebrew-debagr/releases).
The source repository is private. Source-branch audit fixes are not yet in that
published binary. The [compatibility matrix](COMPATIBILITY.md) owns support claims;
the [release runbook](RELEASE.md) owns signing and release acceptance.

## Install and update

```sh
brew install --cask radeknovis/debagr/debagr
brew upgrade --cask radeknovis/debagr/debagr
```

Or download the versioned DMG and SHA-256 from Releases, check the checksum and
copy Debagr.app to Applications. Quit Debagr before replacing its bundle.
The CLI is also inside `Debagr.app/Contents/MacOS/Debagr`; run it as the user who
owns the Apple pairing. The app and its bundled instructions do not configure
SSH, VPN accounts, signing or Apple trust. Follow the [setup guide](../Marketing/site/setup.html).

Homebrew links `debagr` and preserves connection profiles. Uninstalling the app
does not revoke Apple pairing or uninstall deployed apps. See [privacy and removal](PRIVACY.md).

## Release boundaries

Publish one Developer ID-signed, notarized and stapled DMG, checksum and matching
plugin ZIPs. Keep immutable versioned URLs and the previous release for rollback.
Update the public cask only from the final DMG version and checksum. Never use
GitHub's source archive as the application installer.

Anonymous download and temporary Homebrew install checks were recorded for
0.2.0. Those historical results do not validate this source branch, a clean Mac,
a version-to-version upgrade or a new hardware deployment. See the
[historical distribution record](DISTRIBUTION_HISTORY.md) and [current audit status](AUDIT_FIXES.md).
The current source branch has pinned CI tools and automated packaging checks;
account-bound notarization, clean-Mac acceptance and hardware recovery still
need their own evidence before publishing an updated binary.

The [free preview licence](EULA.md) permits personal/internal evaluation and
prohibits redistribution. The [paid terms](PAID_TERMS_DRAFT.md) remain a draft.
