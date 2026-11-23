import DebagrCore
import Foundation

public struct WirelessSetupVerificationResult: Codable, Sendable, Equatable {
  public let profile: ManagedDeviceProfile
  public let vpnProbeSucceeded: Bool
  public let notes: [String]

  public init(profile: ManagedDeviceProfile, vpnProbeSucceeded: Bool, notes: [String]) {
    self.profile = profile
    self.vpnProbeSucceeded = vpnProbeSucceeded
    self.notes = notes
  }
}

public actor WirelessBridgeSupervisor: BridgeEnsuring {
  private let configStore: any ConfigStoring
  private let bridgeStateStore: any BridgeStateStoring
  private let devicectl: any DeviceControlling
  private let dnssd: any DNSSDControlling
  private let tcpProbe: any TCPProbing
  private let vpnDiscovery: any VPNPeerDiscovering

  private var activeProxy: ProxyHandle?
  private var paused = false
  private var networkSatisfied = true
  private var latestSnapshot = BridgeStateSnapshot(
    state: .unconfigured,
    lastTransitionReason: "Supervisor initialized"
  )

  public init(
    configStore: any ConfigStoring = FileConfigStore(),
    bridgeStateStore: any BridgeStateStoring = FileBridgeStateStore(),
    devicectl: any DeviceControlling = SystemDeviceCtlClient(),
    dnssd: any DNSSDControlling = SystemDNSSDController(),
    tcpProbe: any TCPProbing = NWConnectionTCPProbe(),
    vpnDiscovery: any VPNPeerDiscovering = SystemVPNPeerDiscovery()
  ) {
    self.configStore = configStore
    self.bridgeStateStore = bridgeStateStore
    self.devicectl = devicectl
    self.dnssd = dnssd
    self.tcpProbe = tcpProbe
    self.vpnDiscovery = vpnDiscovery
  }

  public func currentSnapshot() async -> BridgeStateSnapshot {
    latestSnapshot
  }

  public func ensureReadyForDeployment() async -> BridgeStateSnapshot {
    if activeProxy == nil,
      let persisted = try? bridgeStateStore.load(),
      persisted.state == .bridgingActive || persisted.state == .nativeLocalStandby,
      Date().timeIntervalSince(persisted.lastUpdated) < 60
    {
      latestSnapshot = persisted
      return persisted
    }
    return await reconcileOnce()
  }

  public func isPaused() -> Bool {
    paused
  }

  public func setPaused(_ shouldPause: Bool) async -> BridgeStateSnapshot {
    paused = shouldPause
    if shouldPause {
      await teardownActiveProxy()
    }
    return await reconcileOnce()
  }

  public func stop(persistState: Bool = true) async {
    await teardownActiveProxy()
    guard persistState else { return }
    let config = try? configStore.load()
    let nextState: BridgeRuntimeState = config?.managedDevice == nil ? .unconfigured : .paused
    await persistSnapshot(
      BridgeStateSnapshot(
        state: nextState,
        lastTransitionReason: "Bridge stopped"
      )
    )
  }

  public func handleSystemEvent(_ event: SystemBridgeEvent) async -> BridgeStateSnapshot {
    switch event {
    case .systemWillSleep:
      await teardownActiveProxy()
      return await persistSnapshot(
        BridgeStateSnapshot(
          state: .paused,
          lastTransitionReason: "Mac is going to sleep; tore down mDNS proxy cleanly"
        )
      )
    case .systemDidWake:
      networkSatisfied = true
      return await reconcileOnce()
    case .networkChanged(let isSatisfied):
      networkSatisfied = isSatisfied
      if !isSatisfied {
        await teardownActiveProxy()
        return await persistSnapshot(
          BridgeStateSnapshot(
            state: .vpnUnavailable,
            vpnReachable: false,
            lastTransitionReason: "Local network path became unsatisfied"
          )
        )
      }
      return await reconcileOnce()
    }
  }

  public func reconcileOnce() async -> BridgeStateSnapshot {
    var config: DebagrConfig
    do {
      config = try configStore.load()
    } catch {
      await teardownActiveProxy()
      return await persistSnapshot(
        BridgeStateSnapshot(
          state: .error,
          lastTransitionReason:
            "Failed loading Debagr configuration: \(error.localizedDescription)",
          consecutiveFailures: latestSnapshot.consecutiveFailures + 1
        )
      )
    }

    guard var managed = config.managedDevice else {
      await teardownActiveProxy()
      return await persistSnapshot(
        BridgeStateSnapshot(
          state: .unconfigured,
          lastTransitionReason: "No managed device configured"
        )
      )
    }

    if paused {
      await teardownActiveProxy()
      return await persistSnapshot(
        BridgeStateSnapshot(
          state: .paused,
          lastTransitionReason: "Bridge paused by user"
        )
      )
    }

    if !networkSatisfied {
      await teardownActiveProxy()
      return await persistSnapshot(
        BridgeStateSnapshot(
          state: .vpnUnavailable,
          vpnReachable: false,
          lastTransitionReason: "Mac network interface is currently offline"
        )
      )
    }

    // Check native CoreDevice state first so Debagr yields when device is connected natively.
    if config.preferences.yieldWhenNativelyLocal {
      if let devices = try? await devicectl.listDevices(timeout: 10),
        let matching = devices.first(where: { $0.matches(identifier: managed.udid) })
      {
        if matching.transportType == .wired {
          await teardownActiveProxy()
          return await persistSnapshot(
            BridgeStateSnapshot(
              state: .nativeLocalStandby,
              nativeTransport: .wired,
              vpnReachable: latestSnapshot.vpnReachable,
              lastTransitionReason: "Device is connected natively via USB; bridge standing by"
            )
          )
        }
        if activeProxy == nil
          && matching.transportType == .localNetwork
          && matching.tunnelState == .connected
        {
          return await persistSnapshot(
            BridgeStateSnapshot(
              state: .nativeLocalStandby,
              nativeTransport: .localNetwork,
              vpnReachable: latestSnapshot.vpnReachable,
              lastTransitionReason:
                "Device already has an active native local Wi-Fi tunnel; bridge standing by"
            )
          )
        }
      }
    }

    // Refresh Tailscale/Headscale dynamic peer IP if node ID or peer name is tracked.
    if managed.vpn.provider.supportsAutomaticDiscovery {
      let vpnEnv = await vpnDiscovery.discoverPeers(provider: managed.vpn.provider)
      if let updatedPeer = matchPeer(in: vpnEnv.peers, against: managed.vpn),
        let nextIP = updatedPeer.preferredPrivateIP,
        nextIP != managed.vpn.address
      {
        managed.vpn = VPNEndpoint(
          provider: managed.vpn.provider,
          address: nextIP,
          peerName: updatedPeer.name,
          tailscaleNodeID: updatedPeer.id,
          lockdownPort: managed.vpn.lockdownPort
        )
        config.managedDevice = managed
        try? configStore.save(config)
      }
    }

    guard IPValidation.isPrivateVPNAddress(managed.vpn.address) else {
      await teardownActiveProxy()
      return await persistSnapshot(
        BridgeStateSnapshot(
          state: .error,
          lastTransitionReason: "Configured VPN IP is not a valid private VPN address",
          consecutiveFailures: latestSnapshot.consecutiveFailures + 1
        )
      )
    }

    let reachable = await tcpProbe.probe(
      host: managed.vpn.address,
      port: managed.vpn.lockdownPort,
      timeoutSeconds: 3.0
    )

    guard reachable else {
      await teardownActiveProxy()
      return await persistSnapshot(
        BridgeStateSnapshot(
          state: .deviceOffline,
          vpnReachable: false,
          lastTransitionReason: "VPN TCP probe to port \(managed.vpn.lockdownPort) did not answer",
          consecutiveFailures: latestSnapshot.consecutiveFailures + 1
        )
      )
    }

    let proxyHost = Self.syntheticProxyHost(for: managed.udid)
    let desiredSpec = ProxyRegistrationSpec(
      instanceName: managed.wirelessIdentity.bonjourInstanceName,
      serviceType: managed.wirelessIdentity.serviceType,
      domain: managed.wirelessIdentity.domain,
      port: managed.wirelessIdentity.port,
      proxyHost: proxyHost,
      targetIP: managed.vpn.address,
      txtRecords: managed.wirelessIdentity.txtRecords
    )

    if let existing = activeProxy, existing.spec == desiredSpec {
      return await persistSnapshot(
        BridgeStateSnapshot(
          state: .bridgingActive,
          activeProxyHost: desiredSpec.targetIP,
          activeProxyPort: desiredSpec.port,
          vpnReachable: true,
          lastTransitionReason: "DNS-SD proxy healthy for \(managed.displayName)"
        )
      )
    }

    await teardownActiveProxy()

    do {
      let handle = try await dnssd.startProxy(desiredSpec)
      activeProxy = handle
      managed.lastVerifiedAt = Date()
      config.managedDevice = managed
      try? configStore.save(config)

      return await persistSnapshot(
        BridgeStateSnapshot(
          state: .bridgingActive,
          activeProxyHost: desiredSpec.targetIP,
          activeProxyPort: desiredSpec.port,
          vpnReachable: true,
          lastTransitionReason: "Registered DNS-SD proxy over \(managed.vpn.provider.displayName)"
        )
      )
    } catch {
      return await persistSnapshot(
        BridgeStateSnapshot(
          state: .error,
          vpnReachable: true,
          lastTransitionReason: "Failed registering DNS-SD proxy: \(error.localizedDescription)",
          consecutiveFailures: latestSnapshot.consecutiveFailures + 1
        )
      )
    }
  }

  public func discoverLocalWirelessCandidates(timeoutSeconds: TimeInterval = 3.0) async throws
    -> [BonjourServiceRecord]
  {
    try await dnssd.browseMobdevServices(timeoutSeconds: timeoutSeconds)
  }

  public func verifyAndBuildProfile(
    device: PhysicalDevice,
    vpnProvider: VPNProvider,
    vpnAddress: String,
    peerName: String? = nil,
    tailscaleNodeID: String? = nil,
    lockdownPort: UInt16 = VPNEndpoint.defaultLockdownPort,
    bonjourRecord: BonjourServiceRecord
  ) async throws -> WirelessSetupVerificationResult {
    guard device.isEligibleForDebagr, let udid = device.udid else {
      throw DebagrError(
        code: .deviceUnpaired,
        category: "setup",
        message: device.ineligibilityReason
          ?? "Selected device is not an eligible paired physical iPhone/iPad.",
        recoverable: true
      )
    }

    let trimmedAddress = vpnAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    switch IPValidation.classify(trimmedAddress) {
    case .privateVPNv4, .privateVPNv6:
      break
    case .invalidOrDisallowed(let reason):
      throw DebagrError(
        code: .vpnAddressInvalid,
        category: "vpn",
        message: reason,
        recoverable: true,
        nextSteps: [
          "Provide the device's private VPN IPv4 or IPv6 ULA address (for example 100.64.x.y or 10.x.y.z)."
        ]
      )
    }

    // Confirm the selected device still matches CoreDevice pairing right now
    let freshDevices = try await devicectl.listDevices(timeout: 15)
    guard let fresh = freshDevices.first(where: { $0.matches(identifier: udid) }),
      fresh.isEligibleForDebagr
    else {
      throw DebagrError(
        code: .deviceUnpaired,
        category: "setup",
        message: "Could not re-confirm '\(device.name)' as a paired physical device in CoreDevice.",
        recoverable: true
      )
    }

    let probeOK = await tcpProbe.probe(
      host: trimmedAddress,
      port: lockdownPort,
      timeoutSeconds: 3.5
    )

    var notes: [String] = [
      "Confirmed paired physical hardware '\(fresh.name)' (\(fresh.platform.rawValue)).",
      "Captured wireless Bonjour service identity (\(bonjourRecord.serviceType) on port \(bonjourRecord.port)).",
    ]
    if probeOK {
      notes.append("VPN TCP reachability probe succeeded on port \(lockdownPort).")
    } else {
      notes.append(
        "VPN TCP probe on port \(lockdownPort) did not respond right now (may require VPN enabled on phone or phone unlocked); profile can still be saved."
      )
    }

    let wirelessIdentity = WirelessIdentity(
      bonjourInstanceName: bonjourRecord.instanceName,
      serviceType: bonjourRecord.serviceType,
      domain: bonjourRecord.domain,
      port: bonjourRecord.port,
      txtRecords: bonjourRecord.txtRecords,
      confirmedHardwareUDID: udid,
      capturedAt: Date()
    )

    let profile = ManagedDeviceProfile(
      udid: udid,
      coreDeviceID: fresh.coreDeviceID,
      displayName: fresh.name,
      model: fresh.model,
      platform: fresh.platform,
      vpn: VPNEndpoint(
        provider: vpnProvider,
        address: trimmedAddress,
        peerName: peerName,
        tailscaleNodeID: tailscaleNodeID,
        lockdownPort: lockdownPort
      ),
      wirelessIdentity: wirelessIdentity,
      savedAt: Date(),
      lastVerifiedAt: probeOK ? Date() : nil
    )

    return WirelessSetupVerificationResult(
      profile: profile,
      vpnProbeSucceeded: probeOK,
      notes: notes
    )
  }

  private func matchPeer(in peers: [VPNPeer], against vpn: VPNEndpoint) -> VPNPeer? {
    if let nodeID = vpn.tailscaleNodeID,
      let byID = peers.first(where: { $0.id == nodeID })
    {
      return byID
    }
    if let peerName = vpn.peerName,
      let byName = peers.first(where: { $0.name.caseInsensitiveCompare(peerName) == .orderedSame })
    {
      return byName
    }
    return nil
  }

  private func teardownActiveProxy() async {
    if let existing = activeProxy {
      activeProxy = nil
      await dnssd.stopProxy(existing)
    }
  }

  @discardableResult
  private func persistSnapshot(_ snapshot: BridgeStateSnapshot) async -> BridgeStateSnapshot {
    latestSnapshot = snapshot
    try? bridgeStateStore.save(snapshot)
    return snapshot
  }

  public static func syntheticProxyHost(for udid: String) -> String {
    let cleaned =
      udid
      .lowercased()
      .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
      .prefix(16)
    let suffix = cleaned.isEmpty ? "device" : String(cleaned)
    return "debagr-\(suffix).local."
  }
}
