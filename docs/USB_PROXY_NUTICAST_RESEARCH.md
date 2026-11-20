# Nuticast USB Sharing: reliability research

> Historical evidence. Current source includes the [paired cable bridge](CABLE_SHARING.md) and [experimental raw USB/IP setup](usbip.md).

Checked 13 November 2026. Primary sources only. No Nuticast installation, execution, or hardware validation; no application code changed.

The user subsequently supplied `Nuticast.app.zip`. Static binary findings below extend the public-source investigation; they do not constitute source review or runtime validation.

## Source availability and verified public files

**The actual USB proxy source was not publicly accessible in the inspected first-party repositories.** The author explicitly labels Nuticast.app and the `nuticast` command proprietary ([Codex plugin README, lines 150–153](https://github.com/webwarrior06/nuticast-codex-plugin/blob/5d359c85dc3804a3cf16423de521c581d2284d33/README.md#L150-L153)). This is stronger evidence than merely failing to find a repository, but does not prove that no source exists elsewhere.

The [author's public repository API](https://api.github.com/users/webwarrior06/repos?per_page=100&type=owner) returned 14 repositories. Inspected complete trees for the three Nuticast-related repositories and their release lists (all empty):

| Repository / pinned commit | What is actually public and verified |
| --- | --- |
| [homebrew-tap @ c079ada720a684ac2882758932d0f2c63af72189](https://github.com/webwarrior06/homebrew-tap/tree/c079ada720a684ac2882758932d0f2c63af72189) | Only README and cask. [Casks/nuticast.rb:1–13](https://github.com/webwarrior06/homebrew-tap/blob/c079ada720a684ac2882758932d0f2c63af72189/Casks/nuticast.rb#L1-L13) downloads a prebuilt DMG (`latest`, `no_check`), installs the app, and exposes its bundled helper. It contains no proxy logic. |
| [nuticast-codex-plugin @ 5d359c85dc3804a3cf16423de521c581d2284d33](https://github.com/webwarrior06/nuticast-codex-plugin/tree/5d359c85dc3804a3cf16423de521c581d2284d33) | Plugin metadata, assets, documentation, and skill. [.mcp.json:1–10](https://github.com/webwarrior06/nuticast-codex-plugin/blob/5d359c85dc3804a3cf16423de521c581d2284d33/.mcp.json#L1-L10) launches the proprietary helper with `mcp`, setting startup/tool timeouts to 30/300 seconds. This verifies configuration, not server behavior. |
| [nuticast-claude-plugin @ 0bfd13baaace64c9ed25af674a4da3fca9c71b07](https://github.com/webwarrior06/nuticast-claude-plugin/tree/0bfd13baaace64c9ed25af674a4da3fca9c71b07) | Metadata, assets, documentation, and skill. [.mcp.json:1–8](https://github.com/webwarrior06/nuticast-claude-plugin/blob/0bfd13baaace64c9ed25af674a4da3fca9c71b07/.mcp.json#L1-L8) likewise invokes the bundled helper; no proxy implementation. |

**No reconnect, identity matching, discovery, bind, or tunnel mechanism is source-code verified.** Public skill text is a documented operating contract, not the implementation behind its tools.

## Product documentation claims

| Area | First-party claim and evidence boundary |
| --- | --- |
| Transport / pairing | Forwards RemotePairing and CoreDevice network services offered over the cable, rather than raw USB. Requires prior pairing with the Xcode Mac. Phone Wi-Fi/VPN is unnecessary on this route; computers must reach each other. One iPhone per sharing Mac. These are vendor claims, not reproduced results. [USB Sharing: architecture, limitations, pairing FAQ](https://www.nuticast.com/usb-sharing). |
| Bind restrictions | Host reportedly listens only on the selected address; RemotePairing still requires the Xcode Mac's pairing identity. LAN exposure receives a warning; mesh VPN recommended. No public implementation establishes enforcement for every listener or authentication of the host-control protocol. [USB Sharing: safety FAQ](https://www.nuticast.com/usb-sharing). |
| Selection / readiness | Select a local or saved phone, assign a USB-host address, then Check. Saving with no connected phone is permitted. Host reports absent phone versus debugging service answering with phone name/port. Requires data cable, unlock/Trust and Developer Mode. Exact stable identifier and mismatch handling are undocumented. [Setup: parts 1–4](https://www.nuticast.com/usb-sharing/setup). |
| Control / reconnect | Host control port is **48999**. App sharing and CLI `nuticast share` conflict on that port; CLI offers `--listen <address>`. Sharing resumes when the app starts. Cable/host-return recovery is claimed after reconnect/unlock and host response; retry policy and existing-session survival are unspecified. [Setup: terminal and troubleshooting](https://www.nuticast.com/usb-sharing/setup). |
| Port discovery / dynamic tunnels | Author says host finds RemotePairing and forwards each tunnel port requested by Xcode. No algorithm, request framing, remapping, teardown, or rediscovery timing is public. [Author's USB article: “A route that skips USB forwarding”](https://www.nuticast.com/blog/virtualhere-usb-network-gate-xcode). General architecture docs describe `_remotepairing._tcp` replay and on-demand tunnel ports **55000–58000**; do not assume this proves USB-host allocation details. [How it works: under the hood](https://www.nuticast.com/how-it-works). |
| Recovery limits / probes | General troubleshooting says `Error` does **not** retry itself. IP/VPN changes restart active bridges; wake errors can require manual restart. Scan port finds/saves a changed service port and distinguishes wrong service from unreachable device; a full scan may take minutes. This is documented mainly for Remote Wi-Fi, not a verified USB rediscovery loop. [Troubleshooting: bridge errors, statuses, network changes](https://www.nuticast.com/troubleshooting). |

The USB recovery promise therefore does not establish recovery from every terminal error or preservation of an LLDB session. Windows setup additionally describes Apple Devices/CoreDeviceProxy and installer-created firewall rules ([setup: Windows](https://www.nuticast.com/usb-sharing/setup)). No evidence here supports a blanket “no privileges required” statement.

## Public operating contracts and useful failure history

- [Codex skill:8–12, 26](https://github.com/webwarrior06/nuticast-codex-plugin/blob/5d359c85dc3804a3cf16423de521c581d2284d33/skills/nuticast/SKILL.md#L8-L12) instructs exact saved-name selection, explicit choice among devices, waiting for `ready: true` and an `id=<UDID>` destination, no duplicate bridge, and stop/restart on `advertisement_lost`. It warns that opening the GUI removes CLI Bonjour records. These instructions expose useful failure categories; they do not verify the readiness probe's internals. [README:74–85](https://github.com/webwarrior06/nuticast-codex-plugin/blob/5d359c85dc3804a3cf16423de521c581d2284d33/README.md#L74-L85) documents Xcode enumeration, diagnosis that saves a moved port, and ensure-ready tools.
- [Changelog](https://www.nuticast.com/changelog): 1.0.8 claims alternate-port retry after collision; 1.0.10 fixes same-name devices being mixed across networks; 1.0.11 recovers temporary renames; 1.0.12 fixes an active-but-invisible port collision; 1.0.14 handles Ethernet/interface selection; 1.0.16 detects missing Bonjour advertisements. These historical claims identify test cases, not demonstrated USB guarantees. The fetched changelog ends at 1.0.18 (22 October), before the November USB docs; it supplies no USB implementation version/commit.

## Recommendations for Debagr (proposals, not Nuticast internals)

1. Keep device identity separate from display name and host address. Pin the intended paired device; reject a different phone after replug, and test duplicate names and renames.
2. Separate host reachable, device present, RemotePairing service responsive, authenticated tunnel established, Xcode available, and install/launch proven. A TCP listener or live bridge process alone must not establish readiness.
3. On host/cable/interface return, rediscover endpoints and invalidate old tunnel forwards. Use one recovery owner with bounded backoff, cancellation, and explicit terminal errors. Test changed RemotePairing/tunnel ports, host restart, sleep/wake, VPN address change, and locked/untrusted devices.
4. Bind control and data listeners to the selected private address; inspect actual sockets during tests. Treat control-plane authentication and permitted forwarding targets as separate requirements from Apple's pairing authentication.
5. Coordinate GUI/CLI ownership and monitor Bonjour registration separately from process liveness. Exercise occupied ports and stale advertisements; verify recovery through an authenticated tunnel and real install/launch, then debugger attachment if promised.

## Supplied application: static implementation evidence

The archive identifies **Nuticast 1.0.19, build 23**, with one app executable and one bundled CLI helper. Nothing was installed or executed. Used `unzip`/Python zip inspection, `plutil`, `otool -L`, `nm -j`, `xcrun swift-demangle` and targeted `xcrun llvm-objdump` disassembly. Symbols exist in both executables; the findings below use the helper unless stated otherwise. The extraction and tool outputs remain locally under `.build/nuticast-research/`, outside source control.

Provenance:

- Archive SHA-256: `909591d5c3c374faf5a7ead67ed354fb7938c9815116164676636ce44ae347f4`.
- Helper SHA-256: `708a03588bd41f33950d69d60448fcd967a6eb049a3d3e1c8af4c76cb0b44fa9`.
- App executable SHA-256: `019cefb910a9bf01d63f9fd9617df96a49f719ebf7f9fb88b2acd06d4eaf86ab`.

### Observed mechanisms and confidence

1. **Discover and probe the cable's network path.** `SystemUSBPhoneDiscovery.discover()` calls `wiredInterfaces()`, `linkPeers(on:)` and `answersLockdown(_:timeout:)` before labelling results. This is visible in disassembly at `0x1000a9ce0`, including those calls at `0x1000a9d00`, `0x1000a9d74` and `0x1000a9ddc`. Supporting strings include scoped link-local IPv6 patterns. This corroborates network-service forwarding over the wired interface. It does not establish the exact USB interface configuration or every supported OS. Windows CoreDeviceProxy is documented separately; do not equate that Windows implementation with this Mac path. Local disassembly (`disassembly-7.txt`).

2. **Maintain the service endpoint while sharing stays enabled.** `USBHostSharing` has separate `tick`, `adopt`, `dropPhone`, `maintainPort`, `startPortSearch` and `finishPortSearch` methods, plus `presenceMisses`, `lastPortCheck` and `nextPortSearch` state. `maintainPort(for:)` actually calls `RemotePairingProbe.probe` at `0x1000a39a4`, clears the stored port after an unsuccessful probe, and calls `startPortSearch` at `0x1000a3b24`. This establishes a revalidation/rediscovery path, beyond merely finding suggestive names. It does not prove all failures retry forever or an LLDB session survives. Local disassembly (`disassembly-1.txt`), symbols (`helper-demangled.txt`).

3. **Reject stale asynchronous port searches.** `finishPortSearch(_:token:target:)` checks running state and compares its token at `0x1000a58f8`–`0x1000a590c`, then calls `USBPhone.__derived_struct_equals` at `0x1000a597c`. This supports rejecting results for an obsolete session/phone. The exact identity fields covered by that equality need further analysis. It is not proof of cryptographic device authentication. Local disassembly (`disassembly-2.txt`).

4. **Separate host control from data forwarding.** `USBHostProtocol` has `infoResponse`, `openResponse`, and `parse(line:)`; request cases include `info`, `open`, `malformed`. `USBHostInfo` includes version, host and optional phone fields; phone metadata includes UDID and RemotePairing port. `USBPortForwarder.forward(port:isBaseline:)` holds an entries dictionary with `isBaseline`/`openedAt` and independent open/entries locks. `ProxyBridge.askUSBHostToOpen(port:generation:)` and `handleDiscoveredTunnelPort` support on-demand tunnel forwarding. These are binary-verified interfaces/data shapes; exact framing, target restrictions, eviction rules and enforcement are not established. Local symbols (`helper-demangled.txt`), strings (`helper-strings.txt`).

5. **Retry an upstream connection during startup.** The binary has `TCPRelay.bridgeRetryingUpstream`, `connectUpstream(for:port:deadline:)`, and `upstreamRetryWindow`. These identify retry machinery bounded by a deadline; they do not establish a particular retry duration or safe replay of application bytes. This is useful specifically for the race where Xcode connects before the cable host has opened a newly discovered tunnel port. Generic MCP heartbeat/reconnection symbols also exist in the helper and were deliberately excluded: they are not evidence of USB recovery. Local symbols (`helper-demangled.txt`), connection construction disassembly (`disassembly-8.txt`).

### Applying the ideas to this Debagr checkout

**First, preserve the distinction between first-time pairing and subsequent cable-backed deployment.** Nuticast explicitly requires existing pairing with the Xcode Mac. Debagr's USB path deliberately creates that initial trust through a raw-USB backend. Service forwarding could become a simpler route for an already-paired phone; it is not evidence that Debagr can remove raw USB from remote first-time pairing. Debagr's Longcable notes explain a concrete failure before USB networking appears: `SET_CONFIGURATION` must permit switching to the configuration that exposes usbmux/NCM. [Current USB/IP setup notes](usbip.md), [Nuticast pairing limitation](https://www.nuticast.com/usb-sharing).

Prioritized work:

1. **Near-term: recover the current session deliberately.** The USB/IP supervisor starts one approved child and waits for exit, then records stopped/failed. Its UI polling reports unexpected exit with a manual restart instruction. VirtualHere similarly reports an ended SSH tunnel and asks the user to reconnect. Add one cancellation-aware recovery owner with bounded retries for transient failures; retain the selected signed peer and physical-device identity and rebuild enumeration after reconnect. Do not retry privilege, trust, ownership or changed-identity failures automatically. Reuse existing generation checks rather than introducing a second independent retry loop. Evidence: `Sources/Debagr/USBIPSession.swift:180–215,457–502`, `Sources/Debagr/USBPairingSession.swift:238–242`, `Sources/Debagr/InitialPairingCoordinator.swift:1058–1110`.

2. **Near-term: distinguish process liveness from usable transport.** Debagr already correctly keeps CoreDevice readiness separate (`ConnectionDeviceCheck.swift:3–26`); preserve it. Add transport-stage diagnostics for export absent, selected device absent, USB import present, Apple services responsive and trust/lock recovery. Nuticast's layered discovery and endpoint maintenance are the useful model. This is an improvement to diagnosis and recovery, not a claim that existing Debagr reports a running USB child as ready.

3. **Architectural experiment: Apple-service forwarding for already-paired devices.** Prototype discovery of the cable's wired network interface and service probe, then expose only the required RemotePairing/tunnel services through the authenticated peer link. Validate on hardware before promising reduced privilege requirements or superior reliability. Keep first-time pairing separate until demonstrated.

4. **For that new service route: coordinate dynamic tunnel opening and local acceptance.** Await the remote open acknowledgement or allow bounded pre-connect retries. Retry only before the connection is established and before application data can be consumed. Debagr's existing generic TCP bridge currently stops on `.failed` and has a 15-second `.waiting` limit (`TCPRelay.swift:117–145`); this relay is not the raw USB/IP backend, so changing it alone will not repair USB/IP import failures.

5. **Acceptance matrix:** same phone unplug/replug; replacement phone on the same cable; lock/unlock; Trust/Developer Mode interruption; host restart; sleep/wake; VPN/interface change; moved service port; tunnel-open race; occupied local port; cancellation while reconnecting. Require expected device identity and a signed app install/launch, with Wi-Fi disabled on the phone to establish a cable-backed route. Test debugger attach only if promised. For the raw initial-pairing route, separately prove genuinely new Apple trust, not refreshed existing pairing.

## Remaining blockers

Static inspection establishes concrete mechanisms and call sites, but not comparative reliability, exact retry/eviction policy, complete control authentication, socket-binding enforcement or privilege behavior. No Nuticast execution, dynamic tracing, hardware test, license bypass or source reconstruction was attempted. The proprietary source remains unavailable. A hardware prototype and failure-injection tests are needed before treating the proposed architectural route as proven.

