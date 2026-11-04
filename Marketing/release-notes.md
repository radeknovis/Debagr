Debagr turns the Mac already paired with your iPhone into a private deployment endpoint for Claude Code, Codex, and your terminal.

- Native macOS settings for device setup and agent onboarding.
- A structured JSON CLI for inventory, readiness, diagnostics, installation, and launch.
- Claude Code and Codex plugin archives with the same deployment workflow.
- Tailscale and Headscale peer discovery; manual private IPv4 entry for ZeroTier, NetBird, and WireGuard.

This is a **technical preview for Apple silicon**. The remote transport requires macOS 26 or later, current Xcode, initial USB pairing and trust, Developer Mode, an unlocked device on Wi-Fi, a private VPN on both endpoints, and Debagr running on the paired Mac. Your signed device `.app` must exist on that Mac. Remote agents use your existing SSH access.

Only Tailscale has prior remote iPhone install-and-launch evidence, recorded on an earlier build. Build 0.2.0 has not yet been re-verified with a fresh remote install and launch or with a first launch on a clean Mac. iPad, alternative VPN providers, the recovery matrix and Homebrew upgrades between versions await testing. Cellular-only operation is unsupported. One managed remote device. Apple pairing stays on its original Mac; devices do not become Xcode destinations on other Macs.

**Download:** choose the versioned Debagr DMG from the attached assets; source-code ZIPs are not the app. Verify the matching SHA-256 file, open the disk image, then drag Debagr to Applications. The app and DMG are Developer ID signed, notarized and stapled, and both passed Apple notarization and Gatekeeper checks. No security bypass is required.

Or use `brew install --cask radeknovis/debagr/debagr` to install the same notarized app and its `debagr` CLI link.

Install the matching `debagr-claude-code` or `debagr-codex` plugin ZIP using the included instructions. Agent Tools in Debagr includes the setup steps and a deployment prompt.

Report problems in [Issues](https://github.com/radeknovis/homebrew-debagr/issues) with the exact macOS, Xcode, and iOS versions. Do not post pairing material, device identifiers, hostnames, or diagnostics publicly. Send security and privacy reports, and diagnostics when asked, through [private vulnerability reporting](https://github.com/radeknovis/homebrew-debagr/security/advisories/new).

Updates use manual DMG replacement or `brew upgrade --cask radeknovis/debagr/debagr`. There is no Debagr cloud, analytics, active paid checkout, or automatic updater. Sponsorship, when enabled, supports development and does not buy a license or guaranteed support.

Website: https://radeknovis.github.io/debagr-site/
