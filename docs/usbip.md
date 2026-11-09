# Initial remote device pairing over USB/IP (experimental)

Use this flow to establish the device's initial trust with its Builder, usually
once for each device and Builder. USB sharing is a temporary setup connection;
complete device pairing on the Builder and approve Trust on the device if asked.
You may need this setup again if device trust is reset or the Builder changes.
The privileged USB transport still needs approval when it is started or stopped;
this is not a one-time installation of a privileged helper. Stopping USB sharing
does not by itself verify a subsequent wireless/VPN device connection.

Debagr can inventory local USB devices and launch the separately installed
longcable server and usbip-macos client. The CLI supports foreground commands;
the native flow uses an owned privileged supervisor. No daemon is installed.
On a new setup, **Set Up Remote Device…** opens the live Builder/Client diagram.
On an already configured Builder, choose **Initial device pairing** in the
wireless setup window to return here.

## Find Builders and Clients

Open **Set Up Remote Device…** to scan this Mac's processes, Bonjour on the local
network, and online Tailscale peers. The main view places the Builder and Client side by side, with each Mac's name
and job in the pair. The separate **Temporary setup connection** area shows process and
device-check status; the arrow between the Macs describes their roles, not a live
USB connection. Click either Mac in the diagram to open its available-Macs picker.
Both cards and picker entries list the physically plugged-in Apple mobile device
models, or **No device connected**. Known Macs refresh about every five seconds;
unavailable or older peers show **Device list unavailable** instead of an empty
list. Only USB product names are advertised, never serial numbers or device IDs.
The list is informational and does not claim device trust, unlock or readiness.
Return activates Start Setup Connection (or USB support setup), then Check Device while
importing. An offline or mismatched pair cannot start a connection. Use Refresh
to scan again. **Show Diagnostics** expands the full process, address and discovery
table, backend details, **Unpair This Mac** and **Copy Diagnostics**.
Discovery does not attach a USB device or establish device readiness.

### Choose machine roles

On either Mac, open **Set Up Remote Device…** and click the **Builder** or **Client**
computer in the diagram. Choose from this Mac and the other discovered Debagr
Macs. The Builder compiles apps and imports USB through `usbip-macos`; the Client
has the device plugged in and exports it through `longcable-server`.
Choosing a Mac immediately assigns the other machine the opposite role and
synchronizes both Macs. There is no separate edit, save or revert step. Choosing
the current pair in reverse swaps roles. Discovery alone never saves a pairing.
Macs already paired with a different machine are unavailable in the picker;
unpair them there first. A failed change preserves the previous saved pair.

For a first connection over the current Tailscale mesh, Debagr checks the actual
socket's local and remote addresses against the local Tailscale daemon's running
network map. The remote must be a direct, online node in that map and have the
current tailnet's DNS suffix; shared nodes from other tailnets are excluded.
Those connections pair without a code or approval on the other screen. This
trusts the devices admitted to your personal mesh, including tagged devices.
Merely having a private or Tailscale-looking IP address is insufficient.
If that identity cannot be established, including ordinary LAN connections,
compare the verification code on both Macs and accept Pair on the other Mac.
Each update is still signed by a per-Mac private key, bound to a fresh connection
challenge, and checked against a pinned peer key. Mesh membership never bypasses
a changed-key error. After initial pairing, either Mac can switch both roles.

The selected role is distinct from a running USB process. Selecting Macs never
captures a device. Both Macs must be reachable to confirm an update. Concurrent
updates converge to one Builder and one Client. A running USB session blocks
changes. **Show Diagnostics → Unpair This Mac** removes this Mac's choice and
trust in its selected peer.

### Start and stop the connection

1. Plug an iPhone or iPad into the **Client**. Without one, Start Setup Connection
   immediately shows the missing-device instruction before any networking,
   support-tool setup or administrator prompt. A Builder whose Client reports
   no device gives the same instruction instead of entering a blind wait.
   On the **Client**, click **Start Setup Connection**. Debagr first verifies a fresh
   signed response from the selected, trusted Mac. Choose the plugged-in device,
   and approve the macOS administrator prompt. Debagr starts the USB export.
2. On the **Builder**, click **Start Setup Connection**. Debagr waits up to a minute
   for the Client and uses its sole exported Apple device automatically. If
   multiple devices are shared, it asks which device to import.
   Approve the administrator prompt to start the import. The native capability
   probe runs before the import backend.
3. The Client reports that its device is shared and names the Builder as the
   next step. Once import is running on the Builder, use **Check Device**. If
   CoreDevice lists multiple devices, explicitly choose the one to check.
   Debagr verifies that selected device is reachable and unlocked and identifies
   it in the result. Locked, unavailable and unconfirmed results include a next
   step and keep Check Device available to retry. A running USB process never
   becomes Ready on its own. CoreDevice verification does not establish which
   transport carried the request or prove installation/launch.
4. To disconnect, use **Stop Setup Connection** on the Builder, then the Client.
   Stopping also asks for administrator approval. During the Builder's wait,
   Stop cancels the wait without an administrator prompt. During the signed Mac
   preflight, **Cancel Check** cancels setup before a USB process is started.
   While macOS administrator approval is pending, the window remains responsive
   and **Cancel Approval** cancels the owned system helper. Authentication still
   requires the normal macOS approval; Debagr does not store credentials.
5. On the Builder, choose **Set up wireless deployment…**. Select the same Apple
   device and private VPN endpoint, capture its nearby Bonjour service or import
   its saved profile, then **Save & check connection**. If the Builder cannot see
   the phone's Bonjour service, capture/export the profile on the Client first;
   USB/IP does not transfer that profile automatically. The SSH profile handoff
   belongs to the separate VirtualHere workflow. After USB has stopped, validate
   wireless readiness and a real installation/launch on another Wi-Fi network.

**Use VirtualHere instead…** opens the alternative SSH workflow on an idle Builder.
Both handoff buttons are disabled while a USB/IP session or approval is active;
the Client tells you to continue on the Builder. The [connection guide](CONNECTION_DESIGN.md)
compares the two backends and distinguishes Mac linking from Apple trust.

Debagr locates the existing backend builds under `~/src/` or Homebrew paths.
An explicitly selected executable is remembered separately for each role and
revalidated before use. If moved or no longer executable, the flow asks for a
replacement instead of silently switching to another tool.
If absent, **Set Up USB Support…** explains the missing tool before asking you
to choose the appropriate trusted executable. Raw backend errors stay under
Diagnostics; the main status names the recovery step.
Bonjour addresses that cannot be used directly and non-Tailscale Client bind
addresses require a private IPv4 address in the flow's address dialog.

Each Mac starts only its own process. The flow validates reciprocal selections
and opposite roles before starting. It does not send USB process controls over the role-pairing connection. A transient privileged supervisor owns
one backend, forwards stop signals and records failures under
`~/Library/Application Support/Debagr/USBIPSessions/`. Closing the window or
quitting the app leaves the transport running; reopen Debagr and use Stop
Connection to end that session. Role changes are disabled while it runs.
An unexpected supervisor exit requires reconnecting. This is not an installed
SMAppService daemon, and no system security settings are changed.

Debagr advertises a read-only discovery identity on TCP 49388 and `_debagr._tcp` while the
app runs. The response contains a node ID, Mac name, process roles and an optional
list of plugged-in Apple mobile USB product names. It contains no serial numbers,
unique device identifiers or USB control operations. Signed role pairing uses TCP 49389
and `_debagr-role._tcp`; permit it through the same private-network firewall
and VPN ACL as discovery. It cannot start privileged USB processes remotely. Only private IPv4 and loopback connections
are accepted. Discovery responses are informational and are not authentication.
Your firewall and VPN ACLs must permit the discovery port for remote discovery.
Older Debagr apps need updating to advertise. Separately running USB/IP servers
on online Tailscale peers are recognized by an OP_REP_DEVLIST reply on TCP 3240;
they do not need a Debagr advertisement. Standalone clients that do not advertise
are visible only on their own Mac through process detection. Process detection
does not prove a successful USB attachment.

`debagr --usbip discover` prints the results of a nine-second scan as JSON.
`debagr --usbip advertise` runs a foreground discovery responder without starting
device relays; Ctrl-C stops it. The GUI app already runs its own responder.

Use the binary inside this build as `debagr` below:

```sh
./Debagr.app/Contents/MacOS/Debagr --usbip help
```

## Client Mac next to the phone (USB exporter)

Keep the phone plugged in and unlocked. Inventory it without claiming the device:

```sh
debagr --usbip devices
```

Select its USB `serial` exactly as printed. Debagr resolves its current VID, PID
and location each time; it does not reuse a stale port or guess a device.

```sh
sudo debagr --usbip serve --tool /absolute/path/longcable-server \
  --listen <this-Mac-VPN-IPv4> --peer <build-Mac-VPN-IPv4> --serial <USB-serial>
```

Use the tested longcable build with the SET_CONFIGURATION guard fixed to accept
nonzero configurations beyond the initially captured configuration. The previous
experiment needed configuration 6 for usbmux and NCM to become available.
The tools are not redistributed in this app. Longcable source:
https://github.com/Sapd/longcable

Longcable persists locations in `/Library/Application Support/Longcable/targets.json`.
If a moved device conflicts with that file, the backend will exit with its error.
Back up and review the existing configuration before changing it; Debagr never
deletes it. Serial selection here resolves launch arguments, not that backend's
persistent storage. The phone is temporarily unavailable to the exporting Mac.

## Builder Mac (USB importer)

First run the bundled native probe as root:

```sh
sudo debagr --usbip probe
```

This creates and immediately destroys an IOUSBHostControllerInterface without
attaching a phone. JSON states: `available` (exit 0), `requires_root` (exit 2),
or `unavailable` (exit 3). Access depends on OS policy and entitlement approval;
SIP text alone is not a capability test. A successful probe does not establish
device trust, a CoreDevice tunnel, installation, or launch.

```sh
debagr --usbip list --tool /absolute/path/usbip-macos --remote <server-VPN-IPv4>
sudo debagr --usbip attach --tool /absolute/path/usbip-macos \
  --remote <server-VPN-IPv4> --busid <ID-from-list>
```

Attach probes access again before starting the client. Stop attach with Ctrl-C,
then stop the server to release the phone. The backend replaces the Debagr CLI
process so Terminal signals and exit codes reach it directly.

### Builder SIP annotation and privilege audit

The read-only `csrutil status` probe runs without administrator access. Its result
is included in discovery and shown beneath the selected Builder card, including
when the Builder is the remote Mac. Green marks **SIP off** and compatibility with
the current experimental root-based importer; it also explains that system
protection is reduced. Amber marks **SIP on** or a custom configuration. An
unavailable, stale or older peer result stays neutral. This annotation never
establishes virtual-controller capability or device readiness.

Click the annotation for the reason, the Apple-approved entitlement alternative,
Recovery instructions (`csrutil disable`), and restoration instructions
(`csrutil enable`). Changes must be made on the Builder in Recovery by the user.
The exporting Client does not need SIP disabled. Debagr never changes SIP,
boot arguments or security policy. Reenabling SIP can block the experimental
importer again.

The privilege audit on 2026-11-06 found that both installed transports still need
root: a direct, unprivileged controller API call failed even on the SIP-off
Builder, and the installed Longcable explicitly rejects non-root USB capture.
Longcable uses IOUSBHost `deviceCapture`, for which Apple requires root or the
restricted `com.apple.vm.device-access` entitlement plus `IOServiceAuthorize`
authorization. The Builder's backend documents an Apple-approved
`com.apple.developer.usb.host-controller-interface` entitlement and granting
profile as the alternative to its SIP-off/root path. Adding an entitlement to
an ad-hoc signature is not an Apple grant. Neither installed backend has the
needed approved entitlement, so capture/import elevation remains in place.
Discovery, SIP and USB inventory, Mac pairing and device checks remain normal-user
operations. No privileged daemon or broader permissions were added.

Sources: [Apple USB capture requirements](https://developer.apple.com/documentation/iousbhost/iousbhostobjectinitoptions/devicecapture),
[usbip-macos permissions](https://github.com/karstx/usbip-macos#permissions),
[Apple SIP instructions and risks](https://developer.apple.com/documentation/security/disabling-and-enabling-system-integrity-protection).

## Verify the result

Approve trust on the phone if requested. In another Terminal check
`xcrun devicectl device info details --device <UDID>` for connected state and wired
transport, then `debagr --status --device <UDID> --timeout 60 --json`.
Use a real install/launch to verify deployment. USB enumeration alone is insufficient.

USB/IP has no authentication or encryption. Use your VPN with restrictive peer
ACLs. Debagr accepts private IPv4 literals and requires an explicit server peer;
private addressing alone does not prove the VPN is active. `--tool` runs the
exact executable you supply, as root for serve/attach: use a trusted build.

## Remaining product work

This flow starts local transports with administrator approval; it is not yet an automatic pairing refresh workflow.
SMAppService registration, authenticated helper IPC, automatic readiness verification and detach,
managed-entitlement provisioning and a redistribution strategy for the backends
remain unimplemented. The bundled probe has no managed entitlement and must be
tested under the intended macOS security policy. This local build is not notarized.


### Connection window layout

The two-column Builder/Client diagram is also the machine picker. Each native
button opens an available-Macs menu and supports keyboard and accessibility
activation. Both cards remain visible through pairing and connection states;
connection actions appear below once the Macs have synchronized. The diagram
arrow describes the assignments, not USB transport or device readiness.
Native preview captures use isolated defaults and sample device/session data;
they do not demonstrate a real USB connection or deployment.
