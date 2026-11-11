// Compiled only in a temporary copy by capture-marketing.py; never bundled in Debagr.
import AppKit

// Only the setup window is built: no menu-bar application, so no peer discovery, role sync,
// listener or device inventory can start. The model's refresh callbacks stay unset.
@MainActor
func captureMarketing() {
  let application = NSApplication.shared
  application.setActivationPolicy(.accessory)
  let controller = DeviceSetupWindowController(configured: nil)
  let model = controller.model
  let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
  let device = TargetDevice(
    identity: .apple(pairedMacNodeID: "preview-mac", identifier: "preview-device"),
    displayName: "My iPhone", kind: .iPhone, status: .paired)
  model.devices = [device]
  model.deviceID = device.identity.value
  model.peers = [
    SelectedNetworkPeer(hostname: "my-iphone", dnsName: "", ipAddress: "100.64.0.2", online: true)
  ]
  model.peerIP = "100.64.0.2"
  model.serviceHosts = ["My-iPhone.local"]
  model.serviceHost = "My-iPhone.local"
  model.discoveryStatus = "One paired device found"
  controller.window?.setContentSize(NSSize(width: 1000, height: 840))
  let captures: [(String, DeviceSetupModel.Page, NSAppearance.Name)] = [
    ("device-setup-light", .setup, .aqua), ("agent-tools-light", .guide, .aqua),
    ("device-setup-dark", .setup, .darkAqua), ("agent-tools-dark", .guide, .darkAqua),
  ]

  func capture(_ index: Int) {
    guard index < captures.count else { application.terminate(nil); return }
    let (name, page, appearance) = captures[index]
    model.deviceID = page == .guide ? "" : device.identity.value
    controller.window?.appearance = NSAppearance(named: appearance)
    controller.present(page: page)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
      guard let view = controller.window?.contentView,
        let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 1680, bitsPerSample: 8,
          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
          bytesPerRow: 0, bitsPerPixel: 0)
      else { fatalError("Could not create screenshot") }
      view.layoutSubtreeIfNeeded()
      bitmap.size = view.bounds.size
      view.cacheDisplay(in: view.bounds, to: bitmap)
      guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode screenshot")
      }
      do { try png.write(to: outputDirectory.appendingPathComponent(name + ".png")) } catch {
        fatalError("Could not save screenshot: \(error)")
      }
      print("Captured \(name) (sample data)")
      capture(index + 1)
    }
  }
  DispatchQueue.main.async { capture(0) }
  application.run()
}

MainActor.assumeIsolated { captureMarketing() }
