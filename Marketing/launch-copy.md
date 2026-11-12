# Debagr launch copy

Prepared for the technical preview. 0.2.0 was published on 4 November 2026.
0.3.0 was published on 12 November 2026. Preview links point at https://radeknovis.github.io/debagr-site/.
Funding links stay bracketed until activation; never post these drafts with
placeholder links.

## Positioning

**Headline:** Your Mac stays home. Your next build comes with you.

**Tagline:** From prompt to pocket.

**One sentence:** Debagr lets Claude Code, Codex, and terminal users install and
launch signed iPhone builds through the Mac already paired with their device,
even across separate Wi-Fi networks.

**Short product description:** A native macOS app and structured JSON CLI for
remote device deployment through your paired Mac and private VPN. Debagr checks
readiness, installs your signed device .app, and confirms launch. Includes Claude
Code and Codex deployment plugins. Technical preview: one managed remote device,
Wi-Fi required, cellular-only unsupported.

## X / Mastodon short post

Your Mac stays home. Your next build comes with you.

Debagr lets Claude Code, Codex, or your terminal deploy signed iPhone builds
through your paired Mac on another Wi-Fi network.

Technical preview. VPN + Wi-Fi required. No cellular-only support.

https://radeknovis.github.io/debagr-site/

Attach `video/debagr-promo-landscape.mp4` or `social/launch-card.png`. Shorten or
split the text to fit the destination's current limits before posting.

## LinkedIn / longer launch post

I built Debagr for the moment when your build Mac is at home and the iPhone you
want to test is in your hand somewhere else.

Pair the device with your Mac once. Connect both endpoints through a private
VPN. Then ask Claude Code, Codex, or your terminal to check readiness, install
your signed device app, and confirm launch through that same Mac.

Debagr is a native macOS app with a JSON CLI and agent plugins. It keeps Apple's
pairing on its original Mac and uses your existing SSH access for remote calls.

This is a technical preview, with clear limits: one managed remote device,
Wi-Fi required, and cellular-only operation unsupported. Tailscale has prior
remote iPhone install-and-launch evidence; the broader provider and iPad
hardware matrix is still being tested.

Preview and setup: https://radeknovis.github.io/debagr-site/
Optional support for testing and compatibility work: [Verified funding link]

## 0.3.0 update post

Debagr 0.3.0 technical preview is out.

- Remote deployment reports problems more clearly: working readiness deadlines,
  Apple's own error details, and a relay that rebuilds unhealthy listeners after wake.
- New CLI commands list installed apps and launch without reinstalling. An
  optional local MCP interface runs over stdin and stdout, with no network listener.
- Setup starts with a guided flow for a device your Mac is already paired with.
- Experimental: link two Macs as Builder and Client and forward USB for a first
  pairing. It needs separately installed USB tools and has no hardware acceptance yet.

Still a technical preview: one managed remote device, VPN + Wi-Fi required, no
cellular-only support.

`brew upgrade --cask radeknovis/debagr/debagr`
https://radeknovis.github.io/debagr-site/

## Developer community post

**Title:** Debagr: deploy to a remote iPhone through the Mac it is already paired with

Debagr is a native macOS menu-bar tool with a JSON CLI and Claude Code/Codex
plugins. Its narrow job is to make an existing paired Mac install and launch a
signed device app when invoked locally or through SSH. The phone can be on
another Wi-Fi network, connected through a private VPN.

It does not transfer pairing state or turn the phone into an Xcode destination
on another Mac. Initial USB pairing, trust, Developer Mode, current Xcode, a
signed device build on the Mac, and an unlocked Wi-Fi device are required.
Cellular-only operation is unsupported.

I would particularly value reproducible reports about setup, recovery after
network changes, and clarity of failure messages. Please include OS/Xcode
versions and redact personal device data.

https://radeknovis.github.io/debagr-site/ · Requirements: https://radeknovis.github.io/debagr-site/#requirements

Share only in communities that permit author promotion and after reviewing the
community's current rules. Do not mass-post, message users, or imply community
endorsement. The source is currently private; do not call Debagr open source.

## Sponsor announcement

Help the next build travel further.

Optional sponsorship supports Debagr compatibility work, hardware testing,
documentation, and signed releases. It does not buy a license, guaranteed
support, or a delivery date.

[Verified GitHub Sponsors link] · [Verified one-time support link]

Publish this only when the linked payment pages are verified and active.

## Video storyboard and optional voiceover

The shipped videos are silent by design; all core copy appears on screen and
English WebVTT captions are included. No music, stock footage, or voice rights
need to be cleared.

| Time | Visual | Optional voiceover |
| --- | --- | --- |
| 0–6 s | Native setup screen | Your Mac stays home. Your next build comes with you. |
| 6–12 s | Setup and private VPN | Pair once. Connect through your private VPN. Take your iPhone to another Wi-Fi network. |
| 12–18 s | Native Agent tools | Ask Claude Code, Codex, or your terminal to check readiness, install, and confirm launch. |
| 18–24 s | Agent tools and support invitation | Debagr. From prompt to pocket. Follow development and support the next milestone. |

Every scene discloses technical-preview status, sample UI data, the Wi-Fi
requirement, and the cellular-only limit. Videos illustrate the workflow;
they are not a new recording of a successful hardware deployment.

## Claims checklist

Use: paired Mac, private VPN, separate Wi-Fi networks, signed device builds,
structured JSON, prior Tailscale/iPhone evidence, technical preview, notarized
download and Homebrew install. For
0.3.0 the hardware evidence is one remote iPhone install and OS-confirmed
launch over Tailscale on 10 November 2026, with a pre-release build.

Do not claim: cellular support, Apple endorsement, transparent cross-Mac Xcode,
validated iPad or alternative VPN deployments, Intel/universal support, remote
deployment on macOS 13 to 15, active funding pages, a clean-Mac or offline
first-launch result, a tested Homebrew upgrade, a completed recovery matrix, or
hardware acceptance of USB/IP, VirtualHere or two-Mac Builder and Client
linking, until that specific result has been verified and recorded. Never name
the app used in a hardware test, its bundle identifier or an employer.
