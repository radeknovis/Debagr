# Debagr security

Technical preview 0.3.0, updated 11 November 2026.

## Deployment boundaries

- Debagr opens no network listener for deployment commands. Remote
  authentication and access control are delegated to the build server's SSH
  configuration. `debagr --mcp` serves local tools over stdin and stdout only.
- Deployments require an explicit local `.app` path and explicit device UDID.
- `xcrun` and `devicectl` receive argument arrays directly; no shell evaluates
  app paths, identifiers, or bundle IDs.
- RemotePairing payloads are forwarded opaquely and never logged or decrypted.
- Tailscale destinations must be online IPv4 peers in `100.64.0.0/10`.
  Alternative-provider profiles require an explicitly selected RFC1918 or CGNAT
  IPv4 address; public and link-local destinations are rejected.
- Device relay listeners bind to the selected local interface address. The
  managed relay accepts connections only from this Mac's own address and
  loopback. The lab relay commands accept the explicitly selected peer, or
  other LAN clients only with the explicit `--allow-lan` flag.
- Child processes for inventory and deployment use fixed executable paths,
  argument arrays, and owned process identifiers.
- App diagnostics omit Bonjour TXT records and payload data.

## Peer discovery and role pairing

The **Initial device pairing** screen links two Macs as Builder and Client.
It uses two listeners that are separate from deployment.

| Service | TCP port | Bonjour type |
| --- | --- | --- |
| Peer discovery | 49388 | `_debagr._tcp` |
| Role pairing | 49389 | `_debagr-role._tcp` |

### When they run

The listeners and their Bonjour advertisements do not start at launch. They run
only while the **Initial device pairing** screen is open, or while a Builder or
Client role is saved on this Mac. Otherwise there is no listener, no
advertisement, no five-second inventory of local processes and USB devices, and
no tailnet probing. **Show Diagnostics**, then **Unpair This Mac**, removes the
saved role and the trust in the other Mac.

The commands `debagr --usbip discover` (about nine seconds) and
`debagr --usbip advertise` (until you press Ctrl-C) also start both services
for as long as the command runs, whatever role is saved.

While they run, both listeners bind to all IPv4 interfaces. They answer only
loopback and source addresses in `10.0.0.0/8`, `172.16.0.0/12`,
`192.168.0.0/16`, or `100.64.0.0/10`, and close every other connection without
a reply. A source address in those ranges is not authentication: on a shared
office, hotel, or café network, other devices on that network can connect.

### What an unauthenticated client can read

The discovery reply to an ordinary private-network client contains only the
protocol version, node ID, Mac name, process roles, machine role, paired node
ID, and role-pairing public key. System Integrity Protection status and the
product names of plugged-in Apple devices are sent only to loopback and to a
connection verified as coming from a device of the same Tailscale user, as
described below. For that check Debagr reads the local Tailscale network map
(`tailscale status --json`) when a connection arrives from a `100.64.0.0/10`
address, at most once every 30 seconds for each connecting tailnet device,
and reuses the answer in between. Serial numbers and device
identifiers are never sent. The reply is informational. Discovery accepts no
commands.

The role-pairing listener sends each connecting client a greeting with this
Mac's node ID, public key, and a one-time nonce.

### Who can change roles

- Every role update is signed with a per-Mac Curve25519 key, bound to the
  nonce of the current connection, and addressed to one node ID.
- The first pairing pins the other Mac's public key. A later connection that
  presents a different key for that Mac is rejected until you unpair.
- Pairing without a code is allowed only when the local Tailscale client's
  network map shows that the remote peer is owned by the same Tailscale user
  as this Mac. Debagr compares the user ID of the peer that owns the
  connection's actual remote address with this Mac's own user ID, and both
  must be present. A private or Tailscale-looking address alone is never
  enough.
- Tagged devices, devices of other users in a shared tailnet, and all
  local-network connections fall back to a pairing code shown on both Macs.
  The Mac that receives the request asks first; the Mac that started it asks
  for the same confirmation before it saves the role or pins the key. Compare
  the codes before you accept, and cancel if the other Mac shows no code. A
  Mac that still holds this Mac's pinned key from an earlier link accepts
  without a prompt; unpair it there and link again to get a code on both. Any
  device that can reach the role-pairing port can cause the first prompt to
  appear; decline a request you did not start.
- If the Mac that started the link is closed, times out or cancels after the
  other Mac has accepted, only the other Mac holds a role. Link them again, or
  choose **Unpair This Mac** there.
- Pairing authorises role synchronisation only. After pairing, either Mac can
  change both roles. The role-pairing connection cannot start or stop a USB
  process, and it cannot deploy an app. A running USB session blocks role
  changes.
- Role-pairing messages are signed but not encrypted. Their contents (node
  IDs, Mac names, and roles) are visible to anyone who can observe the network
  path.

### Outbound scan

Opening the screen or choosing **Refresh** browses Bonjour on the local
network, runs `tailscale status --json` locally, and connects to every online
tailnet peer on TCP 49388 and TCP 3240. The connection to 3240 sends a USB/IP
device-list request to recognise a USB/IP server that is already running. Known
Macs are contacted again about every five seconds while discovery runs.

## Processes that run as root

The VirtualHere path does not elevate Debagr. The USB/IP path does:

- **Start Setup Connection** shows the macOS administrator prompt. After you
  approve it, Debagr runs its own executable as root as a supervisor. The
  supervisor starts exactly one USB tool and forwards stop signals to it.
- On the Client the tool is `longcable-server`. On the Builder it is
  `usbip-macos`, started after Debagr's bundled capability probe, which also
  runs as root.
- **Stop Setup Connection** asks for administrator approval again.
- No privileged helper or launch daemon is installed. The supervisor is not
  tied to the window: it keeps running after the window closes or the app
  quits, until you stop it.
- The administrator prompt approves one command line. It holds the session
  folder and the complete request: the export or import arguments and the
  SHA-256 of the selected USB tool as it was when you clicked
  **Start Setup Connection**. The supervisor acts only on that command line.
  It does not read `request.json`, which is kept as a record.
- After approval the supervisor reads the tool again, refuses to start if its
  SHA-256 differs, and runs a private copy from a root-owned folder,
  `/private/tmp/debagr-usbip-<UUID>/`, which it removes when the session ends.
  In the session folder it refuses symbolic links, hard links and pipes for
  the lock, log and state files.
- **Stop Setup Connection** reads the supervisor's process ID from
  `state.json`, which your user account can write. Before it sends the stop
  signal, it checks that the process's command line is the supervisor command
  for that session folder.
- Limits: the hash covers the selected tool file only, not libraries or other
  files it loads, and a tool that needs files next to it will not start from
  the copy. The supervisor and the capability probe are Debagr's own
  executables; if `Debagr.app` is writable by your user account, software
  running as you can replace them before you approve the prompt. None of this
  defends against software that already runs as your user. This root path has
  not been run on hardware for 0.3.0.
- Debagr does not ship the USB tools and cannot vouch for them. Use a build
  you trust in a location you control.
- The command-line equivalents (`debagr --usbip probe`, `serve`, and `attach`)
  run as root only when you start them with `sudo` yourself.

USB/IP has no authentication and no encryption. Debagr accepts only private
IPv4 addresses and an explicit peer, but a private address does not prove that
a VPN is active. Carry USB/IP over your VPN and restrict the peers with VPN
ACLs.

The current USB/IP importer on the Builder works only with System Integrity
Protection turned off. That reduces protection for the whole system, not only
for Debagr. Debagr reads the status with `csrutil status` and never changes
it. Turn SIP back on when the setup is finished.

## Stored secrets

- The role-pairing private key is stored in
  `~/Library/Application Support/Debagr/role-sync-key.raw`, mode 0600, in a
  directory with mode 0700. It is not in the Keychain. Debagr refuses a key
  file with a different owner or mode.
- The other Mac's pinned public key and the saved role are stored in the
  `com.debagr.app` preferences.
- Connection profiles under `~/.config/debagr/` are written with mode 0600.
- USB session folders under
  `~/Library/Application Support/Debagr/USBIPSessions/` hold the request, the
  state, and the USB tool's output log.
- Debagr stores no passwords and no SSH credentials.

The privacy policy (`PRIVACY.md`) lists what each location contains and how to
delete it.

## Remote access boundary

Anyone allowed to invoke Debagr through SSH acts with that macOS account's
device-development privileges. Require public-key authentication, least-
privilege accounts, a private network such as Tailscale, and normal SSH audit
and revocation practices. Do not expose Remote Login directly to the internet.

## Preview limits

This is a technical preview. USB/IP, VirtualHere, and two-Mac Builder/Client
linking have automated tests but no hardware acceptance for 0.3.0. The
compatibility matrix (`COMPATIBILITY.md`) lists what has been verified.

## Reporting

Report vulnerabilities through GitHub
[private vulnerability reporting](https://github.com/radeknovis/homebrew-debagr/security/advisories/new)
on the public tap repository, which also publishes this policy as `SECURITY.md`.
Responses are best effort during the technical preview, and only the latest
release receives fixes. Do not file public issues containing device identifiers,
hostnames, tailnet addresses, pairing material, logs, or diagnostics.
