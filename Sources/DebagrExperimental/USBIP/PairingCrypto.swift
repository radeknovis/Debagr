import CryptoKit
import DebagrCore
import Foundation

public enum USBIPRole: String, Codable, Sendable, CaseIterable {
  case builder
  case client

  public var counterpart: USBIPRole {
    self == .builder ? .client : .builder
  }
}

public struct PairingHandshakeHello: Codable, Sendable, Equatable {
  public let sessionID: String
  public let role: USBIPRole
  public let publicKeyBase64: String

  public init(sessionID: String, role: USBIPRole, publicKeyBase64: String) {
    self.sessionID = sessionID
    self.role = role
    self.publicKeyBase64 = publicKeyBase64
  }
}

public struct PairingAuthProof: Codable, Sendable, Equatable {
  public let sessionID: String
  public let role: USBIPRole
  public let macBase64: String

  public init(sessionID: String, role: USBIPRole, macBase64: String) {
    self.sessionID = sessionID
    self.role = role
    self.macBase64 = macBase64
  }
}

public struct SealedControlEnvelope: Codable, Sendable, Equatable {
  public let sequence: UInt64
  public let combinedBoxBase64: String

  public init(sequence: UInt64, combinedBoxBase64: String) {
    self.sequence = sequence
    self.combinedBoxBase64 = combinedBoxBase64
  }
}

public struct PairingCryptoSession: Sendable {
  public let sessionID: String
  public let role: USBIPRole
  public let sasCode: String
  private let privateKey: Curve25519.KeyAgreement.PrivateKey

  public init(
    sessionID: String = UUID().uuidString.lowercased(),
    role: USBIPRole,
    sasCode: String = PairingCryptoSession.generateSixDigitSAS()
  ) {
    self.sessionID = sessionID
    self.role = role
    self.sasCode = sasCode
    self.privateKey = Curve25519.KeyAgreement.PrivateKey()
  }

  public var localHello: PairingHandshakeHello {
    PairingHandshakeHello(
      sessionID: sessionID,
      role: role,
      publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
    )
  }

  public func establishChannel(with peerHello: PairingHandshakeHello) throws
    -> AuthenticatedPairingChannel
  {
    guard peerHello.sessionID == sessionID else {
      throw DebagrError(
        code: .pairingAuthFailed,
        category: "usbip_auth",
        message: "Peer session ID mismatch."
      )
    }
    guard peerHello.role == role.counterpart else {
      throw DebagrError(
        code: .pairingAuthFailed,
        category: "usbip_auth",
        message:
          "Role mismatch: expected '\(role.counterpart.rawValue)' but peer advertised '\(peerHello.role.rawValue)'."
      )
    }
    guard let peerKeyData = Data(base64Encoded: peerHello.publicKeyBase64),
      let peerPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerKeyData)
    else {
      throw DebagrError(
        code: .pairingAuthFailed,
        category: "usbip_auth",
        message: "Malformed Curve25519 peer public key."
      )
    }

    let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
    let builderPub =
      role == .builder ? privateKey.publicKey.rawRepresentation : peerPublicKey.rawRepresentation
    let clientPub =
      role == .client ? privateKey.publicKey.rawRepresentation : peerPublicKey.rawRepresentation

    let salt = Data("debagr-usbip-v1:\(sessionID):\(sasCode)".utf8)
    let transcript = builderPub + clientPub

    let authKey = sharedSecret.hkdfDerivedSymmetricKey(
      using: SHA256.self,
      salt: salt,
      sharedInfo: Data("auth".utf8) + transcript,
      outputByteCount: 32
    )
    let builderToClientKey = sharedSecret.hkdfDerivedSymmetricKey(
      using: SHA256.self,
      salt: salt,
      sharedInfo: Data("b2c".utf8) + transcript,
      outputByteCount: 32
    )
    let clientToBuilderKey = sharedSecret.hkdfDerivedSymmetricKey(
      using: SHA256.self,
      salt: salt,
      sharedInfo: Data("c2b".utf8) + transcript,
      outputByteCount: 32
    )

    return AuthenticatedPairingChannel(
      sessionID: sessionID,
      localRole: role,
      authKey: authKey,
      sendKey: role == .builder ? builderToClientKey : clientToBuilderKey,
      receiveKey: role == .builder ? clientToBuilderKey : builderToClientKey,
      builderPublicKey: builderPub,
      clientPublicKey: clientPub
    )
  }

  public static func generateSixDigitSAS() -> String {
    var randomValue: UInt32 = 0
    _ = withUnsafeMutableBytes(of: &randomValue) { ptr in
      SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, ptr.baseAddress!)
    }
    return String(format: "%06d", Int(randomValue % 1_000_000))
  }
}

public final class AuthenticatedPairingChannel: @unchecked Sendable {
  public let sessionID: String
  public let localRole: USBIPRole

  private let authKey: SymmetricKey
  private let sendKey: SymmetricKey
  private let receiveKey: SymmetricKey
  private let builderPublicKey: Data
  private let clientPublicKey: Data

  private let lock = NSLock()
  private var outgoingSeq: UInt64 = 0
  private var expectedIncomingSeq: UInt64 = 0
  private var peerVerified = false

  init(
    sessionID: String,
    localRole: USBIPRole,
    authKey: SymmetricKey,
    sendKey: SymmetricKey,
    receiveKey: SymmetricKey,
    builderPublicKey: Data,
    clientPublicKey: Data
  ) {
    self.sessionID = sessionID
    self.localRole = localRole
    self.authKey = authKey
    self.sendKey = sendKey
    self.receiveKey = receiveKey
    self.builderPublicKey = builderPublicKey
    self.clientPublicKey = clientPublicKey
  }

  public func makeLocalProof() -> PairingAuthProof {
    let payload = proofMaterial(for: localRole)
    let code = HMAC<SHA256>.authenticationCode(for: payload, using: authKey)
    return PairingAuthProof(
      sessionID: sessionID,
      role: localRole,
      macBase64: Data(code).base64EncodedString()
    )
  }

  public func verifyPeerProof(_ proof: PairingAuthProof) throws {
    guard proof.sessionID == sessionID, proof.role == localRole.counterpart else {
      throw DebagrError(
        code: .pairingAuthFailed,
        category: "usbip_auth",
        message: "Peer authentication proof session or role mismatch."
      )
    }
    guard let macData = Data(base64Encoded: proof.macBase64) else {
      throw DebagrError(
        code: .pairingAuthFailed,
        category: "usbip_auth",
        message: "Malformed peer authentication MAC."
      )
    }

    let expectedPayload = proofMaterial(for: localRole.counterpart)
    guard
      HMAC<SHA256>.isValidAuthenticationCode(
        macData, authenticating: expectedPayload, using: authKey)
    else {
      throw DebagrError(
        code: .pairingAuthFailed,
        category: "usbip_auth",
        message: "6-digit pairing verification code or transcript proof failed."
      )
    }

    lock.withLock { peerVerified = true }
  }

  public func sealControlMessage(_ plaintext: Data) throws -> SealedControlEnvelope {
    try lock.withLock {
      guard peerVerified else {
        throw DebagrError(
          code: .pairingAuthFailed,
          category: "usbip_auth",
          message: "Cannot encrypt control message before peer authentication completes."
        )
      }
      let seq = outgoingSeq
      outgoingSeq += 1
      let nonce = try makeNonce(sequence: seq)
      let aad = Data("debagr-ctrl:\(sessionID):\(seq)".utf8)
      let sealed = try ChaChaPoly.seal(plaintext, using: sendKey, nonce: nonce, authenticating: aad)
      return SealedControlEnvelope(
        sequence: seq,
        combinedBoxBase64: sealed.combined.base64EncodedString()
      )
    }
  }

  public func openControlMessage(_ envelope: SealedControlEnvelope) throws -> Data {
    try lock.withLock {
      guard peerVerified else {
        throw DebagrError(
          code: .pairingAuthFailed,
          category: "usbip_auth",
          message: "Cannot decrypt control message before peer authentication completes."
        )
      }
      guard envelope.sequence == expectedIncomingSeq else {
        throw DebagrError(
          code: .pairingAuthFailed,
          category: "usbip_auth",
          message:
            "Control message sequence out of order or replayed (expected \(expectedIncomingSeq), got \(envelope.sequence))."
        )
      }
      guard let combined = Data(base64Encoded: envelope.combinedBoxBase64) else {
        throw DebagrError(
          code: .pairingAuthFailed,
          category: "usbip_auth",
          message: "Malformed encrypted control envelope."
        )
      }
      let box = try ChaChaPoly.SealedBox(combined: combined)
      let aad = Data("debagr-ctrl:\(sessionID):\(envelope.sequence)".utf8)
      let plaintext = try ChaChaPoly.open(box, using: receiveKey, authenticating: aad)
      expectedIncomingSeq += 1
      return plaintext
    }
  }

  private func proofMaterial(for role: USBIPRole) -> Data {
    var data = Data("proof:\(role.rawValue):\(sessionID):".utf8)
    data.append(builderPublicKey)
    data.append(clientPublicKey)
    return data
  }

  private func makeNonce(sequence: UInt64) throws -> ChaChaPoly.Nonce {
    var bytes = [UInt8](repeating: 0, count: 12)
    var be = sequence.bigEndian
    withUnsafeBytes(of: &be) { raw in
      for (idx, b) in raw.enumerated() {
        bytes[4 + idx] = b
      }
    }
    return try ChaChaPoly.Nonce(data: bytes)
  }
}
