# Direct Target Device transport

## USB/IP refresh and relay deployment, 6 November 2026

The referenced RemotePairingd research thread records a newer physical-device
experiment on the MacBook Air, Mac mini, and iPhone 16 Pro:

1. Longcable on the Air exported the phone to usbip-macos on the mini. Initial
   USB enumeration succeeded but configuration stalled. A local Longcable patch
   allowed nonzero `SET_CONFIGURATION` values beyond the initially captured one.
2. With configuration 6, usbmux and NCM appeared. CoreDevice reported a connected
   wired device and an authenticated tunnel; Debagr readiness returned `ok: true`,
   `state: ready` with a longer timeout.
3. **The mini's existing Apple pairing was accepted. No new Trust prompt occurred.**
   This demonstrates a pairing-refresh experiment, not creation of a new pairing.
4. The user stopped both USB processes and confirmed unplugging the phone.
   With the Debagr relay running and the iPhone reachable through Tailscale,
   readiness passed again. A signed LightApp build was installed and launched:
   the thread records `ok: true`, `installed: true`, and `launched: true`.

The source is the recorded experiment in
<t3-thread://v2/c44be434-b944-4980-839b-9296d0114a88/9737cbd3-c5a9-4f98-bf38-936f0d9abfcd>
(messages around positions 138–196). It was reviewed during consolidation, not
repeated. The exact OS/tool/backend commit matrix was not captured in that result,
and app UI behavior was not checked. Do not apply the older October version matrix
below to this November experiment, or treat it as acceptance of the newly combined
Debagr build, first-ever Apple trust, VirtualHere, iPad, or cellular transport.

The patched backend remains outside Debagr; neither Longcable nor usbip-macos is
redistributed by the app. See [USB/IP setup](usbip.md) for its privilege and capability
requirements, and [connection design](CONNECTION_DESIGN.md) for the two native paths.

## Original direct-device transport

The product must keep the original Build Server's Apple pairing usable when
the Target Device moves to another network. Tailscale runs on both endpoints.

The experimental `--direct-device` mode publishes the captured RemotePairing
identity in DNS-SD on all interfaces, pointing to a TCP/UDP proxy on the selected interface.
The proxy forwards directly to the iPhone's Tailscale address, preserving port
numbers. Apple owns authentication and tunnel establishment. Incoming relay
connections are restricted to this Mac's interface address and loopback.

Before advertising, Debagr opens the control port and a bounded tunnel range.
The optional profile field `tunnelPortRange` defaults to `[49152, 49216]`; set
it to the device's expected range if needed (at most 1024 ports). A watcher
adds same-port TCP/UDP relays for tunnel endpoints reported by `remotepairingd`.
The watcher is a fallback: Apple may attempt the connection before a log-driven
relay is ready. Pre-open the expected range for reliable initial establishment.

Hardware check on 10 October 2026: the Mac mini installed and launched
`com.monefit.smartsaver.light.staging` on the paired iPhone 16 Pro while the user
confirmed it was awake on another network. Tailscale connected both endpoints.
The same deployment also passed when invoked from the MacBook over SSH to the
Mac mini; the MacBook was only a caller, not a gateway for the iPhone.
Apple authenticated the captured identity, established a TCP tunnel on port
60547, and read lock state before deployment. The private test profile pre-opened
`[60540, 60640]`; a single previously observed port failed because the next
attempt allocated a different port. A refused port after cancellation does not
prove the active tunnel is unreachable.

Discovery on all interfaces uses `dns-sd -P` without `-i`: `-i 0` silently
prints usage and exits, while local-only discovery was not reliably found by
Apple's native browser. The endpoint parser accepts both scoped IPv4
`192.168.1.140%en1:60547` and scoped IPv6 dot-port formats.
The previous direct-advertisement implementation is checkpointed at `6d13bb2`.

### Working checkpoint configuration

The verified Build Server ran macOS 27.2 (26B5086k), Xcode 27.2
(27B5028f), and Tailscale 1.102.4. The private profile is stored locally at
`.build/iphone-relay-profile.json` and is ignored by Git. It preserves the
captured identity and adds `"tunnelPortRange": [60540, 60640]`.
Do not replace that range with the default when reproducing this test;
the default does not cover this phone's observed tunnel ports. This is an
observed test range, not a guaranteed allocation range for all devices.

From the Debagr repository on the Mac mini:

```sh
.build/release/debagr --direct-device --peer iphone171 \
  --profile .build/iphone-relay-profile.json --interface en1
```

Leave the relay running and invoke `--deploy-app <signed-device.app> --device
<paired-UDID> --launch` in another terminal or over SSH. Successful output
included `Tunnel connection established`, `App installed`, and
`Launched application with com.monefit.smartsaver.light.staging bundle identifier.`
These establish transport, installation, and an OS-confirmed launch, not a
visual UI check. The test did not change or bypass Apple's pairing records.

## Prepare on the original local network

Pair normally using Xcode, enable Developer Mode, and connect both endpoints to
Tailscale. Use `debagr --discover` to identify the phone's Bonjour hostname.
Select its unique Tailscale DNS name (not a shared hostname such as localhost).

```sh
.build/debug/debagr --capture-device-profile \
  --peer iphone-tailnet-name \
  --bonjour-host My-iPhone.local \
  --profile .build/phone-direct.json
```

The explicit Bonjour hostname and Tailscale peer must belong to the same device;
capture does not cryptographically verify that mapping. Apple verifies the
remote pairing identity when it connects. The profile contains TXT metadata;
keep it private. Capturing a profile does not establish new Apple pairing.

## Test roaming

Unplug USB, move the iPhone to a different Wi-Fi network, and keep Tailscale
and the unlocked device active. On the Build Server (select its LAN interface):

```sh
.build/debug/debagr --direct-device \
  --peer iphone-tailnet-name --profile .build/phone-direct.json --interface en1
```

Leave it running. In another terminal, test `devicectl` lock state, then deploy
a signed device `.app` using Debagr's `--deploy-app`, `--device` and `--launch`.
Verify that the app actually launches. Record the phone's network, Tailscale
connectivity, exact OS/toolchain versions, and command results.

A Tailscale ping, open TCP port, or visible advertisement is only an intermediate
check. None proves successful authentication, CoreDevice tunnelling, installation,
or launch. A shared-network result cannot prove roaming.

## Current limits

This is a transport experiment, not yet automatic reconnection. The process
must remain running. If the service identity, port, or Tailscale address changes,
recapture the profile on the local network. Recovery across device reboot,
locking, VPN reconnect, and network handover requires separate verification.
The existing two-Mac relay lab does not implement this direct-device path.
