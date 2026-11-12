# Debagr distribution

The published app is the 0.3.0 build 5 technical preview in the public
[Homebrew tap and releases](https://github.com/radeknovis/homebrew-debagr/releases).
The source repository is private. See the [compatibility matrix](COMPATIBILITY.md),
[release runbook](RELEASE.md), and [shipping status](SHIP_STATUS.md).

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

Homebrew links `debagr` and preserves connection profiles. From 0.3.0, the
linked `debagr` finds the app's bundled USBIPProbe helper when it is run through
that symlink. Uninstalling the app does not revoke Apple pairing or uninstall
deployed apps. See [privacy and removal](PRIVACY.md).

There is no automatic updater. The upgrade from 0.2.0 to 0.3.0, by DMG or by
Homebrew, has not been tested; the runbook lists it as a post-notarization check.

## Release boundaries

Publish one Developer ID-signed, notarized and stapled DMG, checksum and matching
plugin ZIPs. Keep immutable versioned URLs and the previous release for rollback.
Update the public cask only from the final DMG version and checksum. Never use
GitHub's source archive as the application installer.

Anonymous download and temporary Homebrew install checks were recorded for
0.2.0. Those historical results do not validate 0.3.0, a clean Mac, a
version-to-version upgrade or a new hardware deployment. See the
[historical distribution record](DISTRIBUTION_HISTORY.md) and [current audit status](AUDIT_FIXES.md).
0.3.0 has pinned CI tools and automated packaging checks. Its app and DMG passed notarization and Gatekeeper assessment. The owner waived pre-release hardware acceptance for its known gaps on
11 November 2026, as for 0.2.0, so 0.3.0 is published with those gaps listed in
its release notes.

The [free preview licence](EULA.md) permits personal/internal evaluation and
prohibits redistribution. The [paid terms](PAID_TERMS_DRAFT.md) remain a draft.
