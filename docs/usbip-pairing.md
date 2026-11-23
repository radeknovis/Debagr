# Experimental: Pair via USB/IP (Temporary Raw USB)

> **Experimental Route:** This guided two-Mac workflow exists solely to let Apple perform **initial USB pairing** when an unpaired iPhone or iPad is physically with you away from the Builder Mac. Once Apple pairing completes, Debagr immediately tears down the USB/IP link and hands off to normal wireless VPN usage.

## Security & Tooling Policy

- **No bundled third-party drivers:** Debagr never bundles or installs USB/IP drivers, kernel extensions, or system extensions. You install and audit any third-party `usbip` CLI tool yourself.
- **Zero silent security weakening:** Debagr never modifies SIP, disables Gatekeeper, or silently runs privileged commands.
- **Explicit approval required:** Every USB/IP attach/bind step requires explicit confirmation of the security notice (`PrivilegedApprovalReceipt`).
- **On-demand & authenticated:** Coordination runs on demand only (no always-on daemon) and uses ephemeral `Curve25519` ECDH + 6-digit SAS mutual role verification + `ChaChaPoly` AEAD encryption.

## Workflow Steps

1. **Check Prerequisites on Both Macs:**
   ```bash
   debagr experimental usbip check
   ```
   (Pass `--usbip-path /custom/path/to/usbip` if installed outside `/opt/homebrew/bin` or `/usr/local/bin`.)
2. **Choose Roles in the Debagr UI (Experimental Tab):**
   - **Builder Mac:** Owns Xcode and Apple trust.
   - **Client Mac:** Where the unpaired phone is temporarily connected over USB.
3. **Discover Peer & Verify 6-Digit Code:** Discover on demand or enter the private VPN IP, then confirm the matching 6-digit authentication code on both Macs.
4. **Approve & Pair:** Review the exact command and confirm the security notice. Debagr supervises the temporary link while `xcrun devicectl manage pair` completes.
5. **Automatic Teardown & Wireless Handoff:** Once `devicectl` confirms `pairingState == paired`, Debagr stops the USB/IP tool and transitions directly into the primary **Wireless Setup** wizard.
