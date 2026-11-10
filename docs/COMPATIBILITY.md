# Debagr compatibility

Updated 10 November 2026. Published binary: 0.2.0; audit source changes are unreleased.

## Provider support

Tailscale and Headscale have online-device discovery through the Tailscale client.
ZeroTier, NetBird, and WireGuard accept an explicit private VPN IPv4 address in
setup and the CLI. These alternative-provider paths are implemented and covered
by automated tests; real-hardware remote deployment acceptance remains pending.
Only Tailscale has prior remote iPhone install-and-launch evidence.
See [provider setup and address restrictions](NETWORK_PROVIDERS.md).

## Technical preview

| Capability | Status | Supported environment |
| --- | --- | --- |
| Menu-bar Target Device inventory | Implemented and locally verified through `devicectl` plus Bonjour | Apple-silicon Mac, macOS 13 or later |
| Managed remote deployment transport | Implemented; prior Tailscale/iPhone evidence, fresh acceptance pending | Apple-silicon Mac, macOS 26 or later; current Xcode; device Wi-Fi and private VPN |
| Multiple iPhone/iPad Bonjour records | Implemented; parser/model tests pass | Local Bonjour-compatible network |
| First-run guide, Launch at Login, About, diagnostics | Implemented | Packaged macOS app |
| Paired-Mac `.app` install and optional launch | Implemented; automated tests pass, live install requires an unlocked device | Current Xcode and a locally paired physical device |
| Remote invocation | Uses the build server's existing SSH authentication | Any SSH-capable caller; Tailscale optional |
| Manual TCP/UDP relay lab | Implemented; not a customer promise | macOS 26 or later, Tailscale CLI, explicit peer and port |
| Cross-Mac Xcode or local `devicectl` use | Blocked in the current layer-4 architecture | CoreDevice requires per-Mac pairing and a negotiated link-local IPv6 tunnel |
| Managed relay recovery | Rebuilds unhealthy listeners and refreshes after wake; hardware recovery acceptance pending | One managed device |
| Mutual Mac authorization and revocation | Not implemented | — |

Debagr is not affiliated with or endorsed by Apple or Tailscale. Apple documents
wireless use on the same network and does not document cross-Mac RemotePairing
over a tailnet. Live testing also confirmed that a projected service identity
alone does not transfer another Mac's pairing state.

The source branch uses requiredLocalEndpoint without a macOS 26 API guard.
This does not lower the advertised remote support floor: macOS 13–15 runtime
acceptance remains unverified. The shared listener, native Bonjour, new CLI
recovery tools and local MCP endpoint pass local automated checks; no new
remote-device acceptance is implied.

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
