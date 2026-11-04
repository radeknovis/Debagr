# Debagr support

## Before requesting help

1. Confirm Xcode is installed and `xcrun devicectl list devices` runs.
2. Connect the Target Device over USB, trust the Mac, and enable Developer Mode.
3. Keep the device unlocked for the first install so Xcode can mount its
   developer disk image.
4. Confirm the signed `.app` exists on the build server.
5. For remote use, confirm Remote Login works before involving Debagr; if using
   Tailscale, confirm the caller can reach the build server's tailnet hostname.
6. Run the copied deploy command locally once, then invoke that same command
   through SSH.
7. In Debagr, choose **Copy Diagnostics** and review the report before sharing.

Diagnostics include app/macOS versions, prerequisite status, visible device
names, Bonjour hosts, and ports. They exclude TXT values and traffic contents.

## Removing Debagr

Turn off **Launch at Login**, quit Debagr, move `Debagr.app` to Trash, then
optionally delete preferences:

```sh
defaults delete com.debagr.app
```

The app also stores private connection profiles and the last deployment receipt
in `~/.config/debagr/`. Keep a backup if needed, then remove that directory only
if you want to discard all saved Debagr setup. Removing Debagr does not revoke
Apple pairing, uninstall the VPN, or uninstall deployed device apps.

## Preview support promise

The technical preview is best-effort and supports only the matrix in
[`COMPATIBILITY.md`](COMPATIBILITY.md). Report problems in the public tap's
[Issues](https://github.com/radeknovis/homebrew-debagr/issues) without device identifiers, hostnames,
VPN addresses, or diagnostics. Send security or privacy reports, and diagnostics
a maintainer asks for, through
[private vulnerability reporting](https://github.com/radeknovis/homebrew-debagr/security/advisories/new).
The service owner is Radek Novak. Add a support address, response window,
business hours, and refund route before sale.
