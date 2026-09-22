# Debagr architecture

Debagr has one supported product path—deployment executed on the Mac that owns
Apple pairing—and one experimental path—the layer-4 RemotePairing relay lab.
The relay does not transfer Apple pairing state or make a Target Device appear
in another Mac's Xcode.

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
  notarize -->|DMG release artifact| artifact

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
  caller -->|local command or| ssh
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
3. `DeviceDeployer` validates the signed `.app`, checks the device lock state,
   installs it with `xcrun devicectl`, and confirms the expected bundle ID.
4. With `--launch`, Debagr asks `devicectl` to launch that same bundle.

The menu-bar app is a monitor and command helper. Its Bonjour view indicates
visibility only; it is not proof that installation or launch will succeed.

## Relay-lab boundary

The relay lab forwards opaque TCP/UDP traffic toward a selected Tailscale peer
and can project a Bonjour control service. It does not authenticate Debagr
callers, inspect RemotePairing payloads, or reproduce Apple's negotiated
link-local tunnel and pairing state. It must not be presented as transparent
cross-Mac Xcode access.
