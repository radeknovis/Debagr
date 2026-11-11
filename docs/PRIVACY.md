# Debagr privacy policy

Technical-preview policy for Debagr 0.3.0, updated 11 November 2026.
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

### Builder/Client setup (peer discovery and role pairing)

The **Initial device pairing** screen links two of your Macs as Builder and
Client. To do that, Debagr runs two small network services:

- peer discovery on TCP port 49388, advertised over Bonjour as `_debagr._tcp`;
- role pairing on TCP port 49389, advertised over Bonjour as `_debagr-role._tcp`.

These services do not start when the app launches. They run only while the
**Initial device pairing** screen is open, or while a Builder or Client role is
saved on this Mac. Otherwise Debagr has no such listener, publishes no Bonjour
advertisement, does not poll local processes or USB devices every five seconds,
and does not contact your tailnet. To switch them off after linking two Macs,
open the screen, choose **Show Diagnostics**, then **Unpair This Mac**, and
close the window.

The commands `debagr --usbip discover` (about nine seconds) and
`debagr --usbip advertise` (until you press Ctrl-C) also start both services
for as long as the command runs, whatever role is saved.

While the services run, they listen on all IPv4 interfaces of this Mac. They
answer only connections whose source address is this Mac itself, a private
network range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16), or the carrier-grade
NAT range used by Tailscale (100.64.0.0/10). Connections from other addresses
are closed without a reply.

Any device on the same private network or VPN can connect without
authentication and learn the following about this Mac:

- the discovery protocol version;
- a random node ID that Debagr generated for this Mac;
- the Mac's name, which is also the Bonjour service name;
- which Debagr processes are running: the app, a USB export process, a USB
  import process;
- the saved machine role (Builder, Client, or none) and the node ID of the Mac
  it is paired with;
- this Mac's public key for role pairing.

Two further values are sent only to this Mac itself and to a connection that
Debagr has verified as coming from a device owned by the same Tailscale user as
this Mac:

- whether System Integrity Protection is on, off, or customised;
- the USB product names of plugged-in Apple mobile devices, for example
  "iPhone". Serial numbers and device identifiers are never sent.

Other Macs show those two values as unknown. To make the ownership check,
Debagr runs `tailscale status --json` on this Mac when a connection arrives
from a Tailscale address, at most once every 30 seconds for each connecting
tailnet device. The check is local; it sends nothing to the other device.

The role-pairing service sends a connecting device this Mac's node ID, its
public key, and a one-time random value. Role updates are signed. They contain
the two Macs' node IDs and names and which one is the Builder.

### The scan for other Macs

When you open the **Initial device pairing** screen, click **Refresh**, or a
role change is applied, Debagr looks for other Macs:

- It browses Bonjour for `_debagr._tcp` on the local network and connects to
  each Mac it finds on TCP 49388.
- If the Tailscale CLI is installed, it runs `tailscale status --json` on this
  Mac and connects to every online peer in your tailnet on TCP 49388 and on
  TCP 3240. Port 3240 receives a standard USB/IP device-list request, which
  recognises a USB/IP server that is already running. This includes devices in
  the tailnet that belong to other people; they see a connection attempt from
  this Mac's tailnet address and nothing else.

Each connection is closed after at most three seconds. While the screen is open
or a role is saved, Debagr contacts the Macs it has already found again about
every five seconds to refresh their status. `debagr --usbip discover` runs the
same scan from the command line.

### Linking Macs without a pairing code

Two Macs are linked without a pairing code only when the local Tailscale
client's network map shows that the other Mac belongs to the same Tailscale
user as this Mac. Tagged devices, devices of other users in a shared tailnet,
and all ordinary local-network connections show a pairing code on both Macs.
Each Mac asks you to compare the codes before it accepts. See
[security](SECURITY.md).

### Temporary USB sharing

The USB/IP path sends the raw USB traffic of the selected iPhone or iPad from
the Client Mac to the Builder Mac, to the private IPv4 address you choose.
USB/IP itself has no authentication and no encryption, so use it only across
your VPN.

The VirtualHere path uses your existing SSH access from the Builder to the
Client Mac. Over that SSH connection Debagr checks the VirtualHere server's
listening address, asks the Debagr app on the Client for the names of nearby
wireless device services, and, when you choose to go wireless, receives the
selected device's connection profile. The profile contains the device's
Bonjour service metadata and VPN address. It is written to this Mac's private
profile directory and is never sent anywhere else. Debagr stores no SSH
credentials.

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
| `~/Library/Application Support/Debagr/role-sync-key.raw` | The private signing key this Mac uses for role pairing, with its lock file. |
| `~/Library/Application Support/Debagr/USBIPSessions/` | One folder for each USB/IP setup connection: the request, its state, and the USB tool's output log. These can contain the selected device's USB serial number, private addresses, and the path of the USB tool. |
| `/private/tmp/debagr-usbip-<UUID>/` | While a USB/IP setup connection runs: a root-owned copy of the selected USB tool. Removed when the connection ends; after a forced kill it stays until macOS clears `/private/tmp`. |
| Preferences domain `com.debagr.app` | The node ID, the saved Builder or Client role with the other Mac's node ID and name, that Mac's pinned public key, the USB tools you selected, the location of the last USB session folder, and a first-run flag. |

Private files are written with mode 0600 in directories with mode 0700. They
stay until you remove them; keep them private and do not include them in public
reports. Temporary command output is written to the system's temporary
directory and deleted when the command finishes. Apple pairing keys remain
managed by Apple on the paired Mac. Debagr stores no passwords: the macOS
administrator prompt belongs to macOS.

## Removing local data

1. If a USB/IP setup connection is running, open **Initial device pairing**
   and choose **Stop Setup Connection**. The connection keeps running after
   the window is closed or the app quits.
2. Turn off **Launch at Login**, quit Debagr, and move the app to Trash.
3. Delete the preferences, which also removes the saved role and the pinned key
   of the other Mac:

   ```sh
   defaults delete com.debagr.app
   ```

4. Back up any profiles you want to keep, then remove the two data directories:

   ```sh
   rm -rf ~/.config/debagr
   rm -rf ~/Library/Application\ Support/Debagr
   ```

This does not revoke Apple pairing, uninstall your VPN, remove the separately
installed USB tools or their own settings, or remove apps previously deployed
to a device. A Mac that was linked to this one keeps this Mac's public key
until you choose **Unpair This Mac** there.

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
