# Debagr for Claude Code and Codex

Ask your coding agent to install and launch your signed app on your device—even
when the device and its paired Mac are on separate Wi-Fi networks, connected
through a private VPN.

Current target devices are iPhone and iPad. Mac targets are a possible future
extension; deploying macOS apps to a Mac is not implemented. The build Mac and
target device are separate roles.

## Set up the paired Mac and device

Debagr's setup window keeps network and device selection together. Validation
and recovery messages appear inline; saved-profile imports use a file-picker
sheet. Closing the window leaves the menu-bar app running.

1. Install Debagr in `/Applications` on the Mac that will build and deploy your app.
   Install Xcode, pair the device over USB, grant trust, and enable Developer Mode.
2. Connect that Mac and device to your chosen VPN. While the device's Bonjour service
   is available locally, open Debagr and choose **Set Up Remote Device…**.
   Choose your VPN provider, then select the Apple device, its local Bonjour
   service, and the same device’s VPN device or private IPv4 address.
   Choose **Save & Connect**.
3. Leave Debagr running in that Mac user's logged-in session. Enable **Launch at
   Login** if desired. The device can now move to another Wi-Fi network; keep
   the VPN connected and unlock it for deployment. Cellular-only operation is
   unsupported.
4. On the computer running your coding agent, confirm existing SSH access to the
   paired Mac as that same user. A local agent on the paired Mac can invoke the
   CLI directly. Build a signed device `.app` using your project's normal workflow.

See [network provider setup](NETWORK_PROVIDERS.md) for Tailscale, Headscale, ZeroTier,
NetBird, and WireGuard. Alternative providers still need hardware validation.

The plugin supplies instructions. Install the Debagr app separately; the plugin
does not install Xcode or a VPN, establish SSH access, or change Apple trust.
One remote device is supported. The paired Mac retains signing and pairing data.

## Install the plugin

Extract the ZIP for your client and keep the extracted directory at a stable
location. Run the following commands inside that extracted directory. You can
also run them from a Debagr source checkout to test unpublished changes.

### Claude Code

```sh
claude plugin marketplace add .
claude plugin install debagr@debagr-plugins
```

Start a new Claude Code session. Invoke `/debagr:debagr-deploy` or ask for a
deployment in plain language. To test without installing, start
`claude --plugin-dir .` from the plugin directory.

### Codex

```sh
codex plugin marketplace add .
codex plugin add debagr@debagr-plugins
```

Start a new Codex session and ask it to use `debagr-deploy`. This plugin requires
desktop execution with shell and SSH access; cloud-only chat cannot run Debagr.
The Codex manifest declares that requirement.

Install one Debagr plugin per client. If you previously copied the standalone
skill into that client's skills directory, remove that extra copy after
confirming the plugin loads.

## Request a remote deployment

Tell the agent the paired Mac's SSH alias, intended device, and either the project
build instructions or an absolute path to a signed device `.app` on that Mac:

> Use Debagr on `build-server` to install and launch
> `/Users/me/Builds/MyApp.app` on my target device. The device is on another Wi-Fi network.

The agent should select the device, check readiness, then install and launch.
Success requires the expected bundle identifier and `installed: true` and
`launched: true`. If unlocking, trust, or networking needs attention, follow
the recovery instruction and retry after resolving it. A launch confirmation
does not establish that the app's UI works correctly.

## Build and validate packages

From a source checkout, run:

```sh
python3 scripts/package-plugins.py
claude plugin validate .claude-plugin/plugin.json
claude plugin validate .claude-plugin/marketplace.json
```

The packaging command creates `dist/debagr-claude-code-0.2.0.zip` and
`dist/debagr-codex-0.2.0.zip`, each with a `.sha256` checksum. It checks manifest
version agreement, archive integrity, and byte-for-byte shared skill contents.
For a downloaded ZIP, check its checksum before extraction:

```sh
shasum -a 256 -c debagr-codex-0.2.0.zip.sha256
```

Both manifests reference `./Skills/`. The app and both plugins share
`Skills/debagr-deploy`; edit that source rather than copies inside ZIPs. Bump
both manifest versions together for a plugin release. These packages contain
only instructions, metadata, and documentation; no private profiles or binaries.

Before publishing, test each client in a new session and verify a real install
and launch while the device and Mac are on separate networks. Check locked-device
and unavailable-network recovery too. Package validation alone is not a hardware
acceptance test. Public catalog submission and the signed app release are
separate release steps.
