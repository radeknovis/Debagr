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
names, Bonjour hosts, and ports. The report from the **Initial device pairing**
screen also lists the Macs it found with their names and private addresses.
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
| USB/IP initial pairing | Experimental. Needs a separately installed, locally patched Longcable server, usbip-macos, an administrator password, and System Integrity Protection turned off on the Builder. Not hardware-accepted. |
| VirtualHere initial pairing | Experimental. Needs separately installed VirtualHere software and SSH access. Not hardware-accepted. |
| Builder/Client linking of two Macs | Experimental. Not hardware-accepted. |
| iPad | Not verified. |
| VPN providers other than Tailscale | Not verified. |
| macOS 13 to 15 | Not verified. |
| Clean-Mac first launch and offline first launch | Not verified. |
| Recovery after restart, sleep and wake, network change, revoked trust, or denied Local Network permission | Not verified. |
| Homebrew upgrade from 0.2.0 to 0.3.0 | Not verified. |

## Network services to know about

Debagr does not listen on the network for deployment commands. The
**Initial device pairing** screen uses two services, peer discovery on TCP
49388 and role pairing on TCP 49389. They run only while that screen is open,
while a Builder or Client role is saved on the Mac, or while you run
`debagr --usbip discover` or `debagr --usbip advertise` yourself. If Macs do not find each
other, allow those ports, and TCP 3240 for USB/IP, between the two Macs in the
firewall and in the VPN's access rules, and allow Debagr under Local Network in
System Settings. To switch the services off, choose **Show Diagnostics**, then
**Unpair This Mac**, and close the window. [Security](SECURITY.md) lists what
other devices on the network can read while they run.

## Removing Debagr

1. If a USB/IP setup connection is running, open **Initial device pairing**
   and choose **Stop Setup Connection** on the Builder, then on the Client. It
   keeps running after the app quits.
2. If this Mac is linked as Builder or Client, choose **Show Diagnostics**,
   then **Unpair This Mac**, on both Macs.
3. Turn off **Launch at Login**, quit Debagr, and move `Debagr.app` to Trash.
4. Delete the preferences. They hold the saved role, the other Mac's public
   key, and the selected USB tools:

   ```sh
   defaults delete com.debagr.app
   ```

5. Remove the stored data if you want to discard all saved Debagr setup. Keep a
   backup of any profile you need first.

   ```sh
   rm -rf ~/.config/debagr
   rm -rf ~/Library/Application\ Support/Debagr
   ```

| Location | Contents |
| --- | --- |
| `~/.config/debagr/` | Private connection profiles, the managed remote device, and the last deployment receipt |
| `~/Library/Application Support/Debagr/role-sync-key.raw` | This Mac's private signing key for role pairing |
| `~/Library/Application Support/Debagr/USBIPSessions/` | Folders and logs of USB/IP setup connections |

Removing Debagr does not revoke Apple pairing, uninstall the VPN, or uninstall
deployed device apps. It also leaves the separately installed USB tools in
place: Longcable with its `/Library/Application Support/Longcable/` settings,
usbip-macos, and VirtualHere. If you turned System Integrity Protection off
for USB/IP, turn it back on in macOS Recovery with `csrutil enable`.

## Preview support promise

The technical preview is best-effort and supports only the matrix in
[`COMPATIBILITY.md`](COMPATIBILITY.md). Report problems in the public tap's
[Issues](https://github.com/radeknovis/homebrew-debagr/issues) without device identifiers, hostnames,
VPN addresses, or diagnostics. Send security or privacy reports, and diagnostics
a maintainer asks for, through
[private vulnerability reporting](https://github.com/radeknovis/homebrew-debagr/security/advisories/new).
The service owner is Radek Novak. Add a support address, response window,
business hours, and refund route before sale.
