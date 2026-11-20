# Apple Multi-Device RemotePairing Boundary

> Historical research from 29 August 2026, preserved during branch consolidation.
> Repository observations and proposed decisions describe the proof of concept at that time; they are not current implementation or support claims. Current deployment follows [paired-host execution](../adr/0001-paired-host-execution.md), which rejects cross-Mac RemotePairing projection. See [current ship status](../SHIP_STATUS.md) and [connection design](../CONNECTION_DESIGN.md). External sources have not been revalidated for this merge.

Context: [Debagr issue 7](https://github.com/radeknovis/Debagr/issues/7), under the parent map [issue 1](https://github.com/radeknovis/Debagr/issues/1).

Date: 2026-08-29

Branch: `research/apple-multidevice-remotepairing`

## Concrete Product Boundary

Debagr can safely describe the Apple-supported base as: a user-authorized, per-Mac pairing relationship between Xcode/Device Hub/CoreDevice on that Mac and one or more physical iPhone or iPad devices that are paired to that Mac, visible as Xcode run destinations, and usable through Xcode on USB or on the same local Wi-Fi/Bonjour-capable network after the required trust, Developer Mode, and signing steps.

Debagr must not describe cross-Mac or cross-Tailscale RemotePairing as Apple-supported. A Debagr relay may make a remote paired device appear usable from another Mac, but Apple's public docs do not publish `_remotepairing._tcp` as a third-party service contract, do not document VPN/Tailscale RemotePairing transport, and do not expose CoreDevice or RemotePairing protocol APIs for third-party relay products. Treat that behavior as a best-effort private relay around Apple's local-network device stack.

## Findings

### Multiple iPhones and iPads Paired to One Mac

Apple's Device Hub documentation uses a plural device-management model: Device Hub pairs "physical devices with your Mac," its sidebar shows the physical devices paired with that Mac, and the run-destination documentation says Xcode runs on simulated or physical devices paired with the Mac ([Managing your simulated and physical devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub), [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)).

Direct evidence: Apple documents adding physical devices to the run destination list by pairing them in Device Hub and documents using Device Hub to collect identifiers for iOS and iPadOS devices ([Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices), [Locating device identifiers](https://developer.apple.com/documentation/xcode/locating-device-identifiers)).

Inference: one Mac supporting multiple paired iPhones and iPads is within Apple's documented model because Apple consistently describes a set of paired physical devices and does not document a one-device limit for iPhone or iPad pairing. Apple does not document a concurrency guarantee for running, debugging, or streaming multiple physical iPhones and iPads at once.

### Discovery and Remote Use From Xcode and devicectl

Apple-supported Xcode discovery is through Device Hub and Xcode's run-destination list. For wireless iPhone and iPad pairing in current documentation, Apple requires iOS or iPadOS 27 or later and the same Wi-Fi network so the device can discover the Mac; otherwise Apple says to use a cable ([Managing your simulated and physical devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)). After cable pairing, Apple documents disconnecting the cable and running apps through Xcode over Wi-Fi with IPv6 enabled on the same network as the Mac ([Managing your simulated and physical devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)).

Apple documents `devicectl` as an Xcode-shipped command-line tool for managing and interacting with devices connected to a host; the same Apple command-line reference points users to `xcrun devicectl help` for command details ([Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)). Local first-party tool evidence from Xcode 27.0 beta 6 (`xcrun devicectl --help`) says `devicectl` is a "Core Device" utility for devices "connected to this host" and that JSON output is versioned and stable while human stdout is not.

Direct evidence: Xcode and `devicectl` are host-scoped in the public/tooling language. No Apple public source found during this pass documents using `devicectl` on Mac A to operate a device paired to Mac B through a VPN or remote relay.

### Stable Device Identity

Apple's public identity surface for development devices is the device identifier/UDID. Apple says to collect unique device identifiers before registering devices, and Device Hub exposes the UDID for iOS, iPadOS, tvOS, visionOS, and watchOS devices ([Locating device identifiers](https://developer.apple.com/documentation/xcode/locating-device-identifiers)). Xcode's registered-device distribution flow depends on collecting those unique identifiers and registering known devices in the developer account ([Distributing your app to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)).

Local first-party tool evidence from Xcode 27.0 beta 6 (`xcrun devicectl list devices --help`) says the default `Identifier` column shows UDID, falling back to ECID and then CoreDevice identifier, and that `--device` can accept UDID, ECID, serial number, CoreDevice identifier, name, or DNS name. Xcode 27 release notes also say `devicectl list devices` presents a unique identifier, preferring UDID when available ([Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)).

Product record: store Target Device identity by UDID when available. Treat DNS name, Bonjour instance name, user-provided device name, RemotePairing port, and CoreDevice ID as discovery/routing metadata, not the stable product identity.

### Restart, Sleep, Disconnect, and Re-Pair Behavior

Apple documents a few recovery behaviors but not a full lifecycle contract. During initial pairing, if the Trust prompt is dismissed or the device does not immediately appear in Device Hub after Trust, Apple suggests restarting the device ([Managing your simulated and physical devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)). Apple also says that after upgrading the device operating system, the device must be paired again ([Managing your simulated and physical devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)).

Xcode 16 release notes say Xcode no longer changes the selected run destination implicitly after transient device connectivity loss; instead it keeps the disconnected device selected with a disconnected-status indicator ([Xcode 16 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes)).

Unsupported/unknown: Apple public docs found in this pass do not guarantee RemotePairing recovery across Mac sleep, Mac restart, iPhone/iPad restart, Wi-Fi change, VPN reconnect, or relay process restart. They also do not guarantee that RemotePairing control or tunnel ports remain stable. Debagr should model these as reconnect/re-discover states and require user re-pairing after OS upgrades or when Apple's pairing state is invalid.

### Entitlements, Signing, and Authorization

Pairing requires explicit device trust, and Xcode may require Developer Mode before continuing ([Managing your simulated and physical devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)). Developer Mode is required to run apps from Xcode and for local development-signed installs, and turning Developer Mode off prevents running apps from Xcode until it is turned on again ([Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)).

Running on a physical device requires signing setup. Apple says Xcode can register the device and create/update development provisioning profiles when automatic signing is enabled; `xcodebuild -allowProvisioningUpdates` can create/update profiles, app IDs, and certificates when an account is configured, and `-allowProvisioningDeviceRegistration` can register the destination device when paired with provisioning updates ([Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices), local first-party `xcodebuild -help` from Xcode 27.0 beta 6). Registered-device distribution is limited to known registered devices and a limited number of devices per product family per year ([Distributing your app to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)).

For Debagr's own macOS networking, Apple local-network privacy matters. Apple says local network privacy applies to macOS 15 and later, Bonjour browsing/registration requires local network access, apps that use local network access should declare `NSLocalNetworkUsageDescription`, apps that browse/register specific Bonjour services should declare `NSBonjourServices`, and iOS multicast/broadcast requires the multicast entitlement ([TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), [com.apple.developer.networking.multicast](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast)). Apple separately documents that sandboxed macOS apps must declare network-client and network-server intent through App Sandbox entitlements for outgoing and incoming network access ([Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)).

Product record: Debagr authorization is additive to Apple's authorization. Debagr cannot bypass Trust, Developer Mode, device registration, provisioning profile membership, Apple Developer account permissions, local-network privacy, or sandbox/network entitlements.

### Public Boundary vs Private or Reverse-Engineered Boundary

Apple public docs support Device Hub pairing, Xcode run destinations, local Wi-Fi use after pairing, Developer Mode, signing, and device identifiers. Apple also documents VPN interference with Xcode device communication: Xcode 15 release notes say Xcode may not communicate with iOS 17+/tvOS 17+ devices and paired Apple Watch devices when certain VPNs are active, with disabling the VPN as the workaround ([Xcode 15 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes)). TN3158 says Xcode 15 uses a network-based interface to communicate with USB-connected Apple devices and warns that VPN/PF/security software can block link-local IPv6 device-communication traffic ([TN3158: Resolving Xcode 15 device connection issues](https://developer.apple.com/documentation/technotes/tn3158-resolving-xcode-15-device-connection-issues)).

Apple local-network privacy defines local network as broadcast-capable Wi-Fi/Ethernet-style interfaces and explicitly excludes VPN from that definition ([TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)). That is not a RemotePairing support statement by itself, but it reinforces that Apple's documented discovery/use path is local-network scoped, not VPN-scoped.

Local Xcode SDK evidence shows `RemotePairingDevice.framework` under `System/Library/PrivateFrameworks`, with symbols for wireless pairing session requests and promptless pairing policy, but this is private framework evidence, not a public API contract (`/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/RemotePairingDevice.framework/RemotePairingDevice.tbd:4`, `:79-100`).

Unsupported/unknown: `_remotepairing._tcp` Bonjour records, `remotepairingd` log formats, RemotePairing tunnel endpoint logs, dynamic tunnel ports, RemotePairing packet shape, and any direct use of `RemotePairingDevice.framework` are private or reverse-engineered for Debagr purposes unless Apple publishes a public contract.

## Local Repository Evidence

The current `nuticast-poc` describes itself as a relay path from a selected Tailscale peer and RemotePairing port through local TCP/UDP relay and a local `_remotepairing._tcp` proxy to Xcode/`devicectl` (`README.md:3-14`). It explicitly starts a local `_remotepairing._tcp` service with `dns-sd -P`, then asks the user to test with `xcrun devicectl list devices` (`README.md:35-42`).

The current README already states the MVP is not generalized: if more than one paired phone is present, capture must be constrained to a specific Bonjour host; automatic reconfiguration when the RemotePairing port changes is later work; automatic port scanning, multiple devices, other VPN providers, UI, and credential persistence are outside the MVP (`README.md:70-91`, `README.md:132-134`).

The current source parses `_remotepairing._tcp.local` records and retains a single selected device, optionally matching a preferred host name (`Sources/NuticastPOC/BonjourCapture.swift:19-45`, `Sources/NuticastPOC/BonjourCapture.swift:98-102`). The remote forwarder captures exactly one Bonjour device and rejects a manually requested port that differs from the discovered port (`Sources/NuticastPOC/RemoteForwarder.swift:84-107`, `Sources/NuticastPOC/RemoteForwarder.swift:25-30`).

The current profile persists a Tailscale peer IP, remote port, Bonjour name, and local port range, but not an Apple UDID (`Sources/NuticastPOC/DeviceProfile.swift:3-10`). That is sufficient relay metadata, but it is not the stable Target Device identity boundary established above.

The relay is intentionally constrained: Tailscale destinations must be in `100.64.0.0/10`, local Bonjour destinations must be `.local` or local IPv4, and relay constructors reject destinations outside those constraints (`Sources/NuticastPOC/NetworkSupport.swift:108-137`, `Sources/NuticastPOC/RelayPair.swift:134-176`). RemotePairing bytes are documented as opaque and not authenticated, decrypted, or terminated by the relay (`README.md:126-127`).

The tunnel watcher depends on a private `remotepairingd` log predicate and parses `"Got tunnel endpoint"` log lines (`Sources/NuticastPOC/TunnelPortWatcher.swift:18-21`, `Sources/NuticastPOC/TunnelPortWatcher.swift:3-15`). That belongs on the private/reverse-engineered side of the product boundary.

## Source List

- [Debagr issue 7](https://github.com/radeknovis/Debagr/issues/7): research question and required handoff scope.
- [Debagr issue 1](https://github.com/radeknovis/Debagr/issues/1): parent product map and current destination.
- [Managing your simulated and physical devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub): Device Hub pairing, wireless/cable requirements, Trust, Developer Mode, same-network Wi-Fi, OS-upgrade re-pairing.
- [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices): run destinations, physical-device signing, provisioning setup.
- [Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference): `devicectl` is an Xcode-shipped command-line tool and command details live in `xcrun devicectl help`.
- [Locating device identifiers](https://developer.apple.com/documentation/xcode/locating-device-identifiers): UDID/device identifier collection through Device Hub and Finder.
- [Distributing your app to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices): registered-device workflow, known-device distribution, annual device-family limit.
- [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device): Developer Mode authorization requirements and effect of disabling it.
- [TN3158: Resolving Xcode 15 device connection issues](https://developer.apple.com/documentation/technotes/tn3158-resolving-xcode-15-device-connection-issues): Xcode's network-based device communication and VPN/PF boundary.
- [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy): local network privacy, Bonjour, VPN exclusion from local-network definition, macOS local-network behavior.
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox): sandbox network-client/server entitlements.
- [com.apple.developer.networking.multicast](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast): multicast/broadcast entitlement and Apple permission requirement on iOS.
- [Xcode 15 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes): known VPN interference with Xcode device communication.
- [Xcode 16 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes): transient connectivity behavior and expanded `devicectl --device` identifiers.
- [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes): Device Hub network pairing for iPhone/iPad/watchOS 27 and `devicectl list devices` identifier behavior.
- Local Xcode 27.0 beta 6 first-party tool evidence: `xcrun devicectl --help`, `xcrun devicectl list devices --help`, `xcrun devicectl device info details --help`, `xcodebuild -help`.
- Local Xcode 27.0 beta 6 private framework evidence: `/Applications/Xcode-27.0.0-Beta.6.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/RemotePairingDevice.framework/RemotePairingDevice.tbd`.

## Limitations

This pass did not perform a live multi-device pairing experiment and did not prove end-to-end Xcode usability through a Debagr relay. It also did not inspect private RemotePairing traffic. The conclusion is a support-boundary conclusion from Apple primary documentation, local first-party Xcode tool help, the Xcode private framework stub location, GitHub issue context, and current Debagr source.
