# Debagr security

## Current boundaries

- Debagr opens no deployment network listener. Remote authentication and access
  control are delegated to the build server's SSH configuration.
- Deployments require an explicit local `.app` path and explicit device UDID.
- `xcrun` and `devicectl` receive argument arrays directly; no shell evaluates
  app paths, identifiers, or bundle IDs.
- RemotePairing payloads are forwarded opaquely and never logged or decrypted.
- Tailscale destinations must be online IPv4 peers in `100.64.0.0/10`.
  Alternative-provider profiles require an explicitly selected RFC1918 or CGNAT
  IPv4 address; public and link-local destinations are rejected.
- Listeners bind to the selected local interface; LAN clients are denied unless
  the explicit lab-only `--allow-lan` flag is used.
- Child processes use fixed executable paths, argument arrays, and owned process
  identifiers.
- App diagnostics omit Bonjour TXT records and payload data.

## Remote access boundary

Anyone allowed to invoke Debagr through SSH acts with that macOS account's
device-development privileges. Require public-key authentication, least-
privilege accounts, a private network such as Tailscale, and normal SSH audit
and revocation practices. Do not expose Remote Login directly to the internet.

## Reporting

Do not file public issues containing device identifiers, hostnames, tailnet
addresses, pairing material, logs, or diagnostics. Add a monitored private
security-reporting address and response policy before public distribution.
