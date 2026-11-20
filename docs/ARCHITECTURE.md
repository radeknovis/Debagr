# Debagr architecture

Debagr must keep the original Build Server's Apple pairing usable when the
Target Device moves to another network. Wireless operation uses Tailscale on the Builder and phone. The cable route
uses Tailscale between the Macs and a USB network link to the phone. Remote invocation by a Caller alone does not satisfy this requirement.
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
    dns[Native DNS-SD registration]
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

## Restored connection interface

`DeviceSetupView` keeps one root window for wireless setup and the cable guide.
`DeviceSetupModel` preserves explicit identity confirmation, saved profiles,
asynchronous developer-tool checks and editable invalid addresses. The cable
bridge is started through its CLI; the guide does not create a pairing or start
sharing. UI models and menu actions remain main-actor owned.

`CableSharing` starts one SSH-owned host helper, and `CableHostControl` opens
upstream TCP/UDP listeners before `DirectDeviceApplication` opens its matching
local listeners. Saved tunnel ports are preopened to avoid Xcode's immediate
connection race. The existing watcher learns additional tunnel ports. The host
is restricted to one cable endpoint and one Builder VPN source address.

See [the connection design](CONNECTION_DESIGN.md) for the workflows and hardware
acceptance boundaries.
