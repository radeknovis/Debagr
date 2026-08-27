# nuticast-poc

Small macOS Swift command-line proof of the Xcode-to-iPhone remote debugging
relay path:

```text
selected Tailscale peer:100.x.x.x:RemotePairing port
              ↓
       local TCP + UDP relay
              ↓
   local _remotepairing._tcp proxy
              ↓
       Xcode / devicectl
```

## Build

Requires macOS 26 or newer for exact `NWParameters.localEndpoint` binding.

```sh
swift build
swift test
```

The executable is `.build/Products/Debug/nuticast-poc`.

## Phase-1 run

Select the peer explicitly and provide the known RemotePairing port:

```sh
nuticast-poc --peer radeks-mac-mini --remote-port 49640
```

The tool resolves the current `en0` IPv4 address, allocates the first usable
local port in `55000...58000`, starts TCP and UDP relays, registers one local
`_remotepairing._tcp` service with `dns-sd -P`, and starts a local `dns-sd -B`
verification browse. Then test with:

```sh
xcrun devicectl list devices
```

The profile is stored at
`~/.config/nuticast-poc/device-profile.json` unless `--profile` is supplied.
The selected peer IP is refreshed from live `tailscale status --json` output on
each run.

## Bonjour capture

Capture and normalize the first local `_remotepairing._tcp` service:

```sh
nuticast-poc --discover
```

Only one service is retained. Duplicate or conflicting instances are ignored.
TXT values are parsed for proxy use but are never printed by the tool.

## Tunnel watcher

The later tunnel-port path is available behind an explicit flag:

```sh
nuticast-poc --peer radeks-mac-mini --remote-port 49640 --watch-tunnels
```

It watches the owned `/usr/bin/log stream` process, deduplicates remote ports,
allocates a local port for each, and starts both TCP and UDP relays while the
original Bonjour proxy remains alive.

## Safety boundaries

- Tailscale is resolved only from fixed executable paths and the selected peer
  must be online.
- Relay destinations are restricted to the selected peer's `100.64.0.0/10`
  IPv4 address. Bonjour records never choose a relay destination.
- Listeners bind to the resolved en0 address, not `0.0.0.0`.
- By default, inbound clients must appear as this Mac's local interface address
  (loopback is also accepted). `--allow-lan` is an explicit opt-in to accept
  other en0 clients.
- RemotePairing bytes are opaque and are not authenticated, decrypted, or
  otherwise terminated by the relay.
- Child processes are passed argument arrays directly and are stopped on normal
  shutdown and handled termination signals. A narrow PID-scoped kill fallback
  handles children that ignore termination.

Automatic port scanning, additional mDNS service types, multiple devices,
other VPN providers, UI, and credential persistence are intentionally outside
this MVP.
