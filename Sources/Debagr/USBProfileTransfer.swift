import Foundation

enum USBProfileTransfer {
  static func run(_ options: CommandLineOptions) throws {
    if options.agentCommand == "usb-services" {
      let capture = BonjourCapture()
      defer { capture.stop() }
      let result = LockedValue<[BonjourDevice]>([])
      let failure = LockedValue<Error?>(nil)
      let finished = DispatchSemaphore(value: 0)
      try capture.startZoneCaptureAll(
        onFailure: { error in
          failure.set(error)
          finished.signal()
        }, onDevices: { result.set($0) })
      _ = finished.wait(timeout: .now() + options.timeout)
      if let error = failure.get() { throw error }
      let services = result.get().filter { !$0.hostName.hasPrefix("debagr-") && !$0.txt.isEmpty }
      let hosts = Dictionary(grouping: services, by: \.hostName)
      let inventory = USBServiceInventory(
        services: hosts.keys.sorted().compactMap { host in
          hosts[host]?.first.map { USBNearbyService(host: host, name: $0.suggestedDisplayName) }
        })
      try write(inventory)
    } else {
      guard let peer = options.peerName, let host = options.bonjourHost else {
        throw CLIError.invalidDirectDeviceOptions
      }
      let profile = try DirectDeviceApplication.capturedProfile(
        peerName: peer, host: host,
        timeout: options.timeout, provider: options.provider)
      // This explicit private-transfer command is consumed over SSH, never by public diagnostics.
      try write(profile)
    }
  }

  private static func write<Value: Encodable>(_ value: Value) throws {
    FileHandle.standardOutput.write(try JSONEncoder().encode(value))
    FileHandle.standardOutput.write(Data([10]))
  }
}
