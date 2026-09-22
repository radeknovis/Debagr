# Debagr privacy policy draft

Effective date: 22 September 2026. Owner and counsel review are required before
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

Checkout, licence delivery, payments, taxes, and refunds will be handled by the
merchant-of-record named at purchase. Its privacy policy applies to data it
collects. Add the selected processor, data categories, retention periods,
international-transfer basis, and deletion route before opening checkout.

Users can remove local app data by quitting Debagr, disabling Launch at Login,
moving the app to Trash, and deleting its preferences with:

```sh
defaults delete com.debagr.app
```

Add the legal owner name, postal address, privacy contact, and jurisdiction
before publication.
