# Debagr privacy policy draft

Draft updated: 22 October 2026. Owner and counsel review are required before
publication.

Debagr's technical-preview app works locally. It does not include analytics,
advertising, crash-reporting SDKs, customer accounts, or a Debagr cloud service.
It does not inspect or log RemotePairing payloads or Bonjour TXT values.

The app processes locally visible device names, Bonjour hostnames, identifiers,
ports, app bundle paths and identifiers during deployment, `devicectl` results,
macOS version, Developer Tools availability, and Tailscale CLI location to
display status, deploy apps, and create diagnostics. This information stays on
the build-server Mac unless the user explicitly copies a diagnostics report and
sends it to support.
Copied reports omit TXT records and traffic contents but can contain device
names, hostnames, and ports; users should review them before sharing.

Debagr stores device connection profiles and the last deployment receipt under
`~/.config/debagr/`. Profiles can contain device identifiers, private VPN
endpoints, and captured Bonjour service metadata. Files are written with mode
0600 and the app creates its data directory with mode 0700. They persist until
the user removes them; keep them private and do not include them in public
reports. Apple pairing keys remain managed by Apple on the paired Mac.

The optional sponsorship links, when activated, open GitHub Sponsors or Ko-fi.
Those services process their own account and payment data under their policies;
Debagr does not receive payment credentials or embed a payment SDK.

For any future commercial checkout, licence delivery, payments, taxes, and refunds will be handled by the
merchant-of-record named at purchase. Its privacy policy applies to data it
collects. Add the selected processor, data categories, retention periods,
international-transfer basis, and deletion route before opening checkout.

Users can remove local app data by quitting Debagr, disabling Launch at Login,
moving the app to Trash, and deleting its preferences with:

```sh
defaults delete com.debagr.app
```

Removing the app does not remove its connection profiles. To remove all local
Debagr data, first quit Debagr and back up any profiles you want to retain, then
remove only `~/.config/debagr/`. This does not revoke Apple pairing, uninstall
your VPN, or remove apps previously deployed to a device.

Add the legal owner name, postal address, privacy contact, and jurisdiction
before publication.
