# Debagr for Claude Code and Codex

Ask your coding agent to install and launch your signed app on your device—even
when the device and its paired Mac are on separate Wi-Fi networks, connected
through a private VPN.

Current target devices are iPhone and iPad. Mac targets are a possible future
extension; deploying macOS apps to a Mac is not implemented. The build Mac and
target device are separate roles.

## Set up the paired Mac and device

Debagr's Connections window keeps network and device selection together. Validation
and recovery messages appear inline; saved-profile imports use a file-picker
sheet. Closing the window leaves the menu-bar app running.

1. Install Debagr 0.3.0 in `/Applications` on the Mac that will build and deploy your app.
   Install Xcode, pair the device over USB, grant trust, and enable Developer Mode.
2. Connect that Mac and device to your chosen VPN. While the device's Bonjour service
   is available locally, choose **Open Debagr** in the menu-bar menu. With no saved
   device, the window opens on **Use existing pairing**. Select the paired Apple
   device and choose **Continue**. Choose your VPN provider, the same device's
   VPN device or private IPv4 address, and its local Bonjour service, then
   choose **Continue**. Confirm that the selections refer to the same physical
   device, then choose **Save & check connection**.
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
Managed remote deployment needs macOS 26 or later on that Mac.

### Mac cable service sharing

The Builder owns the existing Xcode pairing. A cable host is another Mac with
the phone plugged in. The **USB via Mac** tab explains the CLI route;
[the cable guide](CABLE_SHARING.md) lists the explicit endpoint, port, profile,
Tailscale and trusted SSH requirements. The phone does not need Wi-Fi on this
route. For a new Builder, the separate [USB/IP setup](usbip.md) requires user interaction on the device. Authenticated readiness and
installation passed one physical-iPhone test; launch, debugger and recovery
acceptance remain incomplete.

### Verified and not yet verified

Verified on hardware: one remote iPhone installation and OS-confirmed launch
over Tailscale on 10 November 2026 with a 0.3.0 candidate build. Not yet
verified: iPad, VPN providers other than Tailscale, first launch on a clean or
offline Mac, recovery after restart, sleep, network change, revoked trust or
denied Local Network permission, macOS 13 to 15, and the Homebrew upgrade from
0.2.0 to 0.3.0.

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

In the Debagr window, **Agent tools** lists the setup steps, links to the plugin
downloads, and **Open Debagr skill…**, which reveals the bundled skill in Finder.

Tell the agent the paired Mac's SSH alias, intended device, and either the project
build instructions or an absolute path to a signed device `.app` on that Mac:

> Use Debagr on `build-server` to install and launch
> `/Users/me/Builds/MyApp.app` on my target device. The device is on another Wi-Fi network.

The agent should select the device, check readiness, then install and launch.
Success requires the expected bundle identifier and `installed: true` and
`launched: true`. If unlocking, trust, or networking needs attention, follow
the recovery instruction and retry after resolving it. A launch confirmation
does not establish that the app's UI works correctly.
