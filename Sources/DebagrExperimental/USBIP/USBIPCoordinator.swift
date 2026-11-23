import DebagrCore
import Foundation

public struct USBIPToolPrerequisites: Codable, Sendable, Equatable {
  public let experimental: Bool
  public let usbipBinaryPath: String?
  public let usbipAvailable: Bool
  public let summary: String
  public let installNotice: String
  public let securityNotice: String

  public init(
    usbipBinaryPath: String?,
    usbipAvailable: Bool,
    summary: String
  ) {
    self.experimental = true
    self.usbipBinaryPath = usbipBinaryPath
    self.usbipAvailable = usbipAvailable
    self.summary = summary
    self.installNotice =
      "Debagr never bundles third-party USB/IP drivers or kernel/system extensions. Install your chosen macOS USB/IP tool separately if needed."
    self.securityNotice =
      "Privileged USB/IP bind/attach commands require explicit user confirmation and run only during initial Apple pairing before immediate teardown."
  }
}

public struct PrivilegedApprovalReceipt: Codable, Sendable, Equatable {
  public let sessionID: String
  public let role: USBIPRole
  public let commandDescription: String
  public let approvedAt: Date
  public let userConfirmedSecurityNotice: Bool

  public init(
    sessionID: String,
    role: USBIPRole,
    commandDescription: String,
    approvedAt: Date = Date(),
    userConfirmedSecurityNotice: Bool
  ) {
    self.sessionID = sessionID
    self.role = role
    self.commandDescription = commandDescription
    self.approvedAt = approvedAt
    self.userConfirmedSecurityNotice = userConfirmedSecurityNotice
  }
}

public enum USBIPSessionPhase: String, Codable, Sendable {
  case idle
  case prerequisitesChecked
  case roleSelected
  case peerAuthenticated
  case approvalGranted
  case usbipActive
  case applePairingVerified
  case tornDownReadyForWirelessHandoff
}

public struct WirelessHandoffPayload: Codable, Sendable, Equatable {
  public let pairedDevice: PhysicalDevice
  public let nextStep: String

  public init(pairedDevice: PhysicalDevice) {
    self.pairedDevice = pairedDevice
    self.nextStep =
      "USB/IP session torn down. Proceed to Debagr Wireless Setup to capture Bonjour identity and save VPN configuration."
  }
}

public struct USBIPGuidePayload: Codable, Sendable, Equatable {
  public let label: String
  public let experimentalNotice: String
  public let steps: [String]
  public let securityGuarantees: [String]

  public init() {
    self.label = "Experimental — Pair via USB/IP (Temporary Raw USB)"
    self.experimentalNotice =
      "EXPERIMENTAL: Guided two-Mac helper for initial Apple USB pairing when an unpaired iPhone/iPad is physically with you away from the Builder Mac."
    self.steps = [
      "1. Check prerequisites (`debagr experimental usbip check`) on both Macs; separately install a macOS USB/IP tool (Debagr does not bundle third-party USB drivers).",
      "2. Choose roles: Builder Mac (owns Xcode/Apple trust) and Client Mac (phone plugged in via USB).",
      "3. Discover peer on demand or enter the private VPN IP, then verify the 6-digit authentication code.",
      "4. Explicitly review and approve the exact USB/IP command to run.",
      "5. Once Apple pairing completes and appears as Paired in CoreDevice, Debagr tears down USB/IP and hands off to normal Wireless Setup.",
    ]
    self.securityGuarantees = [
      "Zero background USB/IP listeners; peer discovery runs strictly on demand.",
      "Ephemeral Curve25519 ECDH + 6-digit SAS mutual role authentication + ChaChaPoly encrypted control channel.",
      "Never weakens SIP or silently runs privileged commands without explicit user confirmation.",
    ]
  }
}

public protocol USBIPSupervising: Sendable {
  func checkPrerequisites(customBinaryPath: String?) -> USBIPToolPrerequisites
  func startSupervisedSession(
    binaryPath: String,
    arguments: [String],
    approval: PrivilegedApprovalReceipt
  ) async throws
  func stopSupervisedSession() async
}

public actor SystemUSBIPToolSupervisor: USBIPSupervising {
  private let standardPaths = [
    "/opt/homebrew/bin/usbip",
    "/usr/local/bin/usbip",
    "/usr/bin/usbip",
  ]
  private var activeProcess: Process?

  public init() {}

  deinit {
    if let proc = activeProcess, proc.isRunning {
      proc.terminate()
    }
  }

  public nonisolated func checkPrerequisites(customBinaryPath: String? = nil)
    -> USBIPToolPrerequisites
  {
    var candidates: [String] = []
    if let customBinaryPath,
      !customBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      candidates.append((customBinaryPath as NSString).expandingTildeInPath)
    }
    candidates.append(contentsOf: standardPaths)

    if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
      return USBIPToolPrerequisites(
        usbipBinaryPath: found,
        usbipAvailable: true,
        summary: "Found user-installed USB/IP binary at \(found)."
      )
    }

    return USBIPToolPrerequisites(
      usbipBinaryPath: nil,
      usbipAvailable: false,
      summary:
        "No user-installed `usbip` binary found in standard paths (/opt/homebrew/bin/usbip, /usr/local/bin/usbip)."
    )
  }

  public func startSupervisedSession(
    binaryPath: String,
    arguments: [String],
    approval: PrivilegedApprovalReceipt
  ) async throws {
    guard approval.userConfirmedSecurityNotice, !approval.sessionID.isEmpty else {
      throw DebagrError(
        code: .experimentalApprovalRequired,
        category: "experimental_usbip",
        message:
          "Explicit user confirmation of the USB/IP security notice is required before starting external USB/IP tools."
      )
    }

    guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
      throw DebagrError(
        code: .experimentalToolMissing,
        category: "experimental_usbip",
        message: "External USB/IP binary not executable at \(binaryPath)."
      )
    }

    await stopSupervisedSession()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    activeProcess = process
  }

  public func stopSupervisedSession() async {
    guard let proc = activeProcess else { return }
    activeProcess = nil
    if proc.isRunning {
      proc.terminate()
    }
  }
}

public actor USBIPSessionCoordinator {
  private let devicectl: any DeviceControlling
  private let toolSupervisor: any USBIPSupervising
  private let peerDiscovery: any OnDemandUSBIPPeerDiscovering

  private(set) public var phase: USBIPSessionPhase = .idle
  private(set) public var sessionID: String?
  private(set) public var role: USBIPRole?
  private(set) public var selectedPeer: DiscoveredUSBIPPeer?
  private(set) public var prerequisites: USBIPToolPrerequisites?

  private var cryptoSession: PairingCryptoSession?
  private var authChannel: AuthenticatedPairingChannel?

  public init(
    devicectl: any DeviceControlling = SystemDeviceCtlClient(),
    toolSupervisor: any USBIPSupervising = SystemUSBIPToolSupervisor(),
    peerDiscovery: any OnDemandUSBIPPeerDiscovering = SystemUSBIPPeerDiscovery()
  ) {
    self.devicectl = devicectl
    self.toolSupervisor = toolSupervisor
    self.peerDiscovery = peerDiscovery
  }

  public func checkPrerequisites(customBinaryPath: String? = nil) -> USBIPToolPrerequisites {
    let checked = toolSupervisor.checkPrerequisites(customBinaryPath: customBinaryPath)
    prerequisites = checked
    phase = .prerequisitesChecked
    return checked
  }

  public func discoverPeersOnDemand() async -> [DiscoveredUSBIPPeer] {
    await peerDiscovery.discoverLocalPeers(timeoutSeconds: 2.5)
  }

  public func beginSession(
    role: USBIPRole, sessionID: String = UUID().uuidString.lowercased(), sasCode: String? = nil
  )
    -> (hello: PairingHandshakeHello, sasCode: String)
  {
    let code = sasCode ?? PairingCryptoSession.generateSixDigitSAS()
    let crypto = PairingCryptoSession(sessionID: sessionID, role: role, sasCode: code)
    self.sessionID = sessionID
    self.role = role
    self.cryptoSession = crypto
    self.phase = .roleSelected
    return (crypto.localHello, code)
  }

  public func completePeerAuthentication(
    peer: DiscoveredUSBIPPeer,
    peerHello: PairingHandshakeHello,
    peerProof: PairingAuthProof
  ) throws -> PairingAuthProof {
    guard let cryptoSession else {
      throw DebagrError(
        code: .pairingAuthFailed,
        category: "experimental_usbip",
        message: "No active USB/IP session; call beginSession first."
      )
    }
    let channel = try cryptoSession.establishChannel(with: peerHello)
    try channel.verifyPeerProof(peerProof)
    self.authChannel = channel
    self.selectedPeer = peer
    self.phase = .peerAuthenticated
    return channel.makeLocalProof()
  }

  public func activateUSBIPAndPair(
    targetDeviceHint: String,
    approval: PrivilegedApprovalReceipt,
    binaryPath: String,
    arguments: [String]
  ) async throws -> WirelessHandoffPayload {
    guard phase == .peerAuthenticated || phase == .approvalGranted else {
      throw DebagrError(
        code: .pairingAuthFailed,
        category: "experimental_usbip",
        message: "Peer authentication must complete before starting USB/IP."
      )
    }
    guard approval.userConfirmedSecurityNotice, approval.sessionID == sessionID else {
      throw DebagrError(
        code: .experimentalApprovalRequired,
        category: "experimental_usbip",
        message:
          "User must explicitly review and approve the USB/IP security notice for this session."
      )
    }

    phase = .approvalGranted
    try await toolSupervisor.startSupervisedSession(
      binaryPath: binaryPath,
      arguments: arguments,
      approval: approval
    )
    phase = .usbipActive

    defer {
      Task { [toolSupervisor] in
        await toolSupervisor.stopSupervisedSession()
      }
    }

    try await devicectl.pairDevice(identifier: targetDeviceHint, timeout: 45)
    let devices = try await devicectl.listDevices(timeout: 20)
    guard
      let paired = devices.first(where: {
        $0.matches(identifier: targetDeviceHint) && $0.isEligibleForDebagr
      })
    else {
      throw DebagrError(
        code: .deviceUnpaired,
        category: "experimental_usbip",
        message:
          "Apple pairing command finished, but CoreDevice still does not list '\(targetDeviceHint)' as paired."
      )
    }

    phase = .applePairingVerified
    await toolSupervisor.stopSupervisedSession()
    phase = .tornDownReadyForWirelessHandoff
    return WirelessHandoffPayload(pairedDevice: paired)
  }

  public func cancel() async {
    await toolSupervisor.stopSupervisedSession()
    cryptoSession = nil
    authChannel = nil
    selectedPeer = nil
    sessionID = nil
    phase = .idle
  }
}
