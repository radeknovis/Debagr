import Darwin
import Foundation

struct ConfiguredDevice: Codable, Equatable {
  let deviceIdentifier: String
  let displayName: String
  let peerName: String
  var interfaceName: String = "auto"
  var enabled: Bool = true
  var profile: DeviceProfile
  var kind: TargetDeviceKind? = nil

  func validate() throws {
    guard !deviceIdentifier.isEmpty, !peerName.isEmpty,
      !deviceIdentifier.contains(where: { $0.isWhitespace || $0.isNewline }),
      !profile.bonjourTXT.isEmpty
    else { throw CLIError.invalidDirectDeviceOptions }
    try profile.validate()
  }

  func hasSameConnection(as other: ConfiguredDevice?) -> Bool {
    guard let other else { return false }
    return deviceIdentifier == other.deviceIdentifier && peerName == other.peerName
      && interfaceName == other.interfaceName && profile.bonjourName == other.profile.bonjourName
      && profile.bonjourTXT == other.profile.bonjourTXT && profile.peerIP == other.profile.peerIP
      && profile.remotePort == other.profile.remotePort
      && profile.provider == other.profile.provider
  }
}

struct ManagedDeviceStore {
  var url: URL = ProfileStore.defaultStore.url.deletingLastPathComponent()
    .appendingPathComponent("managed-device.json")

  func load() throws -> ConfiguredDevice? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let device = try JSONDecoder().decode(ConfiguredDevice.self, from: Data(contentsOf: url))
    try device.validate()
    return device
  }

  func save(_ device: ConfiguredDevice) throws {
    try device.validate()
    try withLock { try Self.writePrivate(JSONEncoder().encode(device), to: url) }
  }

  func remove() throws {
    try withLock {
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    }
  }

  func toggleEnabled() throws {
    try withLock {
      guard var device = try load() else { return }
      device.enabled.toggle()
      try Self.writePrivate(JSONEncoder().encode(device), to: url)
    }
  }

  func learn(port: UInt16, for expected: ConfiguredDevice) throws {
    try withLock {
      guard var saved = try load(), saved.hasSameConnection(as: expected) else { return }
      saved.profile = saved.profile.learningTunnelPort(port)
      try Self.writePrivate(JSONEncoder().encode(saved), to: url)
    }
  }

  private func withLock(_ body: () throws -> Void) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let descriptor = open(
      url.appendingPathExtension("lock").path,
      O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteNoPermission) }
    try body()
  }

  static func writePrivate(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    if url.deletingLastPathComponent() == ProfileStore.defaultStore.url.deletingLastPathComponent()
    {
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
    }
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".debagr-private-\(UUID().uuidString)")
    let descriptor = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer {
      try? handle.close()
      try? FileManager.default.removeItem(at: temporary)
    }
    try handle.write(contentsOf: data)
    try handle.synchronize()
    guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }

  }
}

struct DeploymentReceipt: Codable {
  let deviceIdentifier: String
  let bundleIdentifier: String
  let launched: Bool
  let completedAt: Date

  static var url: URL {
    ManagedDeviceStore().url.deletingLastPathComponent().appendingPathComponent(
      "last-deployment.json")
  }

  static func record(_ result: DeploymentResult, deviceIdentifier: String) throws {
    let receipt = DeploymentReceipt(
      deviceIdentifier: deviceIdentifier,
      bundleIdentifier: result.bundleIdentifier, launched: result.launched, completedAt: Date())
    try ManagedDeviceStore.writePrivate(JSONEncoder().encode(receipt), to: url)
  }

  static func latest() -> DeploymentReceipt? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(DeploymentReceipt.self, from: data)
  }
}

enum ManagedDeviceError: LocalizedError {
  case relayAlreadyRunning

  var errorDescription: String? {
    "A Debagr relay already owns this control port. Stop that relay before connecting here."
  }
}

final class RelayLease {
  private var descriptor: Int32 = -1

  init(port: UInt16, directory: URL = ProfileStore.defaultStore.url.deletingLastPathComponent())
    throws
  {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    descriptor = open(
      directory.appendingPathComponent("relay-\(port).lock").path,
      O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw ManagedDeviceError.relayAlreadyRunning }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(descriptor)
      descriptor = -1
      throw ManagedDeviceError.relayAlreadyRunning
    }
  }

  deinit {
    if descriptor >= 0 { close(descriptor) }
  }
}

/// Owned by the menu-bar app and called only on its serial work queue.
final class ManagedDeviceRuntime: @unchecked Sendable {
  private var relay: DirectDeviceApplication?
  private var activeDevice: ConfiguredDevice?
  private var activeAddress: String?
  let store = ManagedDeviceStore()

  func refresh() throws -> String {
    guard let device = try store.load() else {
      stop()
      return "Set up a remote device…"
    }
    guard device.enabled else {
      stop()
      return "Remote deployment disconnected"
    }
    if relay == nil,
      (try? DeviceDeployer().checkReady(deviceIdentifier: device.deviceIdentifier, timeout: 3))
        != nil
    {
      return "\(device.displayName) — Ready (existing Apple connection)"
    }
    do {
      let binding = try NetworkSupport.resolveInterface(named: device.interfaceName)
      if !device.hasSameConnection(as: activeDevice) || activeAddress != binding.ipv4Address
        || relay?.isHealthy == false
      {
        stop()
        let application = DirectDeviceApplication(
          device: device,
          onTunnelPort: { [store] port in
            // Learn the next allocation window without exposing ports in normal setup.
            try? store.learn(port: port, for: device)
          })
        try application.start()
        relay = application
        activeDevice = device
        activeAddress = binding.ipv4Address
      }
    }
    try DeviceDeployer().checkReady(deviceIdentifier: device.deviceIdentifier, timeout: 3)
    return "\(device.displayName) — Ready for deployment"
  }

  func stop() {
    relay?.stop()
    relay = nil
    activeDevice = nil
    activeAddress = nil
  }
}
