# Debagr compatibility

Updated 22 September 2026.

## Technical preview

| Capability | Status | Supported environment |
| --- | --- | --- |
| Menu-bar Target Device inventory | Implemented and locally verified through `devicectl` plus Bonjour | Apple-silicon Mac, macOS 13 or later |
| Multiple iPhone/iPad Bonjour records | Implemented; parser/model tests pass | Local Bonjour-compatible network |
| First-run guide, Launch at Login, About, diagnostics | Implemented | Packaged macOS app |
| Paired-Mac `.app` install and optional launch | Implemented; automated tests pass, live install requires an unlocked device | Current Xcode and a locally paired physical device |
| Remote invocation | Uses the build server's existing SSH authentication | Any SSH-capable caller; Tailscale optional |
| Manual TCP/UDP relay lab | Implemented; not a customer promise | macOS 26 or later, Tailscale CLI, explicit peer and port |
| Cross-Mac Xcode or local `devicectl` use | Blocked in the current layer-4 architecture | CoreDevice requires per-Mac pairing and a negotiated link-local IPv6 tunnel |
| Automatic per-device routing and recovery | Not implemented | — |
| Mutual Mac authorization and revocation | Not implemented | — |

Debagr is not affiliated with or endorsed by Apple or Tailscale. Apple documents
wireless use on the same network and does not document cross-Mac RemotePairing
over a tailnet. Live testing also confirmed that a projected service identity
alone does not transfer another Mac's pairing state.

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
