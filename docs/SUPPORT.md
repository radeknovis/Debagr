# Debagr support

## Before requesting help

1. Confirm Xcode is installed and `xcrun devicectl list devices` runs.
2. Connect the Target Device over USB, trust the Mac, and enable Developer Mode.
3. Keep the device unlocked for the first install so Xcode can mount its
   developer disk image.
4. Confirm the signed `.app` exists on the build server.
5. For remote use, confirm Remote Login works before involving Debagr; if using
   Tailscale, confirm the caller can reach the build server's tailnet hostname.
6. Run the deploy command from the setup guide locally once
   (`debagr --deploy-app /absolute/path/App.app --device <UDID> --launch --json`),
   then invoke that same command through SSH.
7. In Debagr, choose **Copy Diagnostics** and review the report before sharing.

Diagnostics include app/macOS versions, prerequisite status, visible device
names, Bonjour hosts, and ports.
Reports exclude TXT values and traffic contents.

## What the 0.3.0 preview supports

The supported path is **Use existing pairing**: an iPhone that already trusts
the build server, reached over Wi-Fi and Tailscale. One remote iPhone install
and OS-confirmed launch over Tailscale was verified on real hardware on
10 November 2026. Managed remote deployment needs macOS 26 or later on the Mac.

The following are in the app but have not passed hardware acceptance for
0.3.0. Reports about them are welcome; fixes are not promised.

| Area | Status in 0.3.0 |
| --- | --- |
| Mac cable service bridge | Experimental CLI; existing pairing, SSH and Tailscale required. One iPhone readiness/install verified; launch/debugger pending. |
| iPad | Not verified. |
| VPN providers other than Tailscale | Not verified. |
| macOS 13 to 15 | Not verified. |
| Clean-Mac first launch and offline first launch | Not verified. |
| Recovery after restart, sleep and wake, network change, revoked trust, or denied Local Network permission | Not verified. |
| Homebrew upgrade from 0.2.0 to 0.3.0 | Not verified. |

## Cable sharing and removal

See [the cable guide](CABLE_SHARING.md). Pair the phone directly with the Builder
first, then connect it by USB to the cable Mac. Keep the phone unlocked and the
cable attached. If the cable endpoint or port changes, stop the bridge and
restart with newly verified values. Use `--status` against the explicit Apple
identifier, then verify installation and launch separately.

Stop a cable bridge with Ctrl-C before quitting. Disable Launch at Login,
quit Debagr and remove the app. Back up profiles before removing
`~/.config/debagr/` or clearing the `com.debagr.app` preferences. Older setup data
under `~/Library/Application Support/Debagr/` is ignored; review before deleting.
Removing the app does not revoke Apple trust or uninstall deployed device apps,
VPNs or separately installed third-party tools. See [privacy](PRIVACY.md).

## Preview support promise

The technical preview is best-effort and supports only the matrix in
[`COMPATIBILITY.md`](COMPATIBILITY.md). Report problems in the public tap's
[Issues](https://github.com/radeknovis/homebrew-debagr/issues) without device identifiers, hostnames,
VPN addresses, or diagnostics. Send security or privacy reports, and diagnostics
a maintainer asks for, through
[private vulnerability reporting](https://github.com/radeknovis/homebrew-debagr/security/advisories/new).
The service owner is Radek Novak. Add a support address, response window,
business hours, and refund route before sale.
