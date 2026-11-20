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

## Mac cable service sharing

The only USB sharing route forwards device network services from another Mac;
it does not import the raw USB device. It requires existing Apple pairing with
the Builder. The cable endpoint is a fixed, scoped link-local IPv6 address for
one session. Debagr does not silently select another phone after reconnect.

SSH authenticates the control channel. Batch mode and strict host-key checking
are required; there is no password prompt, host-key auto-acceptance, or Debagr
control listener. The remote helper accepts only bounded, unprivileged port
requests. It cannot be told to forward an arbitrary host. Each session is
limited to 256 listeners pairs, and terminates when SSH input closes.

Data listeners bind to the cable Mac's exact Tailscale IPv4 address and accept
only the selected Builder's Tailscale source address. Tailscale carries that
traffic; apply its access rules to restrict the two Macs. Apple pairing protects
the device session. Relay payloads and Bonjour TXT values are not logged.

The route starts no privileged USB tool or driver, requests no administrator
password, and makes no changes to System Integrity Protection. Legacy discovery,
role-pairing and raw-USB setup services are removed. This build ignores their
old preferences and does not delete historical data or third-party software.

## Stored data and remote access

Connection profiles and receipts remain under `~/.config/debagr/`; retain the
existing private file permissions and avoid sharing profiles. Apple owns pairing
keys, and SSH retains its own identity and host-key management. Temporary test
artifacts and captured output can include private endpoints; keep them private.
See [privacy and removal](PRIVACY.md).

## Preview limits

The cable bridge is experimental. One physical iPhone has passed authenticated
readiness and signed-app installation with Wi-Fi off. Launch, debugger, automatic
discovery, reconnect and broader device/OS coverage remain incomplete. A live
listener or advertisement is not authenticated readiness or deployment proof.

## Reporting

Report vulnerabilities through GitHub
[private vulnerability reporting](https://github.com/radeknovis/homebrew-debagr/security/advisories/new)
on the public tap repository, which also publishes this policy as `SECURITY.md`.
Responses are best effort during the technical preview, and only the latest
release receives fixes. Do not file public issues containing device identifiers,
hostnames, tailnet addresses, pairing material, logs, or diagnostics.
