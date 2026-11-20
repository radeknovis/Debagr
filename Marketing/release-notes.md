# Debagr 0.3.1 technical preview

Build 9 for Apple silicon. Use the Mac your device already trusts to deploy while the device is on another Wi-Fi network with its private VPN connected.

- **Use existing pairing** opens by default and guides you through selecting the device, its wireless service and its VPN address.
- **Pair via USB/IP** shares a cable from a nearby Mac to a remote Builder for Apple pairing. This experimental path requires separate USB tools, administrator approval on both Macs and virtual USB controller access on the Builder. The current experimental importer requires SIP off on the Builder.
- **USB via Mac** provides the separate cable bridge for an already paired phone.
- The setup guides, screenshots and matching Claude Code and Codex plugins accompany this release.

In the USB/IP hardware test, the Mac mini installed and launched its signed iPad app using pymobiledevice3. First-time Apple Trust, native Debagr deployment and subsequent independent wireless deployment remain unverified for that route.

Install the signed DMG or use `brew install --cask radeknovis/debagr/debagr`. Existing Homebrew users can run `brew upgrade --cask radeknovis/debagr/debagr`. Managed VPN deployment requires macOS 26 or later, Xcode, Wi-Fi and a private VPN. Use the matching 0.3.1 plugin archive for your agent.
