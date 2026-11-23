# Experimental: USB via Mac (Cable Service Bridge)

> **Experimental Route:** This terminal-driven bridge is an experimental fallback for an **already-paired** physical iPhone or iPad plugged via USB into a second Mac (for example, when Wi-Fi on the phone is off or blocked). It does **not** perform initial Apple pairing.

## How It Works

Instead of forwarding raw USB packets, Debagr opens an unprivileged `AF_UNIX` connection to `/var/run/usbmuxd` on the Client Mac where the phone is plugged in, connects only to lockdown/service port `62078` for that UDID, and relays traffic over `127.0.0.1` through your SSH tunnel over the private VPN to a local `dns-sd -P` proxy on the Builder Mac.

- Zero raw USB sharing
- Zero root privileges
- Zero SIP modifications
- Loopback-only (`127.0.0.1`) bindings

## Terminal Walkthrough

### Step 1: On the Client Mac (phone plugged in via USB)
```bash
debagr experimental cable-bridge client --udid <device-udid> --port 22078
```

### Step 2: Create the SSH Local Forward from the Builder Mac
```bash
ssh -N -L 127.0.0.1:22078:127.0.0.1:22078 <client-user>@<client-vpn-ip>
```

### Step 3: On the Builder Mac
```bash
debagr experimental cable-bridge builder --instance <captured-bonjour-instance> --port 22078
```

You can also print tailored commands directly from the CLI:
```bash
debagr experimental cable-bridge guide --client-host dev@100.64.x.y --udid <udid>
```

## Known Caveats
- The iPhone or iPad must already be paired with the Builder Mac.
- Press `Ctrl+C` on both processes and close the SSH tunnel when finished.
