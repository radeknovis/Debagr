# Debagr Security & Privacy Model

## 1. Threat Model & Trust Boundaries

- **Builder Mac owns Apple trust:** Debagr never copies, exports, or shares Apple lockdown pairing records or developer signing identities.
- **No deployment network listener:** Debagr opens no network port for CLI or MCP commands. Remote callers authenticate through the user's existing **SSH** server on the Builder Mac; local AI coding agents use stdin/stdout (`debagr mcp`).
- **Private VPN validation:** All configured VPN endpoints are validated against private non-routable ranges via `IPValidation`:
  - RFC 1918 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`)
  - RFC 6598 CGNAT (`100.64.0.0/10`, used by Tailscale, Headscale, NetBird)
  - IPv6 ULA (`fc00::/7`)
  - Public IPs, loopback (`127.0.0.0/8`, `::1`), link-local (`169.254.0.0/16`, `fe80::/10`), and multicast addresses are rejected.

## 2. Local Storage & Permissions

- Data root: `~/Library/Application Support/Debagr` (overridable via `DEBAGR_HOME` for testing).
- Directory created with POSIX permissions `0700`.
- `config.json`, `receipts.json`, and `bridge-state.json` written atomically using `O_CREAT | O_EXCL | O_NOFOLLOW` + `fchmod 0600` + `fsync` + atomic `rename`.
- Symlink targets at destination file paths are refused.

## 3. Diagnostic Redaction

Exported diagnostics (`debagr doctor`, `debagr config show`, and UI *Copy Redacted Diagnostics*):
- Redact device UDIDs (`0000...C01C`).
- Never emit `wirelessIdentity.bonjourInstanceName` (`<mac>@<pairID>`) or `txtRecords`.
- Mask private VPN IP octets when strict redaction is active (`100.64.*.*`).
- Scrub PEM blocks or Bonjour identity strings from freeform transition reasons.

## 4. Experimental Routes Security

- **Experimental Cable Service Bridge:** Binds TCP relays strictly to `127.0.0.1` (never `0.0.0.0`). Relies exclusively on the user's SSH tunnel over the private VPN, requires no root privileges, no raw USB forwarding, and no SIP changes.
- **Experimental Pair via USB/IP:**
  - Zero background listeners; discovery runs on demand only.
  - Ephemeral `Curve25519` ECDH + `HKDF<SHA256>` + 6-digit Short Authentication String (SAS) mutual role authentication + `ChaChaPoly` AEAD encrypted control messages with monotonic replay counters.
  - Never bundles third-party USB/IP kernel/system extensions.
  - Requires an explicit `PrivilegedApprovalReceipt` (`userConfirmedSecurityNotice == true`) before supervising any separately installed external `usbip` binary, and tears down immediately once Apple pairing is verified.
