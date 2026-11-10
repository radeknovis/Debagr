import CryptoKit
import Network
import XCTest

@testable import Debagr

final class RoleSyncTests: XCTestCase {
  private var folder: URL!
  private var suites: [String] = []

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "RoleSyncTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    try? FileManager.default.removeItem(at: folder)
  }

  private func defaults() -> UserDefaults {
    let name = "RoleSyncTests-\(UUID().uuidString)"
    suites.append(name)
    return UserDefaults(suiteName: name)!
  }

  func testSignaturesPinIdentityAndRejectReplaysOrTampering() throws {
    let a = try RoleSyncIdentity(keyURL: folder.appendingPathComponent("a"))
    let b = try RoleSyncIdentity(keyURL: folder.appendingPathComponent("b"))
    XCTAssertEqual(
      try RoleSyncIdentity(keyURL: folder.appendingPathComponent("a")).publicKey, a.publicKey)
    let nonce = UUID().uuidString
    let payload = RoleSyncPayload(
      requestID: UUID().uuidString, nonce: nonce,
      sender: RoleSyncNode(id: "A", name: "Air"), targetID: "B", assignment: nil, error: nil)
    let message = try SignedRoleMessage(payload: payload, identity: a)
    XCTAssertEqual(
      try message.verified(expectedKey: a.publicKey, targetID: "B", nonce: nonce).sender.id, "A")
    XCTAssertThrowsError(
      try message.verified(expectedKey: b.publicKey, targetID: "B", nonce: nonce))
    XCTAssertThrowsError(
      try message.verified(expectedKey: a.publicKey, targetID: "B", nonce: UUID().uuidString))
    XCTAssertThrowsError(
      try message.verified(expectedKey: a.publicKey, targetID: "C", nonce: nonce))
    var object =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as! [String: Any]
    object["body"] = Data("tampered".utf8).base64EncodedString()
    let tampered = try JSONDecoder().decode(
      SignedRoleMessage.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertThrowsError(
      try tampered.verified(expectedKey: a.publicKey, targetID: "B", nonce: nonce))
    XCTAssertEqual(message.verificationCode(remoteKey: b.publicKey).count, 8)
  }

  func testConcurrentSwapsConvergeAndOldRepliesCannotUndoNewerRoles() throws {
    let a = RoleSyncNode(id: "A", name: "Air")
    let b = RoleSyncNode(id: "B", name: "Mini")
    let aDefaults = defaults()
    let bDefaults = defaults()
    let aStore = RoleSyncStore(defaults: aDefaults, local: a)
    let bStore = RoleSyncStore(defaults: bDefaults, local: b)
    let keyA = Data(repeating: 1, count: 32)
    let keyB = Data(repeating: 2, count: 32)
    let aProposal = try aStore.proposal(role: .builder, peer: b)
    let bProposal = try bStore.proposal(role: .builder, peer: a)
    try aStore.apply(bProposal, remote: b, publicKey: keyB)
    try bStore.apply(aProposal, remote: a, publicKey: keyA)
    try aStore.apply(aProposal, remote: b, publicKey: keyB)
    try bStore.apply(bProposal, remote: a, publicKey: keyA)
    XCTAssertEqual(aStore.current, bStore.current)
    XCTAssertEqual(try MachineRoleStore(defaults: aDefaults).load()?.role, .client)
    XCTAssertEqual(try MachineRoleStore(defaults: bDefaults).load()?.role, .builder)
    XCTAssertThrowsError(try aStore.checkPeer("B", publicKey: keyA))
    aStore.clear()
    XCTAssertNil(aStore.trustedKey(for: "B"))
    XCTAssertNil(try MachineRoleStore(defaults: aDefaults).load())
  }

  func testReplacingTheSelectedPeerRequiresAnExplicitOutboundChoice() throws {
    let local = RoleSyncNode(id: "A", name: "Mini")
    let first = RoleSyncNode(id: "B", name: "Air")
    let next = RoleSyncNode(id: "C", name: "Other Mac")
    let store = RoleSyncStore(defaults: defaults(), local: local)
    let firstKey = Data(repeating: 1, count: 32)
    let nextKey = Data(repeating: 2, count: 32)
    try store.apply(store.proposal(role: .builder, peer: first), remote: first, publicKey: firstKey)
    let proposal = try store.proposal(role: .client, peer: next)
    XCTAssertThrowsError(try store.apply(proposal, remote: next, publicKey: nextKey))
    XCTAssertEqual(store.current?.client.id, first.id)
    try store.apply(proposal, remote: next, publicKey: nextKey, replacingPeer: true)
    XCTAssertEqual(store.current?.builder.id, next.id)
    XCTAssertNil(store.trustedKey(for: first.id))
    XCTAssertEqual(store.trustedKey(for: next.id), nextKey)
    XCTAssertThrowsError(try store.checkPeer(next.id, publicKey: firstKey, replacingPeer: true))
  }

  func testVerifiedMeshPairsWithoutACodeButStillPinsAndRejectsChangedKeys() throws {
    let aDefaults = defaults()
    let bDefaults = defaults()
    let a = try RoleSyncService(
      local: RoleSyncNode(id: "A", name: "Mini"),
      defaults: aDefaults, keyURL: folder.appendingPathComponent("mesh-a"))
    let b = try RoleSyncService(
      local: RoleSyncNode(id: "B", name: "Air"),
      defaults: bDefaults, keyURL: folder.appendingPathComponent("mesh-b"))
    defer {
      a.stop()
      b.stop()
    }
    a.trustMeshConnection = { _ in true }
    b.trustMeshConnection = { _ in true }
    a.canChangeRoles = { true }
    b.canChangeRoles = { true }
    b.approvePair = { _, _, _, completion in
      XCTFail("Verified personal mesh must not ask for a pairing code")
      completion(false)
    }
    let ready = expectation(description: "mesh receiver ready")
    let port = LockedValue<NWEndpoint.Port?>(nil)
    b.start(port: .any) {
      port.set($0)
      ready.fulfill()
    }
    wait(for: [ready], timeout: 5)
    var peer = DebagrPeer(protocolVersion: 1, nodeID: "B", name: "Air", roles: ["app"])
    peer.roleSyncPublicKey = b.identity.publicKey.base64EncodedString()
    let paired = expectation(description: "mesh pair")
    let progress = LockedValue("")
    a.assign(
      role: .builder, peer: peer,
      endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(port.get())),
      progress: { progress.set($0) },
      completion: { result in
        if case .failure(let error) = result { XCTFail(error.localizedDescription) }
        paired.fulfill()
      })
    wait(for: [paired], timeout: 5)
    XCTAssertFalse(progress.get().contains("code:"))
    XCTAssertEqual(try MachineRoleStore(defaults: aDefaults).load()?.role, .builder)
    XCTAssertEqual(try MachineRoleStore(defaults: bDefaults).load()?.role, .client)
    peer.roleSyncPublicKey = Data(repeating: 9, count: 32).base64EncodedString()
    let rejected = expectation(description: "mesh does not bypass pinned key")
    a.assign(
      role: .client, peer: peer,
      endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(port.get())),
      progress: { _ in },
      completion: { result in
        if case .success = result { XCTFail("A changed pinned key must be rejected") }
        rejected.fulfill()
      })
    wait(for: [rejected], timeout: 5)
    XCTAssertEqual(try MachineRoleStore(defaults: aDefaults).load()?.role, .builder)
  }

  func testTwoLiveServicesPairOnceAndSwapFromEitherSide() throws {
    let aDefaults = defaults()
    let bDefaults = defaults()
    let a = try RoleSyncService(
      local: RoleSyncNode(id: "A", name: "Air"), defaults: aDefaults,
      keyURL: folder.appendingPathComponent("a"))
    let b = try RoleSyncService(
      local: RoleSyncNode(id: "B", name: "Mini"), defaults: bDefaults,
      keyURL: folder.appendingPathComponent("b"))
    defer {
      a.stop()
      b.stop()
    }
    let approvals = LockedValue(0)
    let receivedCode = LockedValue("")
    let sentCode = LockedValue("")
    a.canChangeRoles = { true }
    b.canChangeRoles = { true }
    a.approvePair = { _, _, _, complete in
      XCTFail("The already paired Mac should not prompt again")
      complete(false)
    }
    b.approvePair = { _, code, role, complete in
      approvals.withValue { $0 += 1 }
      receivedCode.set(code)
      XCTAssertEqual(role, .client)
      complete(true)
    }
    let readyA = expectation(description: "A ready")
    let readyB = expectation(description: "B ready")
    let portA = LockedValue<NWEndpoint.Port?>(nil)
    let portB = LockedValue<NWEndpoint.Port?>(nil)
    a.start(port: .any) {
      portA.set($0)
      readyA.fulfill()
    }
    b.start(port: .any) {
      portB.set($0)
      readyB.fulfill()
    }
    wait(for: [readyA, readyB], timeout: 5)
    var peerA = DebagrPeer(protocolVersion: 1, nodeID: "A", name: "Air", roles: ["app"])
    var peerB = DebagrPeer(protocolVersion: 1, nodeID: "B", name: "Mini", roles: ["app"])
    peerA.roleSyncPublicKey = a.identity.publicKey.base64EncodedString()
    peerB.roleSyncPublicKey = b.identity.publicKey.base64EncodedString()
    let unpairedCheck = expectation(description: "unpaired start preflight rejected")
    a.verify(peer: peerB, endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(portB.get())))
    { result in
      if case .success = result { XCTFail("Start must require a previously trusted pair") }
      unpairedCheck.fulfill()
    }
    wait(for: [unpairedCheck], timeout: 5)
    XCTAssertEqual(approvals.get(), 0)
    let first = expectation(description: "first pair")
    a.assign(
      role: .builder, peer: peerB,
      endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(portB.get())),
      progress: { sentCode.set($0) },
      completion: { result in
        if case .failure(let error) = result { XCTFail(error.localizedDescription) }
        first.fulfill()
      })
    wait(for: [first], timeout: 5)
    XCTAssertTrue(sentCode.get().contains(receivedCode.get()))
    XCTAssertEqual(approvals.get(), 1)
    XCTAssertEqual(try MachineRoleStore(defaults: aDefaults).load()?.role, .builder)
    XCTAssertEqual(try MachineRoleStore(defaults: bDefaults).load()?.role, .client)
    let swapped = expectation(description: "swapped from B")
    b.assign(
      role: .builder, peer: peerA,
      endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(portA.get())),
      progress: { _ in },
      completion: { result in
        if case .failure(let error) = result { XCTFail(error.localizedDescription) }
        swapped.fulfill()
      })
    wait(for: [swapped], timeout: 5)
    XCTAssertEqual(approvals.get(), 1)
    XCTAssertEqual(try MachineRoleStore(defaults: aDefaults).load()?.role, .client)
    XCTAssertEqual(try MachineRoleStore(defaults: bDefaults).load()?.role, .builder)
    a.canChangeRoles = { false }
    let busy = expectation(description: "busy role change rejected")
    b.assign(
      role: .client, peer: peerA,
      endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(portA.get())),
      progress: { _ in },
      completion: { result in
        if case .success = result {
          XCTFail("Role changes must stop while USB transport is active")
        }
        busy.fulfill()
      })
    wait(for: [busy], timeout: 5)
    XCTAssertEqual(try MachineRoleStore(defaults: bDefaults).load()?.role, .builder)
    let beforeA = aDefaults.data(forKey: "role-sync-assignment")
    let beforeB = bDefaults.data(forKey: "role-sync-assignment")
    let verified = expectation(description: "read-only verification works during USB activity")
    b.verify(peer: peerA, endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(portA.get())))
    { result in
      if case .failure(let error) = result { XCTFail(error.localizedDescription) }
      verified.fulfill()
    }
    wait(for: [verified], timeout: 5)
    XCTAssertEqual(aDefaults.data(forKey: "role-sync-assignment"), beforeA)
    XCTAssertEqual(bDefaults.data(forKey: "role-sync-assignment"), beforeB)
    var impostor = peerA
    impostor.roleSyncPublicKey = b.identity.publicKey.base64EncodedString()
    let rejected = expectation(description: "discovery cannot replace the pinned key")
    b.verify(
      peer: impostor, endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(portA.get()))
    ) { result in
      if case .success = result {
        XCTFail("A spoofed discovery identity must not pass Start preflight")
      }
      rejected.fulfill()
    }
    wait(for: [rejected], timeout: 5)
    XCTAssertEqual(approvals.get(), 1)
  }

  func testDeclinedPairingDoesNotSaveEitherRole() throws {
    let aDefaults = defaults()
    let bDefaults = defaults()
    let a = try RoleSyncService(
      local: RoleSyncNode(id: "A", name: "Air"), defaults: aDefaults,
      keyURL: folder.appendingPathComponent("a"))
    let b = try RoleSyncService(
      local: RoleSyncNode(id: "B", name: "Mini"), defaults: bDefaults,
      keyURL: folder.appendingPathComponent("b"))
    defer {
      a.stop()
      b.stop()
    }
    b.canChangeRoles = { true }
    b.approvePair = { _, _, _, complete in complete(false) }
    let ready = expectation(description: "ready")
    let port = LockedValue<NWEndpoint.Port?>(nil)
    b.start(port: .any) {
      port.set($0)
      ready.fulfill()
    }
    wait(for: [ready], timeout: 5)
    var peer = DebagrPeer(protocolVersion: 1, nodeID: "B", name: "Mini", roles: ["app"])
    peer.roleSyncPublicKey = b.identity.publicKey.base64EncodedString()
    let declined = expectation(description: "declined")
    a.assign(
      role: .builder, peer: peer,
      endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(port.get())),
      progress: { _ in },
      completion: { result in
        if case .success = result { XCTFail("Declined pairing must not succeed") }
        declined.fulfill()
      })
    wait(for: [declined], timeout: 5)
    XCTAssertNil(try MachineRoleStore(defaults: aDefaults).load())
    XCTAssertNil(try MachineRoleStore(defaults: bDefaults).load())
  }
}
