# Connection design

The Builder owns Xcode pairing, signing and deployment. A device can pair
locally with the Builder. **Pair via USB/IP** also offers an experimental
first-time pairing route when the device is plugged into another Mac.
The two deployment routes below use existing Apple trust.

## Wireless deployment

The **Use existing pairing** tab selects the paired Apple device, matching
Bonjour identity and private VPN destination. Confirm that selections identify
the same physical device. The saved connection is checked through Apple's
CoreDevice stack. The managed menu-bar runtime owns its wireless relay.

The phone remains on Wi-Fi and the selected VPN. The Builder builds and signs,
then installs and optionally launches with `devicectl`. Readiness, installation,
launch and visible UI behavior are separate checks.

## USB via Mac

The phone remains plugged into a cable Mac. That Mac forwards RemotePairing
and tunnel services over Tailscale to the already paired Builder. It does not
recreate the raw USB device. The phone needs no Wi-Fi on this route.

The **USB via Mac** tab describes the experimental CLI and opens the bundled
setup guide. It has no initial-trust action, tool installer, administrator
prompt, peer-role picker or background discovery service. Starting the CLI owns
one SSH helper and one bridge session; Ctrl-C closes them. Closing the guide
window does not control a separately started CLI session.

The helper binds to its exact Tailscale address, permits the Builder's source
address, and forwards only to the session's fixed scoped cable endpoint. Saved
tunnel ranges are opened before Bonjour publication; the log watcher learns
further tunnel ports. See [setup, constraints and hardware evidence](CABLE_SHARING.md).

## Evidence

On 13 November 2026, authenticated readiness and a signed LightApp installation
passed from a Mac mini Builder through a MacBook Pro cable host with phone
Wi-Fi disabled. Launch, debugger, automatic discovery, reconnect and wider
hardware coverage are not accepted by that run.

The USB/IP setup screen restores saved Builder/Client roles and can resume
monitoring a running setup session. See the [USB/IP setup guide](usbip.md).
Historical release records describe older
binaries, not the current connection paths.
