# Debagr distribution proposal

Research checked 2026-10-11. This is a recommendation, not a published release.

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
| `release-macos-app.sh` requires a Developer ID identity and notary profile; signs the app, creates a DMG, notarizes/staples/assesses it, and writes a checksum | Verify publisher credentials are available and perform a real notarized release; ad-hoc local signing is not evidence of this |
| `release.yml` is manually triggered and uploads workflow artifacts | Publish approved artifacts to a tagged draft/prerelease GitHub Release, then promote deliberately |
| `build-macos-app.sh` builds for its host architecture; the inspected local app is arm64 | Start with an explicitly Apple-silicon-only beta; do not claim Intel or universal support without builds and verification |
| Swift package declares macOS 13 minimum | Publish the actually tested macOS/Xcode/iOS matrix, not merely the deployment target |
| CLI works by absolute app-bundle path; menu reveals the skill folder | Optional Homebrew cask for a lowercase `debagr` on PATH; install the skill explicitly into the chosen client's discovery directory |

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

After the beta passes, an **optional publisher-owned Homebrew tap** can expose
the same signed app and executable. A cask is appropriate for a native macOS
app, and its `binary` artifact can link an executable inside an installed app
into Homebrew's bin directory. [Homebrew package choice](https://docs.brew.sh/Adding-Software-to-Homebrew),
[Cask app and binary artifacts](https://docs.brew.sh/Cask-Cookbook#stanza-binary),
[Publisher-owned taps](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap).

Proposed cask artifacts, not an installed or published cask:

```ruby
app "Debagr.app"
binary "#{appdir}/Debagr.app/Contents/MacOS/Debagr", target: "debagr"
```

The full cask must pin the approved version, DMG URL, checksum, architecture,
and supported macOS requirements. Do not install a separately compiled CLI or
overwrite existing user commands. Homebrew handles the link; users must still
have Homebrew's bin directory on PATH. Initial upgrades can be manual download
or `brew upgrade --cask` once the cask exists; an in-app updater is not needed
for this milestone. [Cask definition](https://docs.brew.sh/Cask-Cookbook),
[Tap maintenance](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap).

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

No publishing, signing-credential setup, Homebrew/global skill installation,
auto-updater, new service, or App Store submission is performed by this proposal.
