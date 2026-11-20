# Debagr privacy policy

Technical-preview policy for Debagr 0.3.0, updated 13 November 2026.
Publisher: Radek Novak. Counsel review is required before any sale.

## Summary

Debagr has no analytics, advertising, crash-reporting SDK, customer account, or
Debagr cloud service. Nothing is sent to the publisher. The app talks only to
your own Apple devices, to Macs and VPN peers on your private networks, and to
the tools installed on your Mac. The sections below say exactly when it does so.

## What Debagr processes on this Mac

To display status, deploy apps, and create diagnostics, the app reads locally
visible device names, Bonjour hostnames, identifiers and ports, app bundle paths
and identifiers during deployment, `devicectl` results, the macOS version,
Developer Tools availability, and the Tailscale CLI location and status.

Debagr forwards RemotePairing traffic between this Mac and your device without
inspecting, decrypting, or logging it. Bonjour TXT values are stored only in the
private connection profile and are left out of logs and diagnostics.

## What leaves this Mac, and when

### Everyday deployment

Deployment traffic goes from this Mac to your own iPhone or iPad over your
local network or your private VPN. Remote callers reach Debagr through your
Mac's own SSH service; Debagr opens no network listener for deployment commands.

### Mac cable service sharing

When you run `debagr --cable connect`, Debagr uses your existing SSH identity
and trusted host key to start a helper on the selected cable Mac. It sends that
helper the fixed cable-side IPv6 endpoint, the Builder's Tailscale address, and
port-opening requests. No SSH passwords or private keys are stored by Debagr.

The helper opens TCP/UDP listeners on the cable Mac's selected Tailscale IPv4
address and permits only the selected Builder's Tailscale source address. It
forwards device services to the fixed cable endpoint. Apple's existing pairing
authenticates the device connection. The helper does not inspect USB serial
numbers, scan other Macs, exchange role keys, or create initial Apple trust.
Closing the controlling SSH session releases those listeners.

### Diagnostics

**Copy Diagnostics** places a report on the clipboard. Nothing is sent unless
you paste it somewhere. Reports omit TXT records and traffic contents, but they
can contain device names, Mac names, hostnames, private addresses, and ports.
Review a report before you share it.

### Sponsorship links

The optional sponsorship links, when activated, open GitHub Sponsors or Ko-fi.
Those services process their own account and payment data under their policies;
Debagr does not receive payment credentials or embed a payment SDK.

## What Debagr stores

| Location | Contents |
| --- | --- |
| `~/.config/debagr/` | Device connection profiles, the managed remote device, and the last deployment receipt. Profiles can contain device identifiers, private VPN endpoints, and captured Bonjour service metadata. |
| Preferences domain `com.debagr.app` | UI preferences and launch/setup state. Older preferences from removed setup paths are ignored. |

Keep profiles private. Apple manages pairing keys on the paired Builder. Debagr
stores no administrator or SSH passwords. Legacy setup data from earlier builds
is not automatically deleted.

## Removing local data

1. Stop any cable bridge with Ctrl-C. Turn off Launch at Login and quit Debagr.
2. Move the app to Trash. Back up profiles you want to keep, then remove
   `~/.config/debagr/` and clear the `com.debagr.app` preferences if desired.
3. Older builds may have stored setup keys and logs under
   `~/Library/Application Support/Debagr/`. These are no longer used by this
   build; review them before removing them.

Removing Debagr does not revoke Apple pairing, uninstall VPNs or other tools,
or remove previously deployed device apps.

## Future paid product

For any future commercial checkout, licence delivery, payments, taxes, and
refunds will be handled by the merchant-of-record named at purchase. Its
privacy policy applies to data it collects. Add the selected processor, data
categories, retention periods, international-transfer basis, and deletion route
before opening checkout.

## Contact

Send privacy requests to the publisher through
[private vulnerability reporting](https://github.com/radeknovis/homebrew-debagr/security/advisories/new).
Add a postal address and jurisdiction before any sale.
