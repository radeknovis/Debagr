import Foundation

public protocol BridgeEnsuring: Sendable {
  func currentSnapshot() async -> BridgeStateSnapshot
  func ensureReadyForDeployment() async -> BridgeStateSnapshot
}

public final class DeploymentCoordinator: Sendable {
  private let devicectl: any DeviceControlling
  private let appValidator: any AppBundleValidating
  private let configStore: any ConfigStoring
  private let receiptStore: any ReceiptStoring
  private let bridgeStateStore: any BridgeStateStoring
  private let vpnDiscovery: any VPNPeerDiscovering
  private let runner: any CommandRunning
  private let bridgeEnsurer: (any BridgeEnsuring)?

  public init(
    devicectl: any DeviceControlling = SystemDeviceCtlClient(),
    appValidator: any AppBundleValidating = SystemAppBundleValidator(),
    configStore: any ConfigStoring = FileConfigStore(),
    receiptStore: any ReceiptStoring = FileReceiptStore(),
    bridgeStateStore: any BridgeStateStoring = FileBridgeStateStore(),
    vpnDiscovery: any VPNPeerDiscovering = SystemVPNPeerDiscovery(),
    runner: any CommandRunning = SubprocessRunner(),
    bridgeEnsurer: (any BridgeEnsuring)? = nil
  ) {
    self.devicectl = devicectl
    self.appValidator = appValidator
    self.configStore = configStore
    self.receiptStore = receiptStore
    self.bridgeStateStore = bridgeStateStore
    self.vpnDiscovery = vpnDiscovery
    self.runner = runner
    self.bridgeEnsurer = bridgeEnsurer
  }

  public func listDevices(includeIneligible: Bool = false) async throws -> [PhysicalDevice] {
    let devices = try await devicectl.listDevices(timeout: 20)
    if includeIneligible {
      return devices
    }
    return devices.filter(\.isEligibleForDebagr)
  }

  public func checkReadiness(
    deviceOverride: String? = nil,
    timeoutSeconds: TimeInterval = 20
  ) async throws -> ReadinessReport {
    let config = try configStore.load()
    var checks: [ReadinessCheckItem] = []
    var blockers: [DebagrErrorPayload] = []

    let bridgeSnapshot: BridgeStateSnapshot
    if let bridgeEnsurer {
      bridgeSnapshot = await bridgeEnsurer.ensureReadyForDeployment()
    } else if let stored = try bridgeStateStore.load() {
      bridgeSnapshot = stored
    } else {
      bridgeSnapshot = BridgeStateSnapshot(
        state: config.managedDevice == nil ? .unconfigured : .probingVPN,
        lastTransitionReason: "No live bridge supervisor attached"
      )
    }

    let resolvedIdentifier: String
    let managed = config.managedDevice
    if let override = deviceOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
      !override.isEmpty
    {
      resolvedIdentifier = override
      checks.append(
        ReadinessCheckItem(
          name: "target_device_selection",
          passed: true,
          detail: "Using explicit device override \(Redactor.redactUDID(override))."
        )
      )
    } else if let managed {
      resolvedIdentifier = managed.udid
      checks.append(
        ReadinessCheckItem(
          name: "target_device_selection",
          passed: true,
          detail:
            "Configured managed device '\(managed.displayName)' (\(managed.vpn.provider.displayName))."
        )
      )
    } else {
      let err = DebagrError.deviceNotConfigured()
      checks.append(
        ReadinessCheckItem(
          name: "target_device_selection",
          passed: false,
          detail: err.payload.message
        )
      )
      blockers.append(err.payload)
      return ReadinessReport(
        ready: false,
        deviceName: nil,
        deviceUDIDRedacted: nil,
        connectionPath: "unconfigured",
        pairingState: .unknown,
        lockState: .unknown,
        bridgeState: bridgeSnapshot.state,
        checks: checks,
        blockers: blockers
      )
    }

    let allDevices = try await devicectl.listDevices(timeout: timeoutSeconds)
    guard let device = allDevices.first(where: { $0.matches(identifier: resolvedIdentifier) })
    else {
      let err = DebagrError(
        code: .deviceNotFound,
        category: "discovery",
        message: "Target device was not found in CoreDevice (`devicectl`).",
        recoverable: true,
        nextSteps: [
          "Ensure the bridge is running (`debagr bridge status`) if the device is remote over VPN.",
          "Or connect the device via USB / local Wi-Fi to verify pairing.",
        ]
      )
      checks.append(
        ReadinessCheckItem(name: "coredevice_presence", passed: false, detail: err.payload.message))
      blockers.append(err.payload)
      return ReadinessReport(
        ready: false,
        deviceName: managed?.displayName,
        deviceUDIDRedacted: Redactor.redactUDID(resolvedIdentifier),
        connectionPath: bridgeSnapshot.state.displayTitle,
        pairingState: .unknown,
        lockState: .unknown,
        bridgeState: bridgeSnapshot.state,
        checks: checks,
        blockers: blockers
      )
    }

    checks.append(
      ReadinessCheckItem(
        name: "coredevice_presence",
        passed: true,
        detail: "Found '\(device.name)' (\(device.platform.rawValue) \(device.osVersion ?? ""))."
      )
    )

    if !device.isEligibleForDebagr {
      let reason =
        device.ineligibilityReason ?? "Device is not an eligible paired physical iPhone/iPad."
      let code: DebagrErrorCode = device.pairingState != .paired ? .deviceUnpaired : .deviceNotFound
      let err = DebagrError(code: code, category: "eligibility", message: reason, recoverable: true)
      checks.append(ReadinessCheckItem(name: "device_eligibility", passed: false, detail: reason))
      blockers.append(err.payload)
    } else {
      checks.append(
        ReadinessCheckItem(
          name: "device_eligibility", passed: true,
          detail: "Paired physical \(device.platform.rawValue) device.")
      )
    }

    if device.isDeveloperModeEnabled == false {
      let err = DebagrError(
        code: .developerModeDisabled,
        category: "device_state",
        message: "Developer Mode is disabled on '\(device.name)'.",
        recoverable: true,
        nextSteps: ["Enable Settings > Privacy & Security > Developer Mode on the device."]
      )
      checks.append(
        ReadinessCheckItem(name: "developer_mode", passed: false, detail: err.payload.message))
      blockers.append(err.payload)
    } else {
      checks.append(
        ReadinessCheckItem(
          name: "developer_mode",
          passed: true,
          detail: device.isDeveloperModeEnabled == true
            ? "Developer Mode enabled." : "Developer Mode status not reported as disabled."
        )
      )
    }

    let lockState: LockState
    do {
      lockState = try await devicectl.lockState(
        identifier: device.primaryIdentifier, timeout: timeoutSeconds)
      if lockState.blocksForegroundLaunch {
        let err = DebagrError.deviceLocked(deviceName: device.name)
        checks.append(
          ReadinessCheckItem(
            name: "device_lock_state",
            passed: false,
            detail: "Device is currently locked (\(lockState.rawValue))."
          )
        )
        blockers.append(err.payload)
      } else {
        checks.append(
          ReadinessCheckItem(
            name: "device_lock_state",
            passed: true,
            detail: "Device lock state: \(lockState.rawValue)."
          )
        )
      }
    } catch let debagrErr as DebagrError {
      lockState = debagrErr.payload.code == .deviceLocked ? .locked : .unknown
      checks.append(
        ReadinessCheckItem(
          name: "device_lock_state", passed: false, detail: debagrErr.payload.message))
      blockers.append(debagrErr.payload)
    }

    let pathDescription: String
    if device.transportType == .wired {
      pathDescription = "Native USB"
    } else if bridgeSnapshot.state == .bridgingActive {
      pathDescription = "VPN Bridge (\(managed?.vpn.provider.displayName ?? "VPN"))"
    } else if device.transportType == .localNetwork {
      pathDescription = "Local Wi-Fi"
    } else {
      pathDescription = bridgeSnapshot.state.displayTitle
    }

    return ReadinessReport(
      ready: blockers.isEmpty,
      deviceName: device.name,
      deviceUDIDRedacted: Redactor.redactUDID(device.udid ?? device.coreDeviceID),
      connectionPath: pathDescription,
      pairingState: device.pairingState,
      lockState: lockState,
      bridgeState: bridgeSnapshot.state,
      checks: checks,
      blockers: blockers
    )
  }

  public func doctor(strictRedaction: Bool = true) async throws -> DoctorReport {
    let config = try configStore.load()
    let recentReceipts = (try? receiptStore.listRecent(limit: 10)) ?? []
    let bridgeSnapshot = try? bridgeStateStore.load()
    let devicectlVer = try? await devicectl.version()
    let xcodeVer = await readXcodeVersion()

    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    var arch = "unknown"
    #if arch(arm64)
      arch = "arm64"
    #elseif arch(x86_64)
      arch = "x86_64"
    #endif

    let storageOK =
      configStore.verifyPermissions()
      && receiptStore.verifyPermissions()
      && bridgeStateStore.verifyPermissions()

    var warnings: [String] = []
    if !storageOK {
      warnings.append("Local storage file permissions are broader than 0600/0700.")
    }
    if devicectlVer == nil {
      warnings.append("`xcrun devicectl` could not be executed; verify Xcode installation.")
    }

    let deviceSummary: String?
    let vpnStatusSummary: String
    if let managed = config.managedDevice {
      let redactedUDID = Redactor.redactUDID(managed.udid)
      let shownIP = Redactor.redactIP(managed.vpn.address, strict: strictRedaction) ?? "redacted"
      deviceSummary = "\(managed.displayName) (\(managed.platform.rawValue), UDID \(redactedUDID))"
      let envStatus = await vpnDiscovery.discoverPeers(provider: managed.vpn.provider)
      vpnStatusSummary =
        "\(managed.vpn.provider.displayName) endpoint \(shownIP):\(managed.vpn.lockdownPort) — \(envStatus.detail)"
    } else {
      deviceSummary = nil
      let tailscaleStatus = await vpnDiscovery.discoverPeers(provider: .tailscale)
      vpnStatusSummary = "No managed device configured. Tailscale check: \(tailscaleStatus.detail)"
    }

    let safeBridgeSnapshot = bridgeSnapshot.map { snap in
      BridgeStateSnapshot(
        state: snap.state,
        activeProxyHost: Redactor.redactIP(snap.activeProxyHost, strict: strictRedaction),
        activeProxyPort: snap.activeProxyPort,
        nativeTransport: snap.nativeTransport,
        vpnReachable: snap.vpnReachable,
        lastUpdated: snap.lastUpdated,
        lastTransitionReason: Redactor.redactFreeformText(
          snap.lastTransitionReason,
          knownSensitiveValues: sensitiveValues(from: config)
        ),
        consecutiveFailures: snap.consecutiveFailures
      )
    }

    return DoctorReport(
      debagrVersion: DebagrVersion.current,
      macOSVersion: osVersion,
      architecture: arch,
      xcodeVersion: xcodeVer,
      devicectlVersion: devicectlVer,
      configuredDeviceSummary: deviceSummary,
      vpnStatus: Redactor.redactFreeformText(
        vpnStatusSummary,
        knownSensitiveValues: sensitiveValues(from: config)
      ),
      bridgeSnapshot: safeBridgeSnapshot,
      storagePermissionsOK: storageOK,
      recentReceipts: recentReceipts,
      warnings: warnings,
      redacted: strictRedaction
    )
  }

  public func listApps(
    deviceOverride: String? = nil,
    bundleID: String? = nil,
    timeoutSeconds: TimeInterval = 25
  ) async throws -> [InstalledApp] {
    let target = try await resolveTargetDevice(
      deviceOverride: deviceOverride, timeout: timeoutSeconds)
    return try await devicectl.listApps(
      identifier: target.primaryIdentifier,
      bundleID: bundleID,
      timeout: timeoutSeconds
    )
  }

  public func install(
    appPath: String,
    deviceOverride: String? = nil,
    verify: Bool = true,
    timeoutSeconds: TimeInterval? = nil
  ) async throws -> InstallResult {
    let start = ContinuousClock.now
    let config = try configStore.load()
    let effectiveTimeout =
      timeoutSeconds ?? TimeInterval(config.preferences.defaultDeployTimeoutSeconds)
    let bundle = try await appValidator.validate(appPath: appPath)
    let target = try await resolveTargetDevice(deviceOverride: deviceOverride, timeout: 20)
    let redactedUDID = Redactor.redactUDID(target.udid ?? target.coreDeviceID)

    do {
      let outcome = try await devicectl.installApp(
        identifier: target.primaryIdentifier,
        appPath: bundle.path,
        timeout: effectiveTimeout
      )

      var verified = !verify
      if verify {
        let installed = try await devicectl.listApps(
          identifier: target.primaryIdentifier,
          bundleID: bundle.bundleIdentifier,
          timeout: 25
        )
        verified = installed.contains(where: { $0.bundleIdentifier == bundle.bundleIdentifier })
        if !verified {
          let err = DebagrError(
            code: .installVerificationFailed,
            category: "verification",
            message:
              "devicectl install returned without error, but '\(bundle.bundleIdentifier)' was not reported by `device info apps`.",
            recoverable: true,
            nextSteps: [
              "Inspect installed apps with `debagr apps --bundle-id \(bundle.bundleIdentifier)`.",
              "Check provisioning profile trust and device storage space.",
            ]
          )
          saveReceiptBestEffort(
            operation: .install,
            outcome: .failed,
            deviceUDIDRedacted: redactedUDID,
            deviceName: target.name,
            bundle: bundle,
            installed: true,
            verified: false,
            launched: false,
            pid: nil,
            durationMs: elapsedMs(since: start),
            errorCode: err.payload.code,
            summary: err.payload.message
          )
          throw err
        }
      }

      let duration = elapsedMs(since: start)
      let receipt = try recordReceipt(
        operation: .install,
        outcome: .succeeded,
        deviceUDIDRedacted: redactedUDID,
        deviceName: target.name,
        bundle: bundle,
        installed: true,
        verified: verified,
        launched: false,
        pid: nil,
        durationMs: duration,
        errorCode: nil,
        summary: "Installed \(bundle.bundleIdentifier) on \(target.name)."
      )

      return InstallResult(
        deviceName: target.name,
        deviceUDIDRedacted: redactedUDID,
        bundleIdentifier: bundle.bundleIdentifier,
        verifiedInstalled: verified,
        launchServicesIdentifier: outcome.launchServicesIdentifier,
        durationMs: duration,
        receiptID: receipt.id
      )
    } catch let err as DebagrError {
      if err.payload.code == .operationTimeoutUncertain {
        let verifiedAfter = await probeAppInstalledAfterTimeout(
          deviceIdentifier: target.primaryIdentifier,
          bundleID: bundle.bundleIdentifier
        )
        let uncertainErr = DebagrError.operationTimeoutUncertain(
          operation: "Install of '\(bundle.bundleIdentifier)'",
          timeoutSeconds: effectiveTimeout,
          bundleID: bundle.bundleIdentifier,
          installedVerifiedAfterTimeout: verifiedAfter
        )
        saveReceiptBestEffort(
          operation: .install,
          outcome: .uncertainTimeout,
          deviceUDIDRedacted: redactedUDID,
          deviceName: target.name,
          bundle: bundle,
          installed: verifiedAfter ?? false,
          verified: verifiedAfter ?? false,
          launched: false,
          pid: nil,
          durationMs: elapsedMs(since: start),
          errorCode: uncertainErr.payload.code,
          summary: uncertainErr.payload.message
        )
        throw uncertainErr
      }

      saveReceiptBestEffort(
        operation: .install,
        outcome: .failed,
        deviceUDIDRedacted: redactedUDID,
        deviceName: target.name,
        bundle: bundle,
        installed: false,
        verified: false,
        launched: false,
        pid: nil,
        durationMs: elapsedMs(since: start),
        errorCode: err.payload.code,
        summary: err.payload.message
      )
      throw err
    }
  }

  public func launch(
    bundleID: String,
    deviceOverride: String? = nil,
    arguments: [String] = [],
    environment: [String: String] = [:],
    terminateExisting: Bool = false,
    launchServicesIdentifier: String? = nil,
    timeoutSeconds: TimeInterval = 45
  ) async throws -> LaunchResult {
    let start = ContinuousClock.now
    let target = try await resolveTargetDevice(deviceOverride: deviceOverride, timeout: 20)
    let redactedUDID = Redactor.redactUDID(target.udid ?? target.coreDeviceID)

    let lockState = try await devicectl.lockState(identifier: target.primaryIdentifier, timeout: 15)
    if lockState.blocksForegroundLaunch {
      let lockedErr = DebagrError.deviceLocked(deviceName: target.name, bundleID: bundleID)
      saveReceiptBestEffort(
        operation: .launch,
        outcome: .failed,
        deviceUDIDRedacted: redactedUDID,
        deviceName: target.name,
        bundleID: bundleID,
        installed: true,
        verified: true,
        launched: false,
        pid: nil,
        durationMs: elapsedMs(since: start),
        errorCode: lockedErr.payload.code,
        summary: lockedErr.payload.message
      )
      throw lockedErr
    }

    do {
      let launchOutcome = try await devicectl.launchApp(
        identifier: target.primaryIdentifier,
        bundleID: bundleID,
        arguments: arguments,
        environment: environment,
        terminateExisting: terminateExisting,
        launchServicesIdentifier: launchServicesIdentifier,
        timeout: timeoutSeconds
      )
      let duration = elapsedMs(since: start)
      let receipt = try recordReceipt(
        operation: .launch,
        outcome: .succeeded,
        deviceUDIDRedacted: redactedUDID,
        deviceName: target.name,
        bundleID: bundleID,
        installed: true,
        verified: true,
        launched: true,
        pid: launchOutcome.pid,
        durationMs: duration,
        errorCode: nil,
        summary: "Launched \(bundleID) on \(target.name)."
      )
      return LaunchResult(
        deviceName: target.name,
        deviceUDIDRedacted: redactedUDID,
        bundleIdentifier: bundleID,
        pid: launchOutcome.pid,
        durationMs: duration,
        receiptID: receipt.id
      )
    } catch let err as DebagrError {
      let outcome: DeploymentOutcome =
        err.payload.code == .operationTimeoutUncertain ? .uncertainTimeout : .failed
      saveReceiptBestEffort(
        operation: .launch,
        outcome: outcome,
        deviceUDIDRedacted: redactedUDID,
        deviceName: target.name,
        bundleID: bundleID,
        installed: true,
        verified: true,
        launched: false,
        pid: nil,
        durationMs: elapsedMs(since: start),
        errorCode: err.payload.code,
        summary: err.payload.message
      )
      throw err
    }
  }

  public func deploy(
    appPath: String,
    deviceOverride: String? = nil,
    launchAfterInstall: Bool = true,
    terminateExisting: Bool = false,
    timeoutSeconds: TimeInterval? = nil
  ) async throws -> DeployResult {
    let start = ContinuousClock.now
    let config = try configStore.load()
    let effectiveTimeout =
      timeoutSeconds ?? TimeInterval(config.preferences.defaultDeployTimeoutSeconds)

    let bundle = try await appValidator.validate(appPath: appPath)
    let target = try await resolveTargetDevice(deviceOverride: deviceOverride, timeout: 20)
    let redactedUDID = Redactor.redactUDID(target.udid ?? target.coreDeviceID)

    if target.isDeveloperModeEnabled == false {
      throw DebagrError(
        code: .developerModeDisabled,
        category: "device_state",
        message: "Developer Mode is disabled on '\(target.name)'.",
        recoverable: true,
        nextSteps: ["Enable Settings > Privacy & Security > Developer Mode on the device."]
      )
    }

    if launchAfterInstall {
      let initialLockState = try await devicectl.lockState(
        identifier: target.primaryIdentifier,
        timeout: 15
      )
      if initialLockState.blocksForegroundLaunch {
        let err = DebagrError.deviceLocked(
          deviceName: target.name,
          bundleID: bundle.bundleIdentifier
        )
        saveReceiptBestEffort(
          operation: .deploy,
          outcome: .failed,
          deviceUDIDRedacted: redactedUDID,
          deviceName: target.name,
          bundle: bundle,
          installed: false,
          verified: false,
          launched: false,
          pid: nil,
          durationMs: elapsedMs(since: start),
          errorCode: err.payload.code,
          summary: err.payload.message
        )
        throw err
      }
    }

    let installOutcome: DeviceCtlInstallOutcome
    do {
      installOutcome = try await devicectl.installApp(
        identifier: target.primaryIdentifier,
        appPath: bundle.path,
        timeout: effectiveTimeout
      )
    } catch let err as DebagrError {
      if err.payload.code == .operationTimeoutUncertain {
        let verifiedAfter = await probeAppInstalledAfterTimeout(
          deviceIdentifier: target.primaryIdentifier,
          bundleID: bundle.bundleIdentifier
        )
        let uncertainErr = DebagrError.operationTimeoutUncertain(
          operation: "Install of '\(bundle.bundleIdentifier)'",
          timeoutSeconds: effectiveTimeout,
          bundleID: bundle.bundleIdentifier,
          installedVerifiedAfterTimeout: verifiedAfter
        )
        saveReceiptBestEffort(
          operation: .deploy,
          outcome: .uncertainTimeout,
          deviceUDIDRedacted: redactedUDID,
          deviceName: target.name,
          bundle: bundle,
          installed: verifiedAfter ?? false,
          verified: verifiedAfter ?? false,
          launched: false,
          pid: nil,
          durationMs: elapsedMs(since: start),
          errorCode: uncertainErr.payload.code,
          summary: uncertainErr.payload.message
        )
        throw uncertainErr
      }

      saveReceiptBestEffort(
        operation: .deploy,
        outcome: .failed,
        deviceUDIDRedacted: redactedUDID,
        deviceName: target.name,
        bundle: bundle,
        installed: false,
        verified: false,
        launched: false,
        pid: nil,
        durationMs: elapsedMs(since: start),
        errorCode: err.payload.code,
        summary: err.payload.message
      )
      throw err
    }

    let installedApps = try await devicectl.listApps(
      identifier: target.primaryIdentifier,
      bundleID: bundle.bundleIdentifier,
      timeout: 25
    )
    let verified = installedApps.contains(where: { $0.bundleIdentifier == bundle.bundleIdentifier })
    guard verified else {
      let err = DebagrError(
        code: .installVerificationFailed,
        category: "verification",
        message:
          "App installation completed without error, but '\(bundle.bundleIdentifier)' could not be verified on '\(target.name)'.",
        recoverable: true,
        nextSteps: [
          "Run `debagr apps --bundle-id \(bundle.bundleIdentifier)` to check installed bundles."
        ]
      )
      saveReceiptBestEffort(
        operation: .deploy,
        outcome: .failed,
        deviceUDIDRedacted: redactedUDID,
        deviceName: target.name,
        bundle: bundle,
        installed: true,
        verified: false,
        launched: false,
        pid: nil,
        durationMs: elapsedMs(since: start),
        errorCode: err.payload.code,
        summary: err.payload.message
      )
      throw err
    }

    guard launchAfterInstall else {
      let duration = elapsedMs(since: start)
      let receipt = try recordReceipt(
        operation: .deploy,
        outcome: .succeeded,
        deviceUDIDRedacted: redactedUDID,
        deviceName: target.name,
        bundle: bundle,
        installed: true,
        verified: true,
        launched: false,
        pid: nil,
        durationMs: duration,
        errorCode: nil,
        summary:
          "Installed and verified \(bundle.bundleIdentifier) on \(target.name) (launch skipped)."
      )
      return DeployResult(
        deviceName: target.name,
        deviceUDIDRedacted: redactedUDID,
        bundleIdentifier: bundle.bundleIdentifier,
        installed: true,
        verifiedInstalled: true,
        launched: false,
        pid: nil,
        launchServicesIdentifier: installOutcome.launchServicesIdentifier,
        durationMs: duration,
        receiptID: receipt.id
      )
    }

    do {
      let postInstallLock = try await devicectl.lockState(
        identifier: target.primaryIdentifier,
        timeout: 15
      )
      if postInstallLock.blocksForegroundLaunch {
        let partialErr = DebagrError.installSucceededLaunchFailed(
          bundleID: bundle.bundleIdentifier,
          launchServicesIdentifier: installOutcome.launchServicesIdentifier,
          reason: "Device is locked (\(postInstallLock.rawValue)).",
          deviceLocked: true
        )
        saveReceiptBestEffort(
          operation: .deploy,
          outcome: .partialSuccessLaunchFailed,
          deviceUDIDRedacted: redactedUDID,
          deviceName: target.name,
          bundle: bundle,
          installed: true,
          verified: true,
          launched: false,
          pid: nil,
          durationMs: elapsedMs(since: start),
          errorCode: partialErr.payload.code,
          summary: partialErr.payload.message
        )
        throw partialErr
      }

      let launchOutcome = try await devicectl.launchApp(
        identifier: target.primaryIdentifier,
        bundleID: bundle.bundleIdentifier,
        arguments: [],
        environment: [:],
        terminateExisting: terminateExisting,
        launchServicesIdentifier: installOutcome.launchServicesIdentifier,
        timeout: 45
      )

      let duration = elapsedMs(since: start)
      let receipt = try recordReceipt(
        operation: .deploy,
        outcome: .succeeded,
        deviceUDIDRedacted: redactedUDID,
        deviceName: target.name,
        bundle: bundle,
        installed: true,
        verified: true,
        launched: true,
        pid: launchOutcome.pid,
        durationMs: duration,
        errorCode: nil,
        summary: "Installed, verified, and launched \(bundle.bundleIdentifier) on \(target.name)."
      )

      return DeployResult(
        deviceName: target.name,
        deviceUDIDRedacted: redactedUDID,
        bundleIdentifier: bundle.bundleIdentifier,
        installed: true,
        verifiedInstalled: true,
        launched: true,
        pid: launchOutcome.pid,
        launchServicesIdentifier: installOutcome.launchServicesIdentifier,
        durationMs: duration,
        receiptID: receipt.id
      )
    } catch let err as DebagrError {
      if err.payload.code == .installSucceededLaunchFailed {
        throw err
      }
      if err.payload.code == .operationTimeoutUncertain {
        let uncertainErr = DebagrError(
          code: .operationTimeoutUncertain,
          category: "timeout",
          message:
            "Installed and verified '\(bundle.bundleIdentifier)', but launch timed out with uncertain outcome.",
          recoverable: true,
          partialSuccess: PartialDeployState(
            installed: true,
            verifiedInstalled: true,
            launched: false,
            bundleIdentifier: bundle.bundleIdentifier,
            launchServicesIdentifier: installOutcome.launchServicesIdentifier,
            pid: nil
          ),
          nextSteps: [
            "The app is already installed; do not reinstall unless code changed.",
            "Check device screen and retry launch with `debagr launch --bundle-id \(bundle.bundleIdentifier)`.",
          ]
        )
        saveReceiptBestEffort(
          operation: .deploy,
          outcome: .uncertainTimeout,
          deviceUDIDRedacted: redactedUDID,
          deviceName: target.name,
          bundle: bundle,
          installed: true,
          verified: true,
          launched: false,
          pid: nil,
          durationMs: elapsedMs(since: start),
          errorCode: uncertainErr.payload.code,
          summary: uncertainErr.payload.message
        )
        throw uncertainErr
      }

      let isLocked = err.payload.code == .deviceLocked
      let partialErr = DebagrError.installSucceededLaunchFailed(
        bundleID: bundle.bundleIdentifier,
        launchServicesIdentifier: installOutcome.launchServicesIdentifier,
        reason: err.payload.message,
        deviceLocked: isLocked
      )
      saveReceiptBestEffort(
        operation: .deploy,
        outcome: .partialSuccessLaunchFailed,
        deviceUDIDRedacted: redactedUDID,
        deviceName: target.name,
        bundle: bundle,
        installed: true,
        verified: true,
        launched: false,
        pid: nil,
        durationMs: elapsedMs(since: start),
        errorCode: partialErr.payload.code,
        summary: partialErr.payload.message
      )
      throw partialErr
    }
  }

  private func resolveTargetDevice(deviceOverride: String?, timeout: TimeInterval) async throws
    -> PhysicalDevice
  {
    if let bridgeEnsurer {
      _ = await bridgeEnsurer.ensureReadyForDeployment()
    }

    let config = try configStore.load()
    let desiredIdentifier: String
    if let override = deviceOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
      !override.isEmpty
    {
      desiredIdentifier = override
    } else if let managed = config.managedDevice {
      desiredIdentifier = managed.udid
    } else {
      throw DebagrError.deviceNotConfigured()
    }

    let allDevices = try await devicectl.listDevices(timeout: timeout)
    guard let matched = allDevices.first(where: { $0.matches(identifier: desiredIdentifier) })
    else {
      throw DebagrError(
        code: .deviceUnreachable,
        category: "connectivity",
        message:
          "Configured device (\(Redactor.redactUDID(desiredIdentifier))) is not visible to CoreDevice.",
        recoverable: true,
        nextSteps: [
          "Run `debagr ready` and `debagr bridge status` to check VPN reachability.",
          "Ensure the iPhone/iPad is awake on Wi-Fi with the private VPN active.",
        ]
      )
    }

    if !matched.isEligibleForDebagr {
      throw DebagrError(
        code: matched.pairingState != .paired ? .deviceUnpaired : .deviceNotFound,
        category: "eligibility",
        message: matched.ineligibilityReason
          ?? "Target device is ineligible for Debagr deployment.",
        recoverable: true
      )
    }
    return matched
  }

  private func probeAppInstalledAfterTimeout(
    deviceIdentifier: String,
    bundleID: String
  ) async -> Bool? {
    guard
      let apps = try? await devicectl.listApps(
        identifier: deviceIdentifier,
        bundleID: bundleID,
        timeout: 15
      )
    else {
      return nil
    }
    return apps.contains(where: { $0.bundleIdentifier == bundleID })
  }

  private func saveReceiptBestEffort(
    operation: DeploymentOperation,
    outcome: DeploymentOutcome,
    deviceUDIDRedacted: String,
    deviceName: String,
    bundle: ValidatedAppBundle? = nil,
    bundleID: String? = nil,
    installed: Bool,
    verified: Bool,
    launched: Bool,
    pid: Int?,
    durationMs: Int,
    errorCode: DebagrErrorCode?,
    summary: String
  ) {
    do {
      _ = try recordReceipt(
        operation: operation,
        outcome: outcome,
        deviceUDIDRedacted: deviceUDIDRedacted,
        deviceName: deviceName,
        bundle: bundle,
        bundleID: bundleID,
        installed: installed,
        verified: verified,
        launched: launched,
        pid: pid,
        durationMs: durationMs,
        errorCode: errorCode,
        summary: summary
      )
    } catch {}
  }

  @discardableResult
  private func recordReceipt(
    operation: DeploymentOperation,
    outcome: DeploymentOutcome,
    deviceUDIDRedacted: String,
    deviceName: String,
    bundle: ValidatedAppBundle? = nil,
    bundleID: String? = nil,
    installed: Bool,
    verified: Bool,
    launched: Bool,
    pid: Int?,
    durationMs: Int,
    errorCode: DebagrErrorCode?,
    summary: String
  ) throws -> DeploymentReceipt {
    let receipt = DeploymentReceipt(
      operation: operation,
      outcome: outcome,
      deviceUDIDRedacted: deviceUDIDRedacted,
      deviceName: deviceName,
      bundleIdentifier: bundle?.bundleIdentifier ?? bundleID,
      appVersion: bundle?.shortVersion,
      appBuild: bundle?.buildVersion,
      appPathName: bundle.map { URL(fileURLWithPath: $0.path).lastPathComponent },
      installed: installed,
      verifiedInstalled: verified,
      launched: launched,
      pid: pid,
      durationMs: durationMs,
      errorCode: errorCode,
      summary: summary
    )
    try receiptStore.append(receipt)
    return receipt
  }

  private func readXcodeVersion() async -> String? {
    guard
      let result = try? await runner.run(
        executable: "/usr/bin/xcodebuild",
        arguments: ["-version"],
        timeoutSeconds: 8
      ), result.exitCode == 0, !result.timedOut
    else {
      return nil
    }
    let lines = result.stdoutString
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return lines.isEmpty ? nil : lines.joined(separator: " ")
  }

  private func sensitiveValues(from config: DebagrConfig) -> [String] {
    guard let managed = config.managedDevice else { return [] }
    var values = [managed.udid, managed.coreDeviceID, managed.wirelessIdentity.bonjourInstanceName]
    values.append(contentsOf: managed.wirelessIdentity.txtRecords.values)
    return values
  }

  private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
    let duration = ContinuousClock.now - start
    let ms =
      duration.components.seconds * 1000
      + duration.components.attoseconds / 1_000_000_000_000_000
    return max(0, Int(ms))
  }
}
