# Debagr compatibility

Updated 11 November 2026. Applies to Debagr 0.3.0 (build 5), a technical
preview for Apple-silicon Macs.

## What is verified on real hardware

One thing: a remote iPhone install plus an OS-confirmed launch over Tailscale,
on 10 November 2026, with a 0.3.0 candidate build. The details are in
[hardware evidence](DIRECT_DEVICE.md). Everything else in this document is
implemented and covered by automated tests only, unless a row says otherwise.

## Provider support

Tailscale and Headscale have online-device discovery through the Tailscale client.
ZeroTier, NetBird, and WireGuard accept an explicit private VPN IPv4 address in
setup and the CLI. Only Tailscale has remote iPhone install-and-launch
evidence. Headscale, ZeroTier, NetBird, and WireGuard are implemented and
covered by automated tests; they are not verified on real hardware.
See [provider setup and address restrictions](NETWORK_PROVIDERS.md).

## Technical preview

| Capability | Status in 0.3.0 | Supported environment |
| --- | --- | --- |
| Menu-bar Target Device inventory | Implemented and locally verified through `devicectl` plus Bonjour | Apple-silicon Mac. The app's minimum is macOS 13; macOS 13–15 are not verified |
| Managed remote deployment transport | Verified for one iPhone over Tailscale: remote install and OS-confirmed launch. iPad not verified | Apple-silicon Mac, macOS 26 or later; current Xcode; device Wi-Fi and private VPN |
| Multiple iPhone/iPad Bonjour records | Implemented; parser/model tests pass | Local Bonjour-compatible network |
| First-run guide, Launch at Login, About, diagnostics | Implemented; clean-Mac and offline first launch not verified | Packaged macOS app |
| Paired-Mac `.app` install and optional launch | Implemented; automated tests pass, live install requires an unlocked device | Current Xcode and a locally paired physical device |
| Remote invocation | Uses the build server's existing SSH authentication | Any SSH-capable caller; Tailscale optional |
| Mac cable service bridge | Experimental CLI; one iPhone readiness/install verified, launch/debugger pending | Existing Builder pairing, two Macs, Tailscale, trusted SSH, explicit cable endpoint and port |
| Manual TCP/UDP relay lab | Implemented; not a customer promise | macOS 26 or later, Tailscale CLI, explicit peer and port |
| Cross-Mac Xcode or local `devicectl` use | Blocked in the current layer-4 architecture | CoreDevice requires per-Mac pairing and a negotiated link-local IPv6 tunnel |
| Managed relay recovery | Rebuilds unhealthy listeners and refreshes after wake; recovery not verified on hardware | One managed device |

Debagr is not affiliated with or endorsed by Apple or Tailscale. Apple documents
wireless use on the same network and does not document cross-Mac RemotePairing
over a tailnet. Live testing also confirmed that a projected service identity
alone does not transfer another Mac's pairing state.

Managed remote deployment needs macOS 26 or later on the Mac, because it binds
its listeners to an exact local address. macOS 13–15 are not verified for any
capability.

## Known gaps in 0.3.0

None of the following has been verified for this release. Do not rely on them
without your own test.

- Clean-Mac first launch and offline first launch.
- iPad.
- The recovery matrix: restart, sleep and wake, network change, revoked trust,
  and denied Local Network permission.
- VPN providers other than Tailscale.
- macOS 13–15.
- The Homebrew upgrade from 0.2.0 to 0.3.0.
- Cable bridge launch, debugger attachment and reconnect.

## Evidence required before paid access

- A signed device `.app` installs and launches on a current iPhone and iPad
  through Debagr on their paired Build Server.
- The same operations pass when invoked through SSH by a separate Caller.
- Both Target Devices work independently.
- Deployment recovers after app restart, Mac restart, sleep, a locked/offline
  device, network change, and revoked then restored pairing.
- Fresh installation and removal work on clean supported Macs without terminal
  commands.
- Failure messages identify revoked local-network permission, offline Tailscale,
  missing Developer Mode, expired trust, unsupported OS, unavailable device,
  invalid signing, and absent Artifact.

Record exact Mac, macOS, Xcode, device, and iOS/iPadOS versions for every pass.
Require `devicectl` installation success containing the expected bundle ID;
Bonjour visibility and a listed UDID are not proof.
