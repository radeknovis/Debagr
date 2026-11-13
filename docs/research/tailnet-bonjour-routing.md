# Automatic Tailnet discovery and Bonjour routing constraints

> Historical research from 29 August 2026, preserved during branch consolidation.
> Repository observations and proposed decisions describe the proof of concept at that time; they are not current implementation or support claims. Current deployment follows [paired-host execution](../adr/0001-paired-host-execution.md), which rejects cross-Mac RemotePairing projection. See [current ship status](../SHIP_STATUS.md) and [connection design](../CONNECTION_DESIGN.md). External sources have not been revalidated for this merge.

Research date: 2026-08-29

Context pointer: [Research automatic Tailnet discovery and Bonjour routing constraints](https://github.com/radeknovis/Debagr/issues/9)

Parent map: [Debagr: Productize persistent multi-device Apple device access over Tailscale](https://github.com/radeknovis/Debagr/issues/1)

Scope: Tailscale and Apple primary documentation, IETF DNS-SD/mDNS specifications, and the current Debagr repository. This note does not change product source code and does not claim that Apple CoreDevice or RemotePairing supports the complete cross-Tailnet journey.

## Executive recommendation

Use two separate planes:

1. **A unicast Tailscale control and data plane between Mac agents.** Each participating Mac runs a Debagr agent. The agent uses the installed Tailscale client’s peer state and node identity to find or validate eligible Paired Macs, then exposes one authenticated, stable control/data ingress per Mac. Tailscale provides connectivity between nodes, but the destination still needs an application service listening on a port; Tailscale does not create a Debagr service registry automatically. ([Connect to devices](https://tailscale.com/docs/how-to/connect-to-devices), [Tailscale identity](https://tailscale.com/docs/concepts/tailscale-identity))
2. **A local Bonjour projection on the Developer Mac.** The agent creates one local `_remotepairing._tcp` projection per Target Device, with a unique instance name and a locally reachable relay port. Xcode and `devicectl` discover these services through the Developer Mac’s normal local-network Bonjour path; the agent never asks Tailscale to transport `.local` mDNS between Macs. Apple documents `NWBrowser` for browsing Bonjour services, `NWListener.Service` for advertising them, and `NWParameters.requiredInterface` for constraining browsers and listeners to a chosen interface. ([`NWBrowser`](https://developer.apple.com/documentation/network/nwbrowser), [`NWListener`](https://developer.apple.com/documentation/network/nwlistener), [`NWListener.Service`](https://developer.apple.com/documentation/Network/NWListener/Service-swift.struct), [`requiredInterface`](https://developer.apple.com/documentation/network/nwparameters/requiredinterface))
3. **Per-device routing state inside the Paired-Mac agent.** The registry key should be `(paired Mac node identity, Apple Target Device identity)`, not a friendly Bonjour name or a Tailscale IP alone. The Paired Mac resolves each device’s current local endpoint and owns the mapping from the virtual service to that endpoint. The Developer Mac sends the selected service’s opaque TCP/UDP bytes to the Paired Mac agent, which forwards them to the mapped Target Device.

This is the smallest model that satisfies “no manual peer, host, or port settings” after one-time onboarding. It is an architectural inference from the cited platform primitives, not an Apple-supported RemotePairing protocol contract.

## The discovery boundary

### Tailscale discovers Macs, not Bonjour services or hidden Apple devices

Tailscale’s documented automatic naming feature is MagicDNS: it registers DNS names for devices in a tailnet, and those names resolve to Tailscale devices. Its documented service flow still requires a service running on the destination and a port to connect to. MagicDNS therefore solves **which Mac node** to reach, not **which Bonjour service or Target Device** is behind that Mac. ([MagicDNS](https://tailscale.com/docs/features/magicdns), [Connect to devices](https://tailscale.com/docs/how-to/connect-to-devices))

The product should use the Tailscale peer list/local client state as a routing input and then perform a small, authenticated Debagr handshake on a fixed agent ingress. It should not treat a MagicDNS name as a service registry, and it should not broadly probe arbitrary ports across the tailnet. The current POC already obtains live peer information from `tailscale status --json`, but requires an explicit peer name and uses that name to choose one peer. ([`TailscaleClient.swift`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/Sources/NuticastPOC/TailscaleClient.swift#L81-L129), [`README.md`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/README.md#L27-L47))

Tailscale’s own client metrics document multicast as a packet-drop reason, and the Tailscale issue tracker still contains an open request for mDNS name and service resolution across Tailscale. That is corroborating evidence, not a product specification; the safe product assumption is that native cross-Tailnet Bonjour is unavailable unless a future Tailscale release explicitly documents otherwise. ([Tailscale client metrics](https://tailscale.com/docs/reference/tailscale-client-metrics), [Tailscale mDNS feature request](https://github.com/tailscale/tailscale/issues/1013))

### Bonjour is local-link discovery

Apple describes Bonjour as a combination of link-local addressing, multicast DNS, and DNS-based service discovery. The mDNS specification defines `.local.` as link-local and requires `.local.` queries to use the mDNS multicast address `224.0.0.251` or `FF02::FB`; mDNS messages use UDP port 5353. ([TN3151: Choosing the right networking API](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api), [RFC 6762, sections 2, 3, and 5.1](https://www.rfc-editor.org/rfc/rfc6762))

Consequences for Debagr:

- A Developer Mac must receive the Bonjour projection locally. Sending a remote device’s `.local` hostname to the Developer Mac and hoping MagicDNS resolves it is the wrong path.
- The Paired Mac must resolve or otherwise own the Target Device’s local Bonjour endpoint. The result must be converted into an application-level route over the Paired Mac’s Tailscale address.
- A general mDNS repeater or multicast bridge is outside the product boundary. It would add link-local multicast forwarding, interface and TTL behavior, cache invalidation, and security exposure without solving the Apple pairing/protocol contract.

The current POC follows this split partially: it captures `_remotepairing._tcp`, resolves the captured `.local` host on the machine that saw it, and separately relays to a selected Tailscale peer. ([`RemoteForwarder.swift`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/Sources/NuticastPOC/RemoteForwarder.swift#L14-L40), [`BonjourHostResolver.swift`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/Sources/NuticastPOC/BonjourHostResolver.swift#L20-L58))

## Interface scoping

Apple’s open-source macOS mDNS responder only attempts multicast send/receive on interfaces that are multicast-capable and not flagged point-to-point. ([Apple mDNSResponder, `MulticastInterface`](https://github.com/apple-oss-distributions/mDNSResponder/blob/8f70f98fc1d0cf439ca3a6470be6ad8ac2bcc019/mDNSMacOSX/mDNSMacOSX.c#L2459-L2484))

This makes a Tailscale `utun` interface a poor Bonjour projection surface when it is presented as point-to-point. In the current development environment, the observed `utun*` interfaces are flagged `POINTOPOINT`; that is a local observation, not a promise about every Tailscale client or future macOS release.

The product should therefore:

- Bind the Tailscale data connection to the selected/validated Tailscale path.
- Advertise and browse the local compatibility service on an active broadcast-capable Wi-Fi, Ethernet, or other eligible local interface.
- Discover the eligible interface dynamically; never bake in `en0`. Apple’s Network framework exposes a specific required interface for connections, listeners, and browsers, and the current repository already demonstrates why interface names vary between Macs. ([`requiredInterface`](https://developer.apple.com/documentation/network/nwparameters/requiredinterface), [`NetworkSupport.swift`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/Sources/NuticastPOC/NetworkSupport.swift#L35-L88), [`README.md`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/README.md#L49-L57))
- Treat the lack of an eligible local interface as an explicit degraded state. Tailscale reachability alone does not establish that Xcode’s local Bonjour browser will see a projection.

The RFC also says a host defending a `.local` name should do so on every active interface on which it answers mDNS. This is another reason to make the interface set a live state machine, rather than assuming one static interface or address. ([RFC 6762, section 14](https://www.rfc-editor.org/rfc/rfc6762))

## Multiple Target Devices

DNS-SD is designed to enumerate service instances of a type and then resolve the selected instance’s SRV and TXT records. RFC 6763 says the SRV record supplies the target host and port, while TXT carries service-specific additional data; it also explicitly describes allocating ports dynamically per service instance. ([RFC 6763, sections 3, 4.1, and 6](https://www.rfc-editor.org/rfc/rfc6763))

Apple’s `NWBrowser` returns a set of browse results and change events, and `NWListener.Service` carries a service name, type, domain, and optional TXT record. That gives the local projection a natural one-service-instance-per-Target-Device shape. ([`NWBrowser`](https://developer.apple.com/documentation/network/nwbrowser), [`NWBrowser.Descriptor`](https://developer.apple.com/documentation/network/nwbrowser/descriptor-swift.enum), [`NWListener.Service`](https://developer.apple.com/documentation/Network/NWListener/Service-swift.struct))

The required registry shape is:

- `targetDeviceID`: a stable Apple-provided identifier where the supported device tooling exposes one; Xcode 27 release notes say `devicectl list devices` presents a unique identifier, preferring UDID, then ECID, then CoreDevice identifier. ([Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes))
- `kind`: iPhone or iPad, kept separate from the user-editable display name.
- `pairedMacNodeID`: the Tailscale node identity of the Mac that owns the Apple pairing and local endpoint.
- `bonjourInstanceName`: a unique, user-facing projection name, derived from the stable ID and display name but not used as the security identity.
- `currentAppleEndpoint`: the latest local host/port information known by the Paired Mac, with an epoch or generation so stale routes can be rejected.
- `localProjection`: the Developer-Mac local TCP/UDP listener and its advertised Bonjour endpoint.

The current parser intentionally keeps only one record: it stores a single `selectedKey`, exposes one `device`, and the README says that only one service is retained. Supporting multiple devices therefore requires a registry and lifecycle per service instance; it is not a port-range tweak. ([`BonjourCapture.swift`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/Sources/NuticastPOC/BonjourCapture.swift#L3-L47), [`README.md`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/README.md#L93-L102))

Use only non-sensitive metadata in the projected TXT record. TXT is appropriate for a short device label or capability/version hint, but it is not a secret channel. The pairing authorization and any access token belong in the authenticated Mac-to-Mac control plane, not in a visible local Bonjour record. Apple documents TXT as advertised service data, and RFC 6763 defines it as service-specific additional information. ([`NWListener.Service`](https://developer.apple.com/documentation/Network/NWListener/Service-swift.struct), [RFC 6763, section 6](https://www.rfc-editor.org/rfc/rfc6763))

## Dynamic TCP and UDP ports

### What DNS-SD supports

DNS-SD’s SRV record is specifically intended to advertise the port chosen for a running service. RFC 6763 says services can allocate available ports dynamically and publish those allocated ports in SRV records; a client must resolve the service instance rather than assume a global static port. ([RFC 6763, section 4.1](https://www.rfc-editor.org/rfc/rfc6763))

Apple’s Network framework can create a listener with an optional local port, exposes the assigned port once the listener is ready, and reports changes to advertised service endpoints. This is sufficient for Debagr to allocate local proxy ports automatically and advertise the result to Xcode. ([`NWListener`](https://developer.apple.com/documentation/network/nwlistener), [`NWListener.port`](https://developer.apple.com/documentation/network/nwlistener/port), [`serviceRegistrationUpdateHandler`](https://developer.apple.com/documentation/network/nwlistener/serviceregistrationupdatehandler))

### What the relay must do

- The Paired Mac watches the supported/available Apple device-discovery surface and refreshes a Target Device route when its SRV host or port changes.
- The Developer Mac maintains a stable local projection identity while replacing the underlying relay route. Existing connections should be drained or failed explicitly; stale port mappings must not silently point at another Target Device.
- A DNS-SD `_tcp` SRV record describes the service’s advertised port. It does **not** by itself establish that the same numeric port must be used for UDP. The current POC pairs TCP and UDP relays on the same port because that is the observed RemotePairing path; this is repository behavior, not a generic DNS-SD rule. ([`RelayPair.swift`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/Sources/NuticastPOC/RelayPair.swift#L4-L40), [`README.md`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/README.md#L35-L42))
- If the Apple path opens additional dynamic tunnel ports, each port needs a separate route record or a deliberate multiplexing layer. The POC currently observes `remotepairingd` log lines containing `Got tunnel endpoint` and creates TCP/UDP relay pairs for new ports. Apple’s public documentation reviewed here does not define that log message or guarantee its stability, so log parsing is a compatibility fallback and a launch risk, not a supported product contract. ([`TunnelPortWatcher.swift`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/Sources/NuticastPOC/TunnelPortWatcher.swift#L1-L67), [`README.md`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/README.md#L104-L114))

### Fixed ingress versus dynamic Tailnet ports

Prefer one stable Debagr agent ingress per Paired Mac, with target selection in an authenticated control header or framing layer and opaque Apple payload bytes after routing. This avoids requiring a human to update Tailscale policy every time an Apple tunnel port changes. The framing/multiplexing design must be prototyped for both TCP stream ordering and UDP datagram boundaries before it is treated as an implementation decision.

If the first implementation exposes Apple tunnel ports directly on the Paired Mac’s Tailscale interface, the product must own a bounded port range and document the required policy. Tailscale grants can allow a specific protocol/port or a range, including separate TCP and UDP rules; dynamic ports cannot be authorized with a single unknown fixed port. ([Grants](https://tailscale.com/docs/features/access-control/grants), [Grants syntax](https://tailscale.com/docs/reference/syntax/grants))

## Tailscale ACL and identity implications

Tailscale’s security model is based on user identity, node identity, and tags rather than treating an IP address as the complete identity. Node identity is cryptographically tied to a device, and Tailscale’s LocalAPI can report the node, address, user, or tags associated with an incoming source. ([Tailscale identity](https://tailscale.com/docs/concepts/tailscale-identity))

Apply that model at two layers:

1. **Tailnet layer:** authorize Developer-Mac nodes to reach the Paired-Mac node on the Debagr ingress. Use user/device/group selectors appropriate to the tailnet. Tailscale grants express network permissions by destination, protocol, and port; legacy ACLs remain available but Tailscale recommends grants for new policy work. ([Grants](https://tailscale.com/docs/features/access-control/grants), [ACLs](https://tailscale.com/docs/features/access-control/acls))
2. **Debagr layer:** authorize the Developer Mac to use specific Target Devices and map each request to a device identity. The iPhone or iPad behind the Paired Mac is not itself a Tailscale node in this architecture, so a Tailscale ACL cannot distinguish Target Device A from Target Device B when both are reached through the same Paired-Mac node. This requires an application-level pairing grant, device ID, and revocation state.

Do not use a friendly Mac hostname or a 100.x address as the sole authorization key. They are useful routing hints, while the Tailscale node identity and the Debagr pairing record are the authorization inputs. Likewise, do not use the Target Device’s friendly Bonjour name as its durable identity: names can be renamed or collide, while the registry should retain a stable Apple device identifier when available. ([Machine names](https://tailscale.com/docs/concepts/machine-names), [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes))

The no-manual-settings promise therefore depends on a one-time bootstrap that is allowed to remain explicit:

- install/sign in to Tailscale on each participating Mac;
- USB-pair each iPhone or iPad with its Paired Mac using Apple’s supported device workflow;
- approve the Developer Mac’s use of the Paired Mac once in Debagr, or use a pre-existing tailnet policy plus a Debagr application grant;
- after that, discover current peers, device records, and ports automatically.

Tailscale alone cannot provide zero-touch discovery of an arbitrary new application service on every Mac. A fixed Debagr ingress, an app-level enrollment record, or an explicitly configured service identity is still needed for safe bootstrap. This follows from Tailscale’s documented distinction between network connectivity and the application service running on the destination. ([Connect to devices](https://tailscale.com/docs/how-to/connect-to-devices), [Tailscale identity](https://tailscale.com/docs/concepts/tailscale-identity))

## Apple pairing and Xcode boundary

Apple’s current Device Hub guidance covers physical iPhone and iPad pairing with a Mac. It also documents that after cable pairing, the cable can be disconnected and the device can be used through Xcode over Wi-Fi with IPv6 enabled on the same network; the current guidance separately describes newer wireless pairing flows. This establishes that “pair once, then use a device over a network” is an Apple-supported local workflow, but it does not establish that a third-party relay may move or proxy the pairing state across a Tailscale path. ([Managing your simulated and physical devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub))

Apple also states in the Xcode 12 release notes that Xcode encrypts the connection between Xcode and paired devices for supported OS versions. Debagr should preserve those bytes as opaque and must not terminate, decrypt, inspect, or log the RemotePairing payload. ([Xcode 12 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-12-release-notes))

The compatibility risk is the service contract itself. The repository depends on the private-looking `_remotepairing._tcp` type and its TXT/SRV data, while the public Apple documentation reviewed here describes generic Bonjour APIs and Device Hub rather than a public `_remotepairing._tcp` schema or third-party relay API. Apple’s generic Bonjour listener documentation also says advertised service types should be registered with IANA. Treat `_remotepairing._tcp` acceptance by Xcode as a versioned compatibility dependency that must be tested on every supported Xcode/macOS/iOS/iPadOS combination, not as a stable public API. ([`BonjourCapture.swift`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/Sources/NuticastPOC/BonjourCapture.swift#L19-L20), [`NWListener.Service`](https://developer.apple.com/documentation/Network/NWListener/Service-swift.struct), [Bonjour listener service guidance](https://developer.apple.com/documentation/network/bonjourlistenerprovider/init(name:type:domain:txtrecord:))

Apple’s local-network privacy guidance says registering, browsing, and resolving Bonjour services require local-network access, and it calls out the relevant `NSLocalNetworkUsageDescription` and `NSBonjourServices` configuration. A signed Debagr app must make that permission and its recovery state visible to the user once; it cannot assume that a background process will silently receive or retain Bonjour access. ([TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy))

## Supported, brittle, and out of bounds

| Area | Supported basis | Product stance |
| --- | --- | --- |
| Mac-to-Mac reachability | Tailscale provides node connectivity; a destination application service listens on a port. ([Connect to devices](https://tailscale.com/docs/how-to/connect-to-devices)) | Promise unicast reachability when both agents are online and tailnet policy permits it. |
| Mac identity and authorization | Tailscale node identity, user/tags, LocalAPI, grants/ACLs. ([Tailscale identity](https://tailscale.com/docs/concepts/tailscale-identity), [Grants](https://tailscale.com/docs/features/access-control/grants)) | Authorize Macs at the tailnet layer; authorize hidden Target Devices in Debagr. |
| Local service projection | Apple `NWBrowser`, `NWListener.Service`, interface selection, and local-network permission. ([`NWBrowser`](https://developer.apple.com/documentation/network/nwbrowser), [`NWListener`](https://developer.apple.com/documentation/network/nwlistener), [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)) | Project one local service instance per Target Device on eligible LAN interfaces. |
| Multiple devices | DNS-SD enumerates service instances; `NWBrowser` exposes a set of results. ([RFC 6763](https://www.rfc-editor.org/rfc/rfc6763), [`NWBrowser`](https://developer.apple.com/documentation/network/nwbrowser)) | Design for multiple iPhones and iPads per Paired Mac, with independent lifecycle and routing records. |
| Dynamic service ports | DNS-SD SRV advertises the live port; Network framework exposes listener readiness and advertised endpoint changes. ([RFC 6763](https://www.rfc-editor.org/rfc/rfc6763), [`NWListener.port`](https://developer.apple.com/documentation/network/nwlistener/port)) | No user-entered ports; agent-managed refresh and stale-route handling. |
| Bonjour over the Tailnet | mDNS is link-local multicast; Tailscale documents multicast drops and does not document Bonjour transport. ([RFC 6762](https://www.rfc-editor.org/rfc/rfc6762), [Tailscale client metrics](https://tailscale.com/docs/reference/tailscale-client-metrics)) | Do not promise native cross-Tailnet Bonjour or build a generalized mDNS bridge. |
| `_remotepairing._tcp` compatibility | Current repository behavior and generic Apple Bonjour APIs; no public RemotePairing service contract found. ([`BonjourCapture.swift`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/Sources/NuticastPOC/BonjourCapture.swift#L19-L20), [`NWListener.Service`](https://developer.apple.com/documentation/Network/NWListener/Service-swift.struct)) | Treat as launch-gating compatibility testing, not a durable Apple API promise. |
| Dynamic `remotepairingd` tunnels | Current repository watches a log line and creates relays. ([`TunnelPortWatcher.swift`](https://github.com/radeknovis/Debagr/blob/a3e6374749345051f21e5e217fff474d9095e1db/Sources/NuticastPOC/TunnelPortWatcher.swift#L1-L67)) | Do not promise stability until a supported or version-tested observation path exists. |
| Pairing-state mobility | Apple documents pairing a physical device with a Mac and local network use after pairing. ([Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)) | Do not promise that pairing state can be transferred to any other Mac. Keep the Paired Mac as the owner of Apple pairing state. |

## What can be promised

After one-time onboarding and while the relevant agents and tailnet policy are healthy, Debagr can reasonably promise:

- A Paired Mac may own multiple iPhones and iPads, each represented by an independent Target Device record.
- A Developer Mac can discover eligible Paired Macs through Tailscale state and discover all currently available Target Device records through the Debagr control plane, without asking the user for a peer hostname, Bonjour host, or Apple tunnel port.
- Each Target Device can be projected locally as its own Bonjour service instance, with the local SRV port and the remote route maintained by the agent.
- TCP and UDP can be forwarded as opaque traffic over a permitted Tailscale path, subject to the Apple endpoint actually requiring and accepting both transports.
- A tailnet administrator can restrict which Developer Macs reach the Paired-Mac agent; Debagr can separately revoke a Developer Mac’s access to one Target Device without changing the Tailnet identity of the host Mac.

Do **not** promise:

- native Bonjour/mDNS discovery across the Tailscale interface;
- zero-touch first-time enrollment of an arbitrary remote Mac or automatic tailnet-policy changes;
- a stable public Apple API for `_remotepairing._tcp`, `remotepairingd` logs, dynamic tunnel ports, or third-party relay behavior;
- transfer of an Apple pairing record from one Mac to another;
- uninterrupted recovery after every Xcode, macOS, iOS, iPadOS, Tailscale, Wi-Fi, or interface change until the end-to-end matrix passes.

## Decisions and limitations for the main agent to record

1. **Decision:** adopt a two-plane architecture: Debagr’s authenticated unicast Mac-agent registry/data path over Tailscale, plus one local Bonjour projection per Target Device on the Developer Mac.
2. **Decision:** keep the Paired Mac as the owner of Apple pairing state and local `.local` endpoint resolution; never route `.local` mDNS directly through Tailscale.
3. **Decision:** model identity as `Tailscale Paired-Mac node identity + stable Apple Target Device ID`; keep friendly Mac/device names as display metadata only.
4. **Decision:** support multiple iPhones and iPads per Paired Mac with independent records, local service instances, relays, connection state, and revocation.
5. **Recommendation/open decision:** prefer a fixed Debagr ingress per Paired Mac and agent-managed target selection; prototype opaque TCP/UDP multiplexing before exposing dynamic Apple tunnel ports directly to Tailscale ACLs.
6. **Limitation/open decision:** `_remotepairing._tcp` acceptance, TXT/SRV schema, dynamic `remotepairingd` tunnel lifecycle, and cross-Mac CoreDevice behavior remain undocumented or unverified. Add a launch-gating compatibility matrix and do not represent the research as Apple support.
7. **Limitation/open decision:** initial remote-Mac authorization and tailnet policy/bootstrap remain explicit one-time steps. “No interaction” applies to daily discovery and reconnect after enrollment, not to the first trust decision.

## Required follow-up validation

Before turning this recommendation into a product promise, run a focused matrix with two iPhones and two iPads paired to one Mac and used from another Mac:

- enumerate all four devices and verify stable IDs, unique local Bonjour instances, and correct per-device routing;
- run simultaneous TCP and UDP traffic for at least two Target Devices;
- change/restart the Apple endpoint and confirm stale routes are removed before a new route is advertised;
- restart Debagr, Tailscale, both Macs, and each Target Device independently;
- test Wi-Fi, Ethernet, changing interface names, local-network permission denial/recovery, macOS firewall, and a restrictive Tailscale grant;
- validate the current supported Xcode/devicectl and iOS/iPadOS versions, including install, run, debug, and device listing;
- verify that no Target Device identifier, pairing token, TXT secret, or opaque RemotePairing payload is logged.

