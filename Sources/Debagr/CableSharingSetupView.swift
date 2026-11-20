import AppKit
import SwiftUI

struct CableSharingSetupView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Pair with this Builder first").font(.headline)
      Text(
        "Connect your iPhone or iPad to this Builder and pair it in Xcode once. Then move its USB cable to the other Mac. Keep that cable connected while deploying."
      )
      Text("Start the cable bridge from Terminal").font(.headline)
      Text(
        "The cable bridge requires a saved device profile, the phone’s cable-side address and RemotePairing port, and trusted SSH access to the cable Mac."
      )
      Text("debagr --cable help").font(.system(.callout, design: .monospaced)).textSelection(
        .enabled)
      Button("Open cable sharing guide") {
        if let resources = Bundle.main.resourceURL {
          NSWorkspace.shared.open(resources.appendingPathComponent("Cable-Sharing.md"))
        }
      }
      Text(
        "Authenticated connectivity and app installation have been verified on one iPhone with Wi-Fi off. Automatic discovery, reconnect, launch and debugger acceptance remain incomplete."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .font(.callout)
  }
}
