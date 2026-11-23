import Foundation

public protocol ConfigStoring: Sendable {
  var fileURL: URL { get }
  func load() throws -> DebagrConfig
  func save(_ config: DebagrConfig) throws
  func update(_ transform: @Sendable (inout DebagrConfig) throws -> Void) throws -> DebagrConfig
  func verifyPermissions() -> Bool
}

public protocol ReceiptStoring: Sendable {
  var fileURL: URL { get }
  func listRecent(limit: Int) throws -> [DeploymentReceipt]
  func append(_ receipt: DeploymentReceipt) throws
  func verifyPermissions() -> Bool
}

public protocol BridgeStateStoring: Sendable {
  var fileURL: URL { get }
  func load() throws -> BridgeStateSnapshot?
  func save(_ snapshot: BridgeStateSnapshot) throws
  func verifyPermissions() -> Bool
}

public final class FileConfigStore: ConfigStoring, @unchecked Sendable {
  public let fileURL: URL
  private let lock = NSLock()
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(directoryURL: URL = FileSecurity.dataDirectoryURL()) {
    self.fileURL = directoryURL.appendingPathComponent("config.json", isDirectory: false)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    self.encoder = enc

    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    self.decoder = dec
  }

  public func load() throws -> DebagrConfig {
    try lock.withLock {
      try loadUnlocked()
    }
  }

  public func save(_ config: DebagrConfig) throws {
    var sanitized = config
    sanitized.preferences.clamp()
    try lock.withLock {
      let data = try encoder.encode(sanitized)
      try FileSecurity.writeSecureFile(data, to: fileURL)
    }
  }

  public func update(_ transform: @Sendable (inout DebagrConfig) throws -> Void) throws
    -> DebagrConfig
  {
    try lock.withLock {
      var current = try loadUnlocked()
      try transform(&current)
      current.preferences.clamp()
      let data = try encoder.encode(current)
      try FileSecurity.writeSecureFile(data, to: fileURL)
      return current
    }
  }

  public func verifyPermissions() -> Bool {
    lock.withLock {
      FileSecurity.verifyRestrictivePermissions(fileURL.deletingLastPathComponent())
        && FileSecurity.verifyRestrictivePermissions(fileURL)
    }
  }

  private func loadUnlocked() throws -> DebagrConfig {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return DebagrConfig()
    }
    let data = try Data(contentsOf: fileURL)
    var config = try decoder.decode(DebagrConfig.self, from: data)
    config.preferences.clamp()
    return config
  }
}

public final class FileReceiptStore: ReceiptStoring, @unchecked Sendable {
  public let fileURL: URL
  private let maxEntries: Int
  private let lock = NSLock()
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(directoryURL: URL = FileSecurity.dataDirectoryURL(), maxEntries: Int = 50) {
    self.fileURL = directoryURL.appendingPathComponent("receipts.json", isDirectory: false)
    self.maxEntries = max(1, maxEntries)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    self.encoder = enc

    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    self.decoder = dec
  }

  public func listRecent(limit: Int = 20) throws -> [DeploymentReceipt] {
    try lock.withLock {
      let all = try loadUnlocked()
      return Array(all.prefix(max(0, limit)))
    }
  }

  public func append(_ receipt: DeploymentReceipt) throws {
    try lock.withLock {
      var all = try loadUnlocked()
      all.insert(receipt, at: 0)
      if all.count > maxEntries {
        all = Array(all.prefix(maxEntries))
      }
      let data = try encoder.encode(all)
      try FileSecurity.writeSecureFile(data, to: fileURL)
    }
  }

  public func verifyPermissions() -> Bool {
    lock.withLock {
      FileSecurity.verifyRestrictivePermissions(fileURL.deletingLastPathComponent())
        && FileSecurity.verifyRestrictivePermissions(fileURL)
    }
  }

  private func loadUnlocked() throws -> [DeploymentReceipt] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return []
    }
    let data = try Data(contentsOf: fileURL)
    return try decoder.decode([DeploymentReceipt].self, from: data)
  }
}

public final class FileBridgeStateStore: BridgeStateStoring, @unchecked Sendable {
  public let fileURL: URL
  private let lock = NSLock()
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(directoryURL: URL = FileSecurity.dataDirectoryURL()) {
    self.fileURL = directoryURL.appendingPathComponent("bridge-state.json", isDirectory: false)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    self.encoder = enc

    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    self.decoder = dec
  }

  public func load() throws -> BridgeStateSnapshot? {
    try lock.withLock {
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return nil
      }
      let data = try Data(contentsOf: fileURL)
      return try decoder.decode(BridgeStateSnapshot.self, from: data)
    }
  }

  public func save(_ snapshot: BridgeStateSnapshot) throws {
    try lock.withLock {
      let data = try encoder.encode(snapshot)
      try FileSecurity.writeSecureFile(data, to: fileURL)
    }
  }

  public func verifyPermissions() -> Bool {
    lock.withLock {
      FileSecurity.verifyRestrictivePermissions(fileURL.deletingLastPathComponent())
        && FileSecurity.verifyRestrictivePermissions(fileURL)
    }
  }
}
