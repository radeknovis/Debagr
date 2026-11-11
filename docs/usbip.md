# Initial device pairing over USB/IP (Experimental)

**Experimental.** Everything in this guide is an experimental part of the
Debagr 0.3.0 technical preview. It depends on third-party tools that Debagr
does not ship, it runs one of them as root, and its Builder side currently
works only with System Integrity Protection turned off. No part of it has
passed hardware acceptance with Debagr 0.3.0. If your iPhone or iPad already
trusts the Mac that builds your apps, you do not need this guide: choose
**Use existing pairing** instead.

## What this path is for

An iPhone or iPad must trust the Mac that deploys to it, and Apple creates that
trust over a USB cable. This path lets a device that is plugged into a nearby
Mac (the **Client**) appear as a USB device on a remote Mac (the **Builder**),
long enough to complete Apple pairing on the Builder. You usually need it once
for each device and Builder, and again only if the device's trust is reset or
the Builder changes.

USB sharing is a temporary setup connection. Stopping it does not by itself
prove that the later wireless and VPN connection works; check that separately.

## Before you start

You need all of the following.

- Two Macs that both run Debagr 0.3.0: the Builder, which compiles your apps,
  and the Client, which has the device plugged in with a data cable.
- A private network between the two Macs, normally your VPN. Allow TCP ports
  49388, 49389 and 3240 between them in the firewall and in the VPN's access
  rules.
- A separately installed USB tool. Debagr does not include or download one.
  For USB/IP that is a patched `longcable-server` on the Client and
  `usbip-macos` on the Builder; see [USB tools](#usb-tools). The alternative is
  VirtualHere, which has its own flow behind **Use VirtualHere instead…**.
- For USB/IP, an administrator password on both Macs. Starting and stopping the
  connection each show the macOS administrator prompt.
- For USB/IP, System Integrity Protection (SIP) turned off on the Builder. The
  Client does not need SIP turned off.

## Security trade-offs

Read this before you turn anything off.

- **SIP off weakens the whole Builder.** SIP stops even root from modifying
  protected system files and from attaching to protected processes. With SIP
  off, any software running as root on that Mac can do those things, not only
  the USB tool. Apple recommends turning SIP off only temporarily. Turn it back
  on when pairing is finished. Debagr only reads the SIP status and never
  changes it.
- **A third-party tool runs as root.** After you approve the administrator
  prompt, Debagr checks that the USB tool has not changed since you clicked
  **Start Setup Connection** and runs a private copy of it as root from
  `/private/tmp/debagr-usbip-<UUID>/`. The check covers that one file, not
  libraries it loads, and a tool that needs files next to it will not start
  from the copy. Debagr cannot vouch for that tool. Use a build you trust, and
  keep it where only you and the Mac's administrators can change it.
- **USB/IP has no authentication and no encryption.** A device that can reach
  the Client's USB/IP port while your device is shared may be able to use it
  over USB. Debagr accepts only private IPv4 addresses and an explicit peer, but a
  private address does not prove that a VPN is active. Carry USB/IP over your
  VPN and restrict the peers with the VPN's access rules.
- **Linking the Macs is not Apple pairing.** The Builder/Client link only
  synchronises the two roles. It does not transfer Apple trust and it cannot
  start a USB process on the other Mac.

## Open the screen

Click the Debagr icon in the menu bar and choose **Open Debagr**. The
Connections window opens on **Use existing pairing**. In the path picker,
choose **Initial device pairing**, which is marked Experimental.

The screen shows the Builder and the Client side by side, each with its Mac
name and its job. The arrow between them describes the roles, not a live USB
connection. The separate **Temporary setup connection** area shows the status
of the USB processes and of the device check.

## Find and link your Macs

### Discovery

Open **Initial device pairing** on both Macs. Debagr then checks which USB
processes run on this Mac and looks for other Macs through Bonjour on the
local network and among the online peers of your Tailscale network.
**Refresh** scans again.

Discovery uses TCP port 49388 and the Bonjour type `_debagr._tcp`. Role pairing
uses TCP port 49389 and `_debagr-role._tcp`. Debagr listens on these ports and
advertises them only while this screen is open, or while a Builder or Client
role is saved on the Mac. They do not run at every launch. The commands
`debagr --usbip discover` (about nine seconds) and `debagr --usbip advertise`
(until you press Ctrl-C) also start both services for as long as the command
runs, whatever role is saved.

Keep the screen open on both Macs until they are linked. A Mac with no saved
role cannot be found while the screen is closed, and closing it during a first
link cancels the link on that Mac. If only one Mac then shows a role, link
them again or choose **Unpair This Mac** there.

While it listens, a Mac answers only connections from itself, from private
IPv4 ranges, and from the 100.64.0.0/10 range that Tailscale uses. The
discovery reply is not authenticated. Any device on the same private network
or VPN can read these fields:

| Field | Meaning |
| --- | --- |
| Protocol version | The version of the discovery format |
| Node ID | A random identifier that Debagr generated for the Mac |
| Mac name | The computer name |
| Process roles | Whether the Debagr app, a USB export process, or a USB import process is running |
| Machine role | Builder, Client, or not selected |
| Paired node ID | The node ID of the Mac it is linked with, if any |
| Role-pairing public key | The public key that verifies the Mac's signed role updates |

Two more fields are sent only to the Mac itself and to a connection that
Debagr has verified as coming from a device of the same Tailscale user:

| Field | Meaning |
| --- | --- |
| SIP status | Whether System Integrity Protection is on, off, or customised |
| Plugged-in device names | USB product names of connected Apple mobile devices, such as "iPhone" |

Serial numbers and device identifiers are never sent. When a Mac does not
receive the last two fields, its screen shows them as unknown:
**Device list unavailable** and **Builder SIP status unavailable**. That is
expected for two Macs that see each other only over the local network.

The Tailscale part of the scan runs `tailscale status --json` on your Mac and
connects to every online peer in your tailnet on TCP 49388 and on TCP 3240.
The second connection sends a USB/IP device-list request, which recognises a
USB/IP server that is already running even if that Mac does not run Debagr.
Known Macs are checked again about every five seconds.

The device lists are informational. They do not claim device trust, unlock
state or readiness, and discovery never attaches a USB device.

### Choose the roles

Click the **Builder** or the **Client** computer in the diagram and choose a Mac
from the list. Choosing a Mac immediately gives the other Mac the opposite role
and synchronises both. There is no separate save step. Choosing the current
pair in reverse swaps the roles. A Mac that is already linked with a different
machine is unavailable in the list; unpair it there first. A failed change
keeps the previous pair.

### When a pairing code is needed

The first link between two Macs must be confirmed.

- **No code:** only when the connection runs over Tailscale and the local
  Tailscale client's network map shows that the other Mac is owned by the same
  Tailscale user as this Mac. A private or Tailscale-looking IP address alone
  is not enough.
- **Pairing code:** in every other case. That includes tagged Tailscale
  devices, devices of other users in a shared tailnet, and all local-network
  connections. Both Macs show a pairing code. Compare the two codes. The
  other Mac asks first; choose **Pair** there, then choose **Pair** on the Mac
  where you started. Cancel on either Mac if the codes differ or if the other
  Mac shows no code. A Mac that still remembers this Mac from an earlier link
  accepts without showing a code; in that case cancel, choose
  **Unpair This Mac** there, and link again.

After the first link each Mac remembers the other's public key. Every role
update is signed with the sending Mac's private key and bound to the current
connection. A Mac that later presents a different key is rejected until you
unpair. After pairing, either Mac can switch both roles.

**Show Diagnostics**, then **Unpair This Mac**, removes this Mac's role and its
trust in the other Mac. A running USB session blocks role changes.

## Start and stop the setup connection

1. Plug the iPhone or iPad into the **Client** and unlock it.
2. On the **Client**, click **Start Setup Connection**. Debagr first verifies a
   fresh signed response from the linked Mac. Choose the plugged-in device if
   asked, then approve the macOS administrator prompt. Debagr starts the USB
   export.
3. On the **Builder**, click **Start Setup Connection**. Debagr waits up to a
   minute for the Client. If the Client shares one Apple device, Debagr uses
   it; if it shares several, Debagr asks which one to import. Approve the
   administrator prompt. Debagr runs its capability probe and then starts the
   USB import.
4. Complete Apple pairing on the Builder and approve **Trust** on the device if
   it asks.
5. On the Builder, click **Check Device**. If CoreDevice lists several devices,
   choose the one to check. Debagr reports whether that device is reachable
   and unlocked. A running USB process is never shown as ready on its own, and
   the check does not prove installation or launch.
6. To disconnect, click **Stop Setup Connection** on the Builder, then on the
   Client. Stopping asks for administrator approval again.
7. On the Builder, choose **Set up wireless deployment…**. Select the same
   device and its VPN address, capture its nearby wireless service or import
   its saved profile, then choose **Save & check connection**. USB/IP does not
   transfer the wireless profile from the Client to the Builder. If the
   Builder cannot see the device's wireless service, capture and export the
   profile on the Client first.
8. With USB stopped and the cable unplugged, deploy and launch a real app with
   the device on another Wi-Fi network. Only that proves the wireless path.

While Debagr checks the other Mac, **Cancel Check** stops before any USB
process starts. While the administrator prompt is open, **Cancel Approval**
dismisses it. While the Builder waits for the Client, **Cancel Waiting** stops
without an administrator prompt.

Each Mac starts only its own USB process. Closing the window or quitting
Debagr leaves the USB connection running: reopen Debagr and click
**Stop Setup Connection** to end it. If the connection ends unexpectedly, start
it again. No background service or privileged helper is installed.

If a Mac address cannot be used directly, Debagr asks for the Mac's private
VPN IPv4 address.

## USB tools

Debagr starts two separately installed tools. Neither is included in the app.

| Mac | Tool | Source |
| --- | --- | --- |
| Client | `longcable-server` | https://github.com/Sapd/longcable |
| Builder | `usbip-macos` | https://github.com/karstx/usbip-macos |

### The Longcable patch

The Longcable build that was tested with Debagr contains a local source change
that is not yet published anywhere. Debagr does not include it, and there is no
download for it.

What the change does: Longcable has a guard on the USB `SET_CONFIGURATION`
request that the importing Mac sends. The tested build relaxes that guard so
that the server accepts any nonzero configuration, not only the configuration
that was active when the device was first captured. An iPhone is switched to a
different configuration during setup (configuration 6 in the test), and only
then do its usbmux and network (NCM) interfaces appear. In the test, the
unpatched server listed the iPhone but its configuration stalled, so pairing
could not continue.

Until the change is published, you need to build Longcable from source with an
equivalent change; the unpatched server is not expected to complete pairing.
Otherwise use VirtualHere.

### Where to install them

Debagr looks for the tools in two standard locations:

- `/opt/homebrew/bin/longcable-server` or `/usr/local/bin/longcable-server` on
  the Client;
- `/opt/homebrew/bin/usbip-macos` or `/usr/local/bin/usbip-macos` on the
  Builder.

If a tool is somewhere else, **Start Setup Connection** changes to
**Set Up USB Support…**. It explains which tool is missing and lets you select
the executable. Debagr remembers the selection separately for each role and
checks it again before every use. If the file has moved or is no longer
executable, Debagr asks for a replacement instead of switching to another tool.

Longcable keeps its own list of exported devices in
`/Library/Application Support/Longcable/targets.json`. If the device or its USB
port differs from that file, the connection does not start and
**Show Diagnostics** gives the reason. Review and back up that file before you
change it; Debagr never edits or deletes it. While the device is shared, it is
not available to the Client Mac itself.

## Builder SIP status

Debagr reads `csrutil status` without administrator access and shows the result
under the Builder card. Click it for the explanation and for Apple's
instructions.

- **SIP off** means the experimental importer can attempt to run. It also means
  the Builder's system protection is reduced. It is not a recommended state.
- **SIP on** or a customised configuration means the importer is expected to be
  blocked.
- An unavailable result says nothing either way.

The status never proves that USB import works; the capability probe at
connection time decides that.

SIP can be changed only by you, on the Builder, in macOS Recovery:

1. Shut down the Builder. Hold the power button until the startup options
   appear, then choose Options and Continue.
2. Open Utilities, then Terminal, and run `csrutil disable`. Restart.
3. When pairing is finished, return to Recovery, run `csrutil enable`, and
   restart. With SIP on, the USB importer can be blocked again.

`usbip-macos` documents an Apple-approved alternative to SIP off: the
`com.apple.developer.usb.host-controller-interface` entitlement with a
provisioning profile that grants it. Debagr 0.3.0 does not have that
entitlement.

Sources:
[Apple's SIP instructions and risks](https://developer.apple.com/documentation/security/disabling-and-enabling-system-integrity-protection),
[usbip-macos permissions](https://github.com/karstx/usbip-macos#permissions),
[Apple's USB capture requirements](https://developer.apple.com/documentation/iousbhost/iousbhostobjectinitoptions/devicecapture).

## Command line

The same steps are available as foreground commands. `debagr` below is the
Homebrew command, or `/Applications/Debagr.app/Contents/MacOS/Debagr`.

```sh
debagr --usbip help
```

`debagr --usbip discover` prints the result of a nine-second scan as JSON.
`debagr --usbip advertise` answers discovery in the foreground until you press
Ctrl-C; it starts no USB process. While either command runs, it opens the
discovery and role-pairing listeners on TCP 49388 and 49389 and advertises
them over Bonjour, even when no role is saved and the screen is closed.

### Client Mac, next to the device

Keep the device plugged in and unlocked. List USB devices without claiming one:

```sh
debagr --usbip devices
```

Use the device's USB `serial` exactly as printed. Debagr resolves the current
vendor ID, product ID and port each time.

```sh
sudo debagr --usbip serve --tool /absolute/path/longcable-server \
  --listen <this-Mac-VPN-IPv4> --peer <Builder-VPN-IPv4> --serial <USB-serial>
```

### Builder Mac

Run the bundled capability probe as root first:

```sh
sudo debagr --usbip probe
```

It creates and immediately removes a virtual USB host controller without
attaching a device. The JSON result is `available` (exit code 0),
`requires_root` (exit code 2) or `unavailable` (exit code 3). A successful
probe does not establish device trust, installation or launch.

```sh
debagr --usbip list --tool /absolute/path/usbip-macos --remote <Client-VPN-IPv4>
sudo debagr --usbip attach --tool /absolute/path/usbip-macos \
  --remote <Client-VPN-IPv4> --busid <ID-from-list>
```

`attach` runs the probe again before it starts the tool. Stop `attach` with
Ctrl-C, then stop `serve` to release the device. `--tool` runs exactly the
executable you name, as root for `serve` and `attach`.

## Verify the result

Approve **Trust** on the device if it asks. In another Terminal window, check
the device with `xcrun devicectl device info details --device <UDID>`, then run
`debagr --status --device <UDID> --timeout 60 --json`. A listed USB device is
not proof. Use a real install and launch to verify deployment.

## What Debagr stores for this path

- `~/Library/Application Support/Debagr/role-sync-key.raw`: this Mac's private
  key for role pairing.
- `~/Library/Application Support/Debagr/USBIPSessions/`: one folder for each
  setup connection, with the request, its state and the USB tool's output log.
  They can contain the device's USB serial number and private addresses.
- `/private/tmp/debagr-usbip-<UUID>/`: while a setup connection runs, a
  root-owned copy of the selected USB tool. It is removed when the connection
  ends.
- The saved role, the other Mac's public key and the selected tools, in the
  `com.debagr.app` preferences.

To remove them, stop the setup connection, quit Debagr, run
`defaults delete com.debagr.app`, and delete
`~/Library/Application Support/Debagr/`.

## What has not been tested

- No hardware acceptance of this path has been run with Debagr 0.3.0: not the
  two-Mac link, not the USB export and import, and not the wireless hand-over
  afterwards.
- A first-time **Trust** prompt through USB/IP has not been observed. An
  experiment with a development build on 6 November 2026 refreshed a pairing
  that already existed.
- iPad, macOS 13 to 15, and VPN providers other than Tailscale are untested.
- The VirtualHere alternative has automated tests only.
