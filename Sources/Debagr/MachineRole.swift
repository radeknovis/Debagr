import Foundation

enum DebagrMachineRole: String, Codable, CaseIterable {
  case builder, client

  var title: String {
    self == .builder ? "Builder — compiles apps" : "Client — device connected"
  }

  var opposite: DebagrMachineRole { self == .builder ? .client : .builder }

  // The Builder imports USB; the Client exports its physically connected device.
  var backend: String { self == .builder ? "usbip-macos" : "longcable-server" }
}

struct MachineRoleSelection: Codable, Equatable {
  let role: DebagrMachineRole
  let peerID: String
  let peerName: String

  func isConfirmed(with peer: DebagrPeer?, localNodeID: String) -> Bool {
    peer?.nodeID == peerID && peer?.machineRole == role.opposite
      && peer?.pairedNodeID == localNodeID
  }

  func validate(localNodeID: String) throws {
    guard !peerID.isEmpty, peerID != localNodeID, peerID.count <= 128,
      !peerID.hasPrefix("usbip:"), !peerName.isEmpty, peerName.count <= 128
    else {
      throw USBIPError.invalid("Choose another discovered Debagr Mac as the other machine.")
    }
  }

  func status(with peer: DebagrPeer?, localNodeID: String) -> String {
    guard let peer else { return "Saved. \(peerName) is not currently discovered." }
    guard let remoteRole = peer.machineRole else {
      return "Saved. On \(peerName), select \(role.opposite.title) and choose this Mac."
    }
    guard remoteRole == role.opposite else {
      return
        "Role conflict: both Macs are \(role.rawValue)s. Select \(role.opposite.title) on \(peerName)."
    }
    guard peer.pairedNodeID == localNodeID else {
      return "On \(peerName), choose this Mac as its other machine."
    }
    return
      "Roles configured: \(role == .builder ? "this Mac builds; \(peerName) provides the device" : "\(peerName) builds; this Mac provides the device")."
  }
}

struct MachineRoleStore {
  var defaults: UserDefaults = .standard
  private let key = "usbip-machine-role-selection"

  func load() throws -> MachineRoleSelection? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try JSONDecoder().decode(MachineRoleSelection.self, from: data)
  }

  func save(_ selection: MachineRoleSelection, localNodeID: String) throws {
    try selection.validate(localNodeID: localNodeID)
    defaults.set(try JSONEncoder().encode(selection), forKey: key)
  }

  func clear() { defaults.removeObject(forKey: key) }
}
