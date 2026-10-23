Debagr turns the Mac already paired with your iPhone into a private deployment endpoint for Claude Code, Codex, and your terminal.

- Native macOS settings for device setup and agent onboarding.
- A structured JSON CLI for inventory, readiness, diagnostics, installation, and launch.
- Claude Code and Codex plugin archives with the same deployment workflow.
- Tailscale and Headscale peer discovery; manual private IPv4 entry for ZeroTier, NetBird, and WireGuard.

This is a **technical preview for Apple silicon**. The remote transport requires macOS 26 or later, current Xcode, initial USB pairing and trust, Developer Mode, an unlocked device on Wi-Fi, a private VPN on both endpoints, and Debagr running on the paired Mac. Your signed device `.app` must exist on that Mac. Remote agents use your existing SSH access.

Only Tailscale has prior remote iPhone install-and-launch evidence. iPad and alternative VPN providers await full remote hardware acceptance. Cellular-only operation is unsupported. One managed remote device. Apple pairing stays on its original Mac; devices do not become Xcode destinations on other Macs.

**Download:** choose the versioned Debagr DMG from the attached assets; source-code ZIPs are not the app. Verify the matching SHA-256 file, open the disk image, then drag Debagr to Applications. The release workflow attaches a Developer ID signed, notarized and stapled app and DMG only after the Apple and Gatekeeper gates pass. No security bypass is required.

The publisher-owned Homebrew cask is prepared in `radeknovis/homebrew-debagr`. After its public activation, use `brew install --cask radeknovis/debagr/debagr` to install the same notarized app and its `debagr` CLI link.

Install the matching `debagr-claude-code` or `debagr-codex` plugin ZIP using the included instructions. Agent Tools in Debagr includes the setup steps and a deployment prompt.

Report problems with the exact macOS, Xcode, and iOS versions. Review copied diagnostics and send them only through a private channel. Do not post pairing material or device identifiers.

Updates use manual DMG replacement or `brew upgrade --cask radeknovis/debagr/debagr` after tap activation. There is no Debagr cloud, analytics, active paid checkout, or automatic updater. Sponsorship, when enabled, supports development and does not buy a license or guaranteed support.
