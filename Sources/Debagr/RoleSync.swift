import CryptoKit
import Darwin
import Foundation

struct RoleSyncNode: Codable, Equatable {
  let id: String
  let name: String
}

struct SyncedMachineRoles: Codable, Equatable {
  let revision: Int64
  let authorID: String
  let builder: RoleSyncNode
  let client: RoleSyncNode

  func validate(localID: String, remoteID: String) throws {
    guard revision > 0, revision < Int64.max,
      Set([builder.id, client.id]) == Set([localID, remoteID]),
      builder.id != client.id, [builder.id, client.id].contains(authorID)
    else {
      throw USBIPError.invalid("Invalid paired role assignment.")
    }
    try MachineRoleSelection(role: .builder, peerID: client.id, peerName: client.name).validate(
      localNodeID: builder.id)
    try MachineRoleSelection(role: .client, peerID: builder.id, peerName: builder.name).validate(
      localNodeID: client.id)
  }

  func selection(for nodeID: String) throws -> MachineRoleSelection {
    if nodeID == builder.id {
      return MachineRoleSelection(role: .builder, peerID: client.id, peerName: client.name)
    }
    if nodeID == client.id {
      return MachineRoleSelection(role: .client, peerID: builder.id, peerName: builder.name)
    }
    throw USBIPError.invalid("This Mac is not a member of the selected pair.")
  }

  func isNewer(than other: SyncedMachineRoles) -> Bool {
    revision > other.revision || (revision == other.revision && authorID > other.authorID)
  }
}

struct RoleSyncIdentity {
  let key: Curve25519.Signing.PrivateKey
  var publicKey: Data { key.publicKey.rawRepresentation }

  init(keyURL: URL) throws {
    try FileManager.default.createDirectory(
      at: keyURL.deletingLastPathComponent(),
      withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let lockFD = open(
      keyURL.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard lockFD >= 0 else { throw USBIPError.invalid("Cannot lock the role pairing identity.") }
    defer { close(lockFD) }
    guard flock(lockFD, LOCK_EX) == 0 else {
      throw USBIPError.invalid("Cannot lock the role pairing identity.")
    }
    if FileManager.default.fileExists(atPath: keyURL.path) {
      let attributes = try FileManager.default.attributesOfItem(atPath: keyURL.path)
      guard (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
        (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
      else {
        throw USBIPError.invalid("The role pairing key must be owned by this user with mode 0600.")
      }
      key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
    } else {
      key = Curve25519.Signing.PrivateKey()
      try ManagedDeviceStore.writePrivate(key.rawRepresentation, to: keyURL)
    }
  }
}

struct RoleSyncHello: Codable {
  let version: Int
  let nodeID: String
  let publicKey: Data
  let nonce: String
}

struct RoleSyncPayload: Codable {
  let requestID: String
  let nonce: String
  let sender: RoleSyncNode
  let targetID: String
  let assignment: SyncedMachineRoles?
  let error: String?
}

struct SignedRoleMessage: Codable {
  let body: Data
  let publicKey: Data
  let signature: Data

  init(payload: RoleSyncPayload, identity: RoleSyncIdentity) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    body = try encoder.encode(payload)
    publicKey = identity.publicKey
    signature = try identity.key.signature(for: body)
  }

  func verified(expectedKey: Data, targetID: String, nonce: String) throws -> RoleSyncPayload {
    guard body.count <= 8192, publicKey == expectedKey,
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: expectedKey),
      key.isValidSignature(signature, for: body)
    else {
      throw USBIPError.invalid("The role update's signature could not be verified.")
    }
    let payload = try JSONDecoder().decode(RoleSyncPayload.self, from: body)
    guard payload.targetID == targetID, payload.nonce == nonce,
      UUID(uuidString: payload.requestID) != nil, !payload.sender.id.isEmpty,
      payload.sender.id.count <= 128, !payload.sender.name.isEmpty, payload.sender.name.count <= 128
    else {
      throw USBIPError.invalid("The role update was addressed to another Mac or connection.")
    }
    return payload
  }

  func verificationCode(remoteKey: Data) -> String {
    let digest = SHA256.hash(data: body + publicKey + remoteKey)
    return digest.prefix(4).map { String(format: "%02X", $0) }.joined()
  }
}

final class RoleSyncStore {
  private let defaults: UserDefaults
  private let local: RoleSyncNode
  private let roles: MachineRoleStore

  init(defaults: UserDefaults, local: RoleSyncNode) {
    self.defaults = defaults
    self.local = local
    roles = MachineRoleStore(defaults: defaults)
  }

  var current: SyncedMachineRoles? {
    defaults.data(forKey: "role-sync-assignment").flatMap {
      try? JSONDecoder().decode(SyncedMachineRoles.self, from: $0)
    }
  }

  func trustedKey(for nodeID: String) -> Data? {
    (defaults.dictionary(forKey: "role-sync-trusted-keys")?[nodeID] as? String).flatMap {
      Data(base64Encoded: $0)
    }
  }

  func checkPeer(_ peerID: String, publicKey: Data, replacingPeer: Bool = false) throws {
    if let pinned = trustedKey(for: peerID), pinned != publicKey {
      throw USBIPError.invalid(
        "The other Mac's pairing key has changed. Clear the pairing and verify it again.")
    }
    if !replacingPeer, let selected = try roles.load(), selected.peerID != peerID {
      throw USBIPError.invalid(
        "This Mac is already paired with another machine. Clear that selection before pairing again."
      )
    }
  }

  func proposal(role: DebagrMachineRole, peer: RoleSyncNode) throws -> SyncedMachineRoles {
    let previous = max(
      (defaults.object(forKey: "role-sync-counter") as? NSNumber)?.int64Value ?? 0,
      current?.revision ?? 0)
    guard previous < Int64.max - 1 else {
      throw USBIPError.invalid("Role revision limit reached. Clear the pairing and retry.")
    }
    let assignment = SyncedMachineRoles(
      revision: previous + 1, authorID: local.id,
      builder: role == .builder ? local : peer, client: role == .client ? local : peer)
    try assignment.validate(localID: local.id, remoteID: peer.id)
    defaults.set(NSNumber(value: assignment.revision), forKey: "role-sync-counter")
    return assignment
  }

  func confirms(_ assignment: SyncedMachineRoles, remoteID: String) throws -> Bool {
    try assignment.validate(localID: local.id, remoteID: remoteID)
    return try roles.load() == assignment.selection(for: local.id)
  }

  @discardableResult
  func apply(
    _ candidate: SyncedMachineRoles, remote: RoleSyncNode, publicKey: Data,
    replacingPeer: Bool = false
  ) throws
    -> SyncedMachineRoles
  {
    try checkPeer(remote.id, publicKey: publicKey, replacingPeer: replacingPeer)
    try candidate.validate(localID: local.id, remoteID: remote.id)
    let winner: SyncedMachineRoles
    if let current, [current.builder.id, current.client.id].contains(remote.id) {
      try current.validate(localID: local.id, remoteID: remote.id)
      if candidate.revision == current.revision, candidate.authorID == current.authorID,
        candidate != current
      {
        throw USBIPError.invalid("Conflicting role updates reused the same revision.")
      }
      winner = candidate.isNewer(than: current) ? candidate : current
    } else {
      winner = candidate
    }
    let previousPeerID = try roles.load()?.peerID
    try roles.save(winner.selection(for: local.id), localNodeID: local.id)
    defaults.set(try JSONEncoder().encode(winner), forKey: "role-sync-assignment")
    let counter = max(
      (defaults.object(forKey: "role-sync-counter") as? NSNumber)?.int64Value ?? 0, winner.revision)
    defaults.set(NSNumber(value: counter), forKey: "role-sync-counter")
    var keys = defaults.dictionary(forKey: "role-sync-trusted-keys") as? [String: String] ?? [:]
    if let previousPeerID, previousPeerID != remote.id { keys.removeValue(forKey: previousPeerID) }
    keys[remote.id] = publicKey.base64EncodedString()
    defaults.set(keys, forKey: "role-sync-trusted-keys")
    return winner
  }

  func clear() {
    if let selected = try? roles.load() {
      var keys = defaults.dictionary(forKey: "role-sync-trusted-keys") as? [String: String] ?? [:]
      keys.removeValue(forKey: selected.peerID)
      defaults.set(keys, forKey: "role-sync-trusted-keys")
    }
    defaults.removeObject(forKey: "role-sync-assignment")
    roles.clear()
  }
}
