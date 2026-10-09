# Direct Target Device transport

The product must keep the original Build Server's Apple pairing usable when
the Target Device moves to another network. Tailscale runs on both endpoints.

The current experimental `--direct-device` mode publishes a captured
RemotePairing service in the Build Server's local-only DNS-SD namespace with
the device's Tailscale IPv4 address. The original service port and TXT identity
are preserved. Apple owns authentication and tunnel establishment. There is no
Debagr TCP/UDP forwarding hop, and no advertisement is sent to other LAN hosts.

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

Unplug USB, disable Wi-Fi in iPhone Settings, and keep cellular, Tailscale and
the unlocked device active. On the Build Server:

```sh
.build/debug/debagr --direct-device \
  --peer iphone-tailnet-name --profile .build/phone-direct.json
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
