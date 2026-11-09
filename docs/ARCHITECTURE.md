# Debagr architecture

Debagr must keep the original Build Server's Apple pairing usable when the
Target Device moves to another network. Tailscale runs directly on both
endpoints. Remote invocation by a Caller alone does not satisfy this requirement.
The direct-device mode remains experimental; install and launch on a roaming
iPhone were verified on 10 October 2026. Reconnection and cellular operation
remain unverified. See [DIRECT_DEVICE.md](DIRECT_DEVICE.md) for test evidence.

```mermaid
flowchart LR
  caller["Caller / CI / agent"] -->|"Optional SSH"| server["Original paired Build Server"]
  profile["Captured RemotePairing identity and port"] --> discovery["Local advertisement and TCP/UDP proxy to phone's Tailscale IP"]
  discovery --> server
  server <-->|"Required development transport over Tailscale"| phone["Target Device on another network"]
```

The following component map includes the earlier two-Mac relay lab. It is
separate from the direct-device experiment and does not prove roaming support.

```mermaid
flowchart LR
  %% People and automation
  caller[Caller\nperson, CI, or agent]
  ssh[SSH\nexisting authentication]

  subgraph build[Build Server — Mac that owns Apple pairing]
    subgraph app[Debagr.app]
      menu[Menu-bar application]
      registry[TargetDeviceRegistry\nmerge and status]
      core[CoreDeviceInventory\nphysical devices]
      bonjour[BonjourCapture\n_visible _remotepairing._tcp services]
      support[ProductSupport\nAbout, diagnostics, URLs]
    end

    cli[Debagr CLI]
    deploy[DeviceDeployer\nvalidate .app and bundle ID]
    devicectl[xcrun devicectl]
    dns[dns-sd]
  end

  device[(Target Device\niPhone or iPad)]
  artifact[Signed device .app\nalready on Build Server]

  subgraph release[Release and packaging]
    source[Swift source]
    ci[CI\ntest and lint]
    package[build-macos-app.sh\n.app bundle and Hardened Runtime]
    notarize[Developer ID + notarization\nrelease credentials required]
    source --> ci --> package --> notarize
  end
  notarize -->|Install Debagr DMG on Build Server| menu

  %% Supported discovery path
  menu --> core
  menu --> bonjour
  core -->|list devices JSON| devicectl
  bonjour -->|capture and parse| dns
  core --> registry
  bonjour --> registry
  registry --> menu
  support --> menu

  %% Supported deployment path
  caller -->|Remote command| ssh
  caller -->|Local command| cli
  ssh --> cli
  cli --> deploy
  artifact --> deploy
  deploy -->|lock-state preflight| devicectl
  deploy -->|install app| devicectl
  deploy -->|optional process launch| devicectl
  devicectl -->|paired local connection| device

  %% Experimental lab, intentionally isolated
  subgraph lab[Experimental relay lab — not the deployment product]
    forward[RemoteForwarder]
    tail[TailscaleClient\nselect online peer]
    profile[DeviceProfile\nservice identity and TXT metadata]
    manager[RelayManager]
    pair[RelayPair]
    tcp[TCPRelay]
    udp[UDPRelay]
  end

  peer[Other Mac\nlocal RemotePairing service]
  proxy[Bonjour proxy\nlocal projected service]

  forward --> tail
  forward --> profile
  forward --> manager
  manager --> pair
  pair --> tcp
  pair --> udp
  tail -.->|tailnet transport| peer
  tcp -.-> peer
  udp -.-> peer
  profile -.-> proxy
  proxy -.->|control service only| cli

  classDef supported fill:#e8f5e9,stroke:#2e7d32,color:#16351a
  classDef experimental fill:#fff3e0,stroke:#ef6c00,color:#4e2600
  classDef external fill:#e3f2fd,stroke:#1565c0,color:#0d2b4d
  class menu,registry,core,bonjour,support,cli,deploy,devicectl,artifact,device supported
  class forward,tail,profile,manager,pair,tcp,udp,peer,proxy experimental
  class caller,ssh external
```

## Supported deployment sequence

1. The Build Server is paired with the Target Device through Apple's normal
   Xcode/device workflow.
2. A Caller invokes the Debagr CLI locally or through SSH.
3. `DeviceDeployer` validates the `.app` path and bundle ID, requests device lock state,
   installs it with `xcrun devicectl`, and confirms the expected bundle ID.
4. With `--launch`, Debagr asks `devicectl` to launch that same bundle.

The menu-bar app is a monitor and command helper. Its Bonjour view indicates
visibility only; it is not proof that installation or launch will succeed.
Apple performs signing validation. The Debagr DMG is distinct from the signed
iOS/iPadOS app being deployed.

## Relay-lab boundary

The relay lab forwards opaque TCP/UDP traffic toward a selected Tailscale peer
and can project a Bonjour control service. It does not authenticate Debagr
callers, inspect RemotePairing payloads, or reproduce Apple's negotiated
link-local tunnel and pairing state. It must not be presented as transparent
cross-Mac Xcode access.

## Initial pairing and everyday wireless setup

`InitialPairingCoordinator` owns the initial Builder/Client diagram and
USB/IP controls. `DebagrPeerDiscovery` advertises read-only device names and
machine state; `RoleSyncService` uses signed challenges and pinned keys for role
updates. Verified personal Tailscale endpoints can bootstrap Mac trust without
a code; LAN connections require code confirmation. That Mac link never substitutes
for Apple's device trust or grants remote privileged transport control.

`USBIPSessionController` starts a local, transient root supervisor through macOS
approval. The Client exports via external Longcable; the Builder imports via
external usbip-macos after the bundled `USBIPProbe` succeeds. The SIP annotation
is informational. USB/IP sessions deliberately survive closing the app and have
explicit Stop controls. VirtualHere sessions instead end when their setup closes.
Neither backend is bundled, and Debagr never changes SIP.

On an idle Builder, the pairing window links to `DeviceSetupWindowController`
for everyday wireless configuration or the VirtualHere alternative. Navigation
prevents starting the other GUI backend while a setup session is active. Returning
to initial pairing retains Mac role selection and existing Apple trust. Wireless
readiness still comes from `ManagedDeviceRuntime`; the USB/IP Check Device action
does not establish which transport carried the successful CoreDevice request.

## VirtualHere alternative

`USBPairingModel` drives four native setup stages. Its serial worker owns a
`USBPairingSession`, a bounded command runner, and an SSH process tied to the app's
lifetime. VirtualHere supplies the USB virtualization; Debagr does not emulate a
USB controller or install drivers. The nearby Mac's server must listen only on
127.0.0.1:7575. Existing SSH authentication protects the transport, and a local
lease prevents two Debagr sessions from claiming devices concurrently.

```mermaid
sequenceDiagram
  participant UI as Build Mac / Debagr
  participant VH as Build Mac / VirtualHere Client
  participant Near as Nearby Mac / VirtualHere Server + Debagr
  participant Phone as iPhone
  UI->>Near: SSH preflight and loopback listener check
  UI->>VH: Add hub through owned SSH tunnel; list devices
  UI->>VH: Claim selected USB serial
  VH->>Near: USB traffic over SSH
  Near->>Phone: Physical USB cable
  UI->>Phone: devicectl pair; user approves Trust
  UI->>UI: Verify USB identity, Apple inventory, and lock state
  UI->>Near: Capture selected Bonjour profile over SSH
  UI->>VH: Release selected device; remove owned hub
  UI->>UI: Confirm USB disappearance; close SSH tunnel
  UI->>Phone: Managed runtime checks direct wireless connection
```

The private `--usb-services --json` helper returns a versioned list of service
names and hosts. `--usb-profile --json` returns the existing private `DeviceProfile`
payload, including service metadata. Neither transfers an Apple pairing record.
The helpers are invoked only through the user's existing SSH access; profile data
is kept out of application logs and public diagnostics. Apple trust is created by
`devicectl manage pair` on the build Mac, with consent entered on the phone.

USB acceptance, Apple pairing, wireless readiness, installation, and launch are
separate gates. Tests use a simulated backend; physical validation is still
required. See [connection design](CONNECTION_DESIGN.md) for prerequisites,
recovery behavior, and the hardware acceptance sequence.
