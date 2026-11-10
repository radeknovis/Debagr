# Historical distribution evidence

Snapshot recorded 4 November 2026; see [current distribution scope](DISTRIBUTION.md).

# Debagr distribution

Updated 4 November 2026. The 0.2.0 technical preview is public through the
Homebrew tap and its GitHub release; the app source stays private.

## Smallest useful route

Ship one **Developer ID-signed, notarized DMG on GitHub Releases**, containing
the menu-bar app, its existing CLI, and the client-neutral deployment skill.
Reuse the existing DMG pipeline rather than adding a second ZIP pipeline.
Apple supports notarizing disk images containing apps; GitHub Releases support
versioned binary assets attached to tags. [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases).

Humans download the DMG, drag Debagr into Applications, and configure their
paired iPhone once. Agents invoke the same app's JSON CLI on the Build Server,
locally or through the user's existing SSH alias. Keep trust, Developer Mode,
Tailscale login, and device-specific profiles out of the installer.

Publish `Debagr-VERSION.dmg` and its SHA-256 alongside concise requirements,
known limitations, setup instructions, and the previous release for rollback.
Do not confuse GitHub's automatic source-code ZIP with the signed application.
[GitHub release assets and source archives](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases).

## Already implemented versus release gaps

| Existing repository implementation | Still needed before distribution |
| --- | --- |
| App bundle contains menu UI, JSON CLI, and `Resources/Skills/debagr-deploy` | Fresh end-to-end install/launch and visual UI acceptance of this milestone |
| `release-macos-app.sh` requires a Developer ID identity and notary profile; signs the app, creates a DMG, notarizes/staples/assesses it, and writes a checksum | 0.2.0 build 2 passed app/DMG notarization, stapling and local Gatekeeper; clean-Mac acceptance remains open |
| `release.yml` is manually triggered and uploads workflow artifacts | Publish approved artifacts to a tagged draft/prerelease GitHub Release, then promote deliberately |
| `build-macos-app.sh` builds for its host architecture; the inspected local app is arm64 | Start with an explicitly Apple-silicon-only beta; do not claim Intel or universal support without builds and verification |
| Swift package declares macOS 13 minimum | Publish the actually tested macOS/Xcode/iOS matrix, not merely the deployment target |
| CLI works by absolute app-bundle path; menu reveals the skill folder | Homebrew cask is staged and locally tested; public activation remains pending; install the skill explicitly into the chosen client's discovery directory |

Inspect the accepted notarization log, not only the submit exit status. Apple
creates tickets for the DMG and nested app; stapling lets Gatekeeper verify
without fetching a ticket online. The release script now notarizes and staples
the app before packaging, then signs, notarizes, staples, and assesses the DMG.
It retains both submission results and Apple logs and refuses rejected results
and artifact overwrites. CI creates a draft prerelease. A ZIP, if ever added, must
contain already-stapled items because ZIPs cannot themselves be stapled.
[Apple custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## AI-friendly installation, without another binary

For direct DMG installs, agents can use the stable absolute path immediately:

```sh
/Applications/Debagr.app/Contents/MacOS/Debagr --devices --json
```

No shell profile edit, privileged helper, or PATH mutation is required.
For SSH, use the absolute remote path too: noninteractive shells need not load
the user's interactive PATH setup. Run as the paired user, not root.

A **publisher-owned Homebrew cask** is published in the separate public
[`radeknovis/homebrew-debagr`](https://github.com/radeknovis/homebrew-debagr)
repository. Its 0.2.0 prerelease contains the notarized DMG, checksum and
matching plugin archives. The app source remains private. The cask pins 0.2.0
and the final DMG SHA-256, requires Apple silicon and macOS 26 or later, installs
`Debagr.app`, and links its existing executable as lowercase `debagr`.
[Cask definition](https://github.com/radeknovis/homebrew-debagr/blob/main/Casks/debagr.rb),
[Homebrew cask documentation](https://docs.brew.sh/Cask-Cookbook).

Install with:

```sh
brew install --cask radeknovis/debagr/debagr
```

Homebrew style and strict audit passed. Install, reinstall and uninstall were
tested in a temporary Applications directory using a local file URL for the
exact final notarized DMG. The CLI symlink, JSON inventory, strict signature,
stapled ticket and Gatekeeper acceptance passed after install and replacement.
The temporary cask, link, trust entry and tap were removed. The uploaded draft
DMG was downloaded with authenticated GitHub access and its checksum matched.
After publication on 4 November 2026, an anonymous download of the release DMG
matched its checksum, and `brew install --cask` from the public tap into a
temporary Applications directory passed the same signature, ticket, Gatekeeper
and JSON checks before uninstall and untap. `brew audit --cask --strict --online`
reports two expected findings: the release is a GitHub prerelease, and the
cask's macOS 26 floor is deliberately above the app's macOS 13 minimum.
A version-to-version upgrade has not been tested.

For each release, update the cask's `version` and `sha256` from the final,
notarized/stapled DMG. Keep the versioned URL immutable and retain the previous
release for rollback. Use `brew style` and `brew audit --cask --strict`, then
verify the public URL and install/replacement/uninstall path before promoting.
For temporary local acceptance, set `HOMEBREW_NO_AUTO_UPDATE=1`,
`HOMEBREW_NO_INSTALL_CLEANUP=1` and `HOMEBREW_NO_AUTOREMOVE=1` to avoid unrelated
package maintenance. Do not overwrite an existing app or `debagr` command.
[Tap maintenance](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap).

The cask has no `zap` stanza and preserves profiles, pairing records, preferences
and deployment receipts. It does not install skills globally. Homebrew handles
the CLI link; its bin directory must be on PATH. Updates can use manual DMG
replacement or `brew upgrade --cask radeknovis/debagr/debagr`;
an in-app updater is not required for this preview.

For either upgrade path, quit Debagr before replacing its app bundle and relaunch
afterward. Its owned relay stops during the upgrade; do not replace the executable
under a running menu-bar process and imply the new version is active.

The skill is already shipped at
`/Applications/Debagr.app/Contents/Resources/Skills/debagr-deploy/SKILL.md` and
in [`Skills/debagr-deploy`](../Skills/debagr-deploy). Installation of the app
does not make a skill discoverable in every AI client. Use the menu's **Show AI
Deployment Skill…**, copy the enclosing folder to that client's documented
skill directory, and supply the Build Server SSH alias. Keep this explicitly
client-neutral; don't silently modify global agent configuration. The skill
version should match the app version. See [AI deployment setup](AI_DEPLOYMENT.md).

## Phased acceptance

1. **Checkpoint and technical beta:** retain the implementation commit. Verify
   the packaged menu UI, configuration/import, connect/disconnect, relaunch,
   and a real signed app install plus OS-confirmed launch on remote Wi-Fi.
   Tests and JSON smoke checks alone do not satisfy this gate.
2. **Small invited beta:** produce a notarized Apple-silicon DMG and install its
   downloaded copy on a clean supported Mac. Confirm Gatekeeper needs no bypass,
   first-run permissions, CLI discovery/readiness/deploy/diagnose, skill setup,
   Wi-Fi recovery, uninstall, and rollback. Share through a private repository
   or another access-controlled host if access must actually be restricted;
   a prerelease label is a channel label, not access control. GitHub release
   visibility follows repository read access. [GitHub release access](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases).
3. **Public beta:** publish the verified hardware/toolchain matrix, known issues,
   versioned assets, and support route. Add the Homebrew cask only when its
   install/upgrade/uninstall behavior has been tested. Paid/general availability
   remains subject to [release acceptance](RELEASE.md) and a refreshed
   [compatibility matrix](COMPATIBILITY.md).

Explicit limits: one remote device, the original paired Build Server user's
logged-in session, Tailscale at both endpoints, and remote **Wi-Fi**. Cellular
RemotePairing remains unsupported. Do not advertise an iPhone companion app,
zero-touch Apple trust, universal Mac support, or tested iPad support.

The cask/binary repository, the 0.2.0 prerelease and the
[launch site](https://radeknovis.github.io/debagr-site/), served from the public `radeknovis/debagr-site`
repository, are public. The app source remains private. No global skill
installation, auto-updater, new service or App Store submission has occurred.
