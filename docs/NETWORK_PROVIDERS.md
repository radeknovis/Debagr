# Private network providers

Debagr can use Tailscale, Headscale, ZeroTier, NetBird, or WireGuard to reach a
paired device across separate Wi-Fi networks. Configure the VPN on both devices
before setting up Debagr. Provider account creation, device enrollment, access
rules, and tunnel configuration stay in the provider's own tools.

**Verification:** Tailscale remote installation and launch were previously
verified on an iPhone. The other provider paths have automated coverage for
configuration, address validation, persistence, and proxy construction. They
still require real-device installation and launch tests on separate networks.

Current target devices are iPhone and iPad. Mac targets are a possible future
extension; deploying macOS apps to a Mac is not implemented. The build Mac and
target device are separate roles.

## Choose a provider

| Provider | What to configure first | How Debagr selects the device |
| --- | --- | --- |
| [Tailscale](https://tailscale.com/docs/install/ios) | Connect both devices to a network that permits communication between them | Lists online peers from the local Tailscale client |
| [Headscale](https://docs.headscale.org/usage/connect/apple/) | Connect the official Tailscale clients to your Headscale server | Uses the same client discovery; permits private IPv4 pools |
| [ZeroTier](https://docs.zerotier.com/quickstart/) | Join and authorize both devices on your ZeroTier network | Enter the device's assigned private IPv4 address |
| [NetBird](https://docs.netbird.io/manage/peers/add-machines-to-your-network) | Enroll both devices and permit communication between them | Enter the device's NetBird private IPv4 address |
| [WireGuard](https://www.wireguard.com/quickstart/) | Configure keys, routes, endpoints, and a working tunnel | Enter the device's private tunnel IPv4 address, rather than its public endpoint |

ZeroTier, NetBird, and WireGuard do not require a Tailscale installation or
account. Their device addresses are entered manually; Debagr does not query
those providers' APIs or store their credentials. Manual selection does not
establish that the device is online. Apple's readiness check verifies the device
connection after configuration, and install/launch results verify deployment.

Tailscale profiles retain the `100.64.0.0/10` restriction. Other providers accept
RFC1918 (`10/8`, `172.16/12`, `192.168/16`) and CGNAT (`100.64/10`) IPv4 addresses.
Public, loopback, multicast, link-local, hostnames, and IPv6 are unsupported as
manual destinations. Overlapping local and VPN address ranges can route to the
wrong host; use a VPN range that does not overlap the local networks.

## Menu-bar setup

1. Pair the device with this Mac over USB and enable Developer Mode.
2. Connect both devices through the selected VPN and keep the device nearby on
   the same Wi-Fi for initial service capture.
3. Choose **Set Up Remote Device…** and select the VPN provider. Tailscale and
   Headscale automatically load the online-device picker in the same form.
   Other providers show an address field for the device's private VPN IPv4.
4. Select the same device in the paired-device and nearby-service lists, then
   confirm its VPN device/address. Choose **Save & Connect**.
5. Keep Debagr running. Move the device to another Wi-Fi network, keep its VPN
   connected, unlock it, and run a readiness check followed by deployment.

**Use Saved Profile…** imports an existing capture. Its provider and IP must
match your selection. Existing Tailscale profiles remain compatible; changing a
provider requires deliberate setup and does not rewrite a saved profile on load.

One remote device is managed at a time. Remote relays require macOS 26 or later
for exact listener-address binding. Cellular-only RemotePairing remains excluded.

## CLI setup

For example, with a ZeroTier-assigned address:

```sh
/Applications/Debagr.app/Contents/MacOS/Debagr \
  --configure --provider zerotier --peer 10.147.17.2 \
  --device DEVICE_UDID --bonjour-host My-Device.local --json
```

Use `--provider netbird` or `--provider wireguard` with that provider's device IP.
Use `--provider headscale --peer PHONE_NAME` for discovery through a Headscale
connected Tailscale client. Omitting `--provider` preserves the Tailscale default.
The provider flag applies to `--configure` and `--capture-device-profile`.
`--direct-device` uses the provider saved in its profile.

Once configured, `--status`, `--diagnose`, and `--deploy-app` keep their existing
syntax. Status and diagnostics include `networkProvider`; `tailscaleInstalled`
remains an informational client-presence check, not a prerequisite for other VPNs.
Keep the saved profile private and use the existing SSH authorization boundary.
