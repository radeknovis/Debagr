# Experimental Mac cable service sharing

This CLI route forwards RemotePairing and CoreDevice TCP/UDP services from a
phone's USB network link. It does not forward raw USB or establish initial Apple
trust. Pair the phone with the Builder Mac in Xcode first. Keep that pairing.

Both Macs need this Debagr build and reachable Tailscale IPv4 addresses. The
Builder needs working, already trusted SSH key access to the cable Mac. SSH
runs in batch mode and refuses unknown host keys. The phone must trust the cable
Mac and have Developer Mode enabled. No USB/IP driver, root access or SIP change
is used by this route.

## Setup

1. While the paired phone is nearby, capture its service identity using the
   existing command (keep the resulting profile private):

   ```sh
   debagr --capture-device-profile --peer <phone-Tailscale-name> \
     --bonjour-host <phone.local> --profile /absolute/device-profile.json
   ```

2. Plug the phone into the cable Mac. Identify its **cable-side** scoped
   link-local IPv6 address and its current RemotePairing port. This version
   requires those values explicitly; it does not scan or automatically discover
   the endpoint. Use `ifconfig` and `ndp -an` on the cable Mac to inspect the
   USB network interface and its neighbor. A neighbor address alone does not
   establish device identity or identify the RemotePairing port. Do not substitute
   the Mac's own address, a Wi-Fi endpoint, or the Lockdown service port.

3. On the Builder, run (all addresses and paths below are placeholders):

   ```sh
   debagr --cable connect --ssh user@cable-mac \
     --peer <cable-Mac-Tailscale-IPv4> \
     --endpoint 'fe80::<phone-address>%en9' --port <RemotePairing-port> \
     --profile /absolute/device-profile.json \
     --tool /Applications/Debagr.app/Contents/MacOS/Debagr
   ```

The endpoint scope belongs to the **cable Mac**. The command uses the saved
Bonjour identity, without changing the saved profile, and publishes a local
proxy on the Builder. It starts one SSH-owned helper on the cable Mac. That
helper binds data listeners to the cable Mac's Tailscale address and permits
only the Builder's Tailscale source IP. Requests can open unprivileged ports
only on the fixed cable endpoint. SSH authenticates control; Apple pairing
authenticates the device session. Limit VPN access using your Tailscale policy.

The Builder opens each upstream listener before starting its local listener.
It preopens the saved tunnel range before advertising the pairing service and
learns additional ports from the existing `remotepairingd` log watcher. Preopening
is needed because Xcode can connect before a log event reaches the watcher.
Ctrl-C cancels startup; Ctrl-C or loss of SSH stops the Builder bridge;
closing the SSH input releases host listeners. Stop the usual direct-device
bridge for this phone before starting the cable route to avoid port conflicts.

## Acceptance and current limits

This is an implementation prototype, **not full hardware-accepted support**. Before
relying on it, disable phone Wi-Fi and verify the expected UDID using
`debagr --status --device <UDID> --timeout 30 --json`, then install and launch a
signed app through `--deploy-app ... --device <UDID> --launch --json`. Require
`installed: true` and `launched: true`. Verify Xcode debugger attachment separately.
A listener, Bonjour entry or successful SSH handshake does not prove any of these.

There is no automatic endpoint/port discovery, GUI setup, cable replug recovery
or host restart recovery. Restart with a newly verified endpoint/port after
changes. One fixed endpoint is used per process; the host never switches phones
automatically. Device identity ultimately depends on Apple's existing trust;
the host does not inspect USB serial numbers. The host caps each session at 256
forwarded ports; restart after reaching that limit. Windows is out of scope.

On 13 November 2026, a Mac mini Builder reached an already paired iPhone 16 Pro
over a MacBook Pro cable host with phone Wi-Fi disabled. The Builder returned
`state: ready`, then installed a signed LightApp device build with
`installed: true` and `launched: false`. Socket inspection confirmed the host
listener bound to its Tailscale address, reached from the Builder through
Tailscale. This proves authenticated connectivity and installation for that run;
launch and debugger attachment were not tested. The Device panel exposed only
simulators during this test.

Two issues were found and fixed during that run: Tailscale `utun` interfaces
were absent from Network.framework's path interface list (exact-address binding
now avoids that lookup), and opening tunnel listeners only after log events
was too late for Xcode's immediate connection attempt. Preopening the saved
tunnel range resolved the observed connection-refused loop.

Other devices/OS versions, changed service identities, tunnel ranges outside
the saved window and recovery still require physical-device validation. If the
cable-side service is unavailable, this route cannot create it merely by opening
relay sockets.

### 20 November 2026 iPad test

The MacBook Pro and an unlocked iPad Pro shared Wi-Fi. The iPad was also
plugged into the Pro. The Mac mini was on a different network. Both Macs ran
the release binary built from `65e1dc3`. The Pro's Apple tools reported a wired,
paired connection. The iPad's USB link advertised RemotePairing on port 49152
with a different service instance name from the saved Wi-Fi profile. The test
used a fresh profile matching the cable advertisement.

The mini started the bridge and resolved its local Bonjour advertisement. In a
separate TCP check, the Pro's cable helper held simultaneous established
connections from the mini and to the iPad's verified USB address on port 49152.
Six additional tunnel ports were already in use during bridge startup.

Apple's device list on the mini contained no matching iPad before or during the
test. Three readiness checks and one native `devicectl manage pair` attempt on
the mini returned CoreDevice error 1000 (device not found). The mini did not
install or launch test build 5. After the test, the mini's original iPhone relay
resumed and the iPhone returned `state: ready`.
