import XCTest

@testable import Debagr

final class ParserTests: XCTestCase {
  func testAgentCommandsAreExplicitAndCannotStartCompetingRelays() throws {
    let status = try CommandLineOptions.parse([
      "--status", "--device", "udid", "--timeout", "30", "--json",
    ])
    XCTAssertEqual(status.agentCommand, "status")
    XCTAssertTrue(status.json)
    XCTAssertEqual(status.interfaceName, "auto")
    XCTAssertEqual(try CommandLineOptions.parse(["--devices", "--json"]).agentCommand, "devices")
    for arguments in [
      ["--status", "--json"], ["--json"], ["--devices", "--status", "--device", "udid"],
      ["--devices", "--deploy-app", "/tmp/Test.app", "--device", "udid"],
      ["--deploy-app", "/tmp/Test.app", "--device", "udid", "--menu-bar"],
      ["--status", "--device", "udid", "--direct-device", "--peer", "phone"],
    ] { XCTAssertThrowsError(try CommandLineOptions.parse(arguments)) }
  }

  func testReadinessRequiresAnExplicitUnlockedAppleResult() throws {
    let ready = Data(#"{"result":{"passcodeRequired":false,"unlockedSinceBoot":true}}"#.utf8)
    var commands: [[String]] = []
    let deployer = DeviceDeployer(run: { args, _ in
      commands.append(args)
      return ready
    })
    try deployer.checkReady(deviceIdentifier: "udid")
    XCTAssertTrue(commands[0].contains("lockState"))
    XCTAssertTrue(commands[0].contains("udid"))
    for data in [
      Data(#"{"result":{}}"#.utf8),
      Data(#"{"result":{"passcodeRequired":true,"unlockedSinceBoot":true}}"#.utf8),
    ] {
      XCTAssertThrowsError(
        try DeviceDeployer(run: { _, _ in data }).checkReady(deviceIdentifier: "udid"))
    }
  }

  func testDeploymentFlowConfirmsInstallAndReportsPartialLaunchFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AgentTest-\(UUID().uuidString).app")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    try PropertyListSerialization.data(
      fromPropertyList: ["CFBundleIdentifier": "com.example.agent"],
      format: .xml, options: 0
    ).write(to: directory.appendingPathComponent("Info.plist"))
    var calls: [[String]] = []
    let run: ([String], TimeInterval) throws -> Data = { arguments, _ in
      calls.append(arguments)
      if arguments.contains("lockState") {
        return Data(#"{"result":{"passcodeRequired":false,"unlockedSinceBoot":true}}"#.utf8)
      }
      if arguments.contains("install") {
        return Data(#"{"result":{"installedApplication":{"bundleID":"com.example.agent"}}}"#.utf8)
      }
      throw DeviceDeploymentError.commandFailed(arguments: arguments, status: 1)
    }
    do {
      _ = try DeviceDeployer(run: run).deploy(
        appURL: directory, deviceIdentifier: "udid", launch: true)
      XCTFail("Launch failure must not report success")
    } catch {
      let failure = AgentCLI.failure(error, operation: "deploy")
      XCTAssertEqual(failure.exitCode, 1)
      let detail = try XCTUnwrap(failure.object["error"] as? [String: Any])
      XCTAssertEqual(detail["code"] as? String, "launch_failed")
      XCTAssertEqual(detail["installed"] as? Bool, true)
      XCTAssertEqual(detail["bundleIdentifier"] as? String, "com.example.agent")
    }
    XCTAssertEqual(calls.count, 3)
    calls.removeAll()
    let result = try DeviceDeployer(run: run).deploy(
      appURL: directory, deviceIdentifier: "udid", launch: false)
    XCTAssertFalse(result.launched)
    XCTAssertEqual(calls.count, 2)
    let wrongResult = DeviceDeployer(run: { args, _ in
      if args.contains("lockState") {
        return Data(#"{"result":{"passcodeRequired":false,"unlockedSinceBoot":true}}"#.utf8)
      }
      return Data(#"{"info":{"bundleID":"com.example.agent"},"result":{}}"#.utf8)
    })
    XCTAssertThrowsError(
      try wrongResult.deploy(appURL: directory, deviceIdentifier: "udid", launch: false))
  }

  func testManagedConfigurationIsPrivateAndLearnedPortsStayBounded() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ManagedTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ManagedDeviceStore(url: directory.appendingPathComponent("device.json"))
    let profile = DeviceProfile(
      bonjourName: "phone", bonjourTXT: ["authTag": "test-secret"],
      provider: "tailscale", peerIP: "100.64.0.2", remotePort: 49152,
      localPortRange: [55000, 58000])
    let device = ConfiguredDevice(
      deviceIdentifier: "udid", displayName: "Phone", peerName: "phone.test", profile: profile)
    try store.save(device)
    XCTAssertEqual(try store.load(), device)
    try store.toggleEnabled()
    try store.learn(port: 60549, for: device)
    XCTAssertFalse(try XCTUnwrap(store.load()).enabled)
    let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    for port: UInt16 in [1024, 60549, 65535] {
      let learned = profile.learningTunnelPort(port)
      try learned.validate()
      XCTAssertTrue((learned.tunnelPortRange[0]...learned.tunnelPortRange[1]).contains(port))
      var updated = device
      updated.profile = learned
      XCTAssertTrue(device.hasSameConnection(as: updated))
    }
  }

  func testAgentWaitIsBoundedAndStructuredErrorsAreActionable() throws {
    var count = 0
    XCTAssertThrowsError(
      try AgentCLI.waitUntilReady(
        deviceIdentifier: "udid", timeout: 0.01,
        check: { _, _ in
          count += 1
          throw DeviceDeploymentError.deviceLocked
        }))
    XCTAssertEqual(count, 1)
    let result = AgentCLI.failure(DeviceDeploymentError.deviceLocked, operation: "status")
    XCTAssertEqual(result.exitCode, 2)
    XCTAssertEqual((result.object["error"] as? [String: Any])?["code"] as? String, "device_locked")
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: result.object))
  }

  func testRelayLeaseExcludesCompetingOwnersAndReleasesOnStop() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "LeaseTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    var lease: RelayLease? = try RelayLease(port: 49152, directory: directory)
    XCTAssertNotNil(lease)
    XCTAssertThrowsError(try RelayLease(port: 49152, directory: directory))
    lease = nil
    XCTAssertNoThrow(try RelayLease(port: 49152, directory: directory))
  }

  func testDirectDeviceModesRejectConflictingOperations() throws {
    let capture = try CommandLineOptions.parse([
      "--capture-device-profile", "--peer", "iphone", "--bonjour-host", "phone.local",
    ])
    XCTAssertTrue(capture.captureDeviceProfile)
    XCTAssertFalse(capture.directDevice)
    let direct = try CommandLineOptions.parse(["--direct-device", "--peer", "iphone"])
    XCTAssertTrue(direct.directDevice)
    for arguments in [
      ["--capture-device-profile", "--peer", "iphone"],
      ["--direct-device"],
      ["--direct-device", "--peer", "iphone", "--forward-remote"],
      ["--direct-device", "--peer", "iphone", "--discover"],
      ["--direct-device", "--peer", "iphone", "--remote-port", "49152"],
      [
        "--direct-device", "--peer", "iphone", "--capture-device-profile", "--bonjour-host",
        "phone.local",
      ],
    ] {
      XCTAssertThrowsError(try CommandLineOptions.parse(arguments))
    }
  }

  func testDirectDeviceRequiresProfileForSelectedPeerAndCapturedIdentity() throws {
    let peer = SelectedTailscalePeer(
      hostname: "iphone", dnsName: "iphone.test", ipAddress: "100.64.0.1", online: true)
    func profile(ip: String, txt: [String: String]) -> DeviceProfile {
      DeviceProfile(
        bonjourName: "device-service", bonjourTXT: txt, provider: "tailscale", peerIP: ip,
        remotePort: 49152, localPortRange: [55000, 58000])
    }
    XCTAssertThrowsError(
      try DirectDeviceApplication.makeProxy(
        profile: profile(ip: "100.64.0.2", txt: ["authTag": "test"]), peer: peer,
        interfaceName: "en1", localIP: "192.168.1.2", localPort: 49152))
    XCTAssertThrowsError(
      try DirectDeviceApplication.makeProxy(
        profile: profile(ip: "100.64.0.1", txt: [:]), peer: peer,
        interfaceName: "en1", localIP: "192.168.1.2", localPort: 49152))
    XCTAssertNoThrow(
      try DirectDeviceApplication.makeProxy(
        profile: profile(ip: "100.64.0.1", txt: ["authTag": "test"]), peer: peer,
        interfaceName: "en1", localIP: "192.168.1.2", localPort: 49152))
  }

  func testDirectDeviceTunnelRangeIsBoundedAndSurvivesProfileRoundTrip() throws {
    let profile = DeviceProfile(
      bonjourName: "device-service", bonjourTXT: ["authTag": "test"],
      provider: "tailscale", peerIP: "100.64.0.1", remotePort: 49152,
      localPortRange: [55000, 58000], tunnelPortRange: [50000, 50020])
    let decoded = try JSONDecoder().decode(
      DeviceProfile.self, from: JSONEncoder().encode(profile))
    XCTAssertEqual(decoded.tunnelPortRange, [50000, 50020])
    try decoded.validate()
    for range: [UInt16] in [[], [50000], [50020, 50000], [80, 100], [49152, 65535]] {
      let invalid = DeviceProfile(
        bonjourName: profile.bonjourName, bonjourTXT: profile.bonjourTXT,
        provider: profile.provider, peerIP: profile.peerIP, remotePort: profile.remotePort,
        localPortRange: profile.localPortRange, tunnelPortRange: range)
      XCTAssertThrowsError(try invalid.validate())
    }
  }

  func testDeployOptionsRequireAnAppAndExplicitDevice() throws {
    let options = try CommandLineOptions.parse([
      "--deploy-app", "/tmp/Test.app",
      "--device", "device-udid",
      "--launch",
    ])

    XCTAssertEqual(options.deployAppURL?.path, "/tmp/Test.app")
    XCTAssertEqual(options.deviceIdentifier, "device-udid")
    XCTAssertTrue(options.launchAfterInstall)
    XCTAssertThrowsError(try CommandLineOptions.parse(["--launch"]))
    XCTAssertThrowsError(try CommandLineOptions.parse(["--deploy-app", "/tmp/Test.app"]))
  }

  func testDeviceDeploymentReadsBundleIdentifierAndConfirmsResult() throws {
    let appURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("DebagrTests-\(UUID().uuidString).app")
    try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: appURL) }

    let plist = try PropertyListSerialization.data(
      fromPropertyList: ["CFBundleIdentifier": "com.example.test"],
      format: .xml,
      options: 0
    )
    try plist.write(to: appURL.appendingPathComponent("Info.plist"))

    XCTAssertEqual(try DeviceDeployer.bundleIdentifier(at: appURL), "com.example.test")
    XCTAssertTrue(
      DeviceDeployer.contains(
        "com.example.test",
        in: ["result": ["installedApplication": ["bundleID": "com.example.test"]]]
      ))
    XCTAssertFalse(
      DeviceDeployer.contains("com.example.other", in: ["result": ["bundleID": "com.example.test"]])
    )
  }

  func testBonjourZoneParserNormalizesSRVAndTXT() {
    var parser = BonjourZoneParser()
    parser.consume("_remotepairing._tcp.local. 120 IN PTR My\\032iPhone._remotepairing._tcp.local.")
    parser.consume(
      "My\\032iPhone._remotepairing._tcp.local. 120 IN SRV 0 0 49640 remote-mac.local.")
    parser.consume(
      "My\\032iPhone._remotepairing._tcp.local. 120 IN TXT \"pairing_tag=secret\" \"flags=1\"")

    XCTAssertEqual(
      parser.device,
      BonjourDevice(
        instanceName: "My iPhone",
        serviceType: "_remotepairing._tcp",
        hostName: "remote-mac.local",
        port: 49_640,
        txt: ["pairing_tag": "secret", "flags": "1"]
      )
    )
  }

  func testBonjourZoneParserKeepsFirstServiceOnly() {
    var parser = BonjourZoneParser()
    parser.consume("_remotepairing._tcp.local. PTR First._remotepairing._tcp.local.")
    parser.consume("First._remotepairing._tcp.local. SRV 0 0 49640 first.local.")
    parser.consume("_remotepairing._tcp.local. PTR Second._remotepairing._tcp.local.")
    parser.consume("Second._remotepairing._tcp.local. SRV 0 0 49641 second.local.")

    XCTAssertEqual(parser.device?.instanceName, "First")
    XCTAssertEqual(parser.device?.port, 49_640)
    XCTAssertEqual(parser.device?.hostName, "first.local")
  }

  func testBonjourZoneParserReturnsEveryCompleteService() {
    var parser = BonjourZoneParser()
    parser.consume("_remotepairing._tcp.local. PTR iPhone._remotepairing._tcp.local.")
    parser.consume("iPhone._remotepairing._tcp.local. SRV 0 0 49152 iphone.local.")
    parser.consume("iPhone._remotepairing._tcp.local. TXT \"kind=iPhone\"")
    parser.consume("_remotepairing._tcp.local. PTR iPad._remotepairing._tcp.local.")
    parser.consume("iPad._remotepairing._tcp.local. SRV 0 0 49153 ipad.local.")
    parser.consume("iPad._remotepairing._tcp.local. TXT \"kind=iPad\"")

    XCTAssertEqual(parser.devices.map(\.instanceName), ["iPad", "iPhone"])
    XCTAssertEqual(parser.devices.map(\.port), [49_153, 49_152])
    XCTAssertEqual(parser.devices[0].txt["kind"], "iPad")
    XCTAssertEqual(parser.devices[1].txt["kind"], "iPhone")
  }

  func testBonjourDeviceUsesHumanHostNameForDisplay() {
    let device = BonjourDevice(
      instanceName: "D352A1EA-2CA2-4CBE-84C9-84874F6B4645",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "Radeks-iPhone-16-Pro.local.",
      port: 49_152,
      txt: [:]
    )

    XCTAssertEqual(device.suggestedDisplayName, "Radeks iPhone 16 Pro")
    XCTAssertEqual(TargetDeviceKind.inferred(from: device), .iPhone)
  }

  func testProvisionalIdentityPrefersBonjourIdentifierMetadata() {
    let device = BonjourDevice(
      instanceName: "service-instance",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "iPad.local",
      port: 49_153,
      txt: ["identifier": "stable-service-id"]
    )

    XCTAssertEqual(
      TargetDeviceIdentity.provisional(
        pairedMacNodeID: "tailnet-mac",
        service: device
      ).value,
      "bonjour:stable-service-id"
    )
  }

  func testBonjourZoneParserAcceptsDnsSDInstanceNamesWithoutLocalSuffix() {
    var parser = BonjourZoneParser()
    parser.consume("_remotepairing._tcp PTR iPhone._remotepairing._tcp")
    parser.consume("iPhone._remotepairing._tcp SRV 0 0 49152 iPhone.local.")
    parser.consume("iPhone._remotepairing._tcp TXT \"flags=0\"")

    XCTAssertEqual(
      parser.device,
      BonjourDevice(
        instanceName: "iPhone",
        serviceType: "_remotepairing._tcp",
        hostName: "iPhone.local",
        port: 49_152,
        txt: ["flags": "0"]
      )
    )
  }

  func testBonjourZoneParserCanSelectPreferredHost() {
    var parser = BonjourZoneParser(preferredHostName: "Radek-iPhone.local")
    parser.consume("_remotepairing._tcp PTR Jane._remotepairing._tcp")
    parser.consume("Jane._remotepairing._tcp SRV 0 0 49152 Jane-iPhone.local.")
    parser.consume("_remotepairing._tcp PTR Radek._remotepairing._tcp")
    parser.consume("Radek._remotepairing._tcp SRV 0 0 49153 Radek-iPhone.local.")

    XCTAssertEqual(parser.device?.instanceName, "Radek")
    XCTAssertEqual(parser.device?.hostName, "Radek-iPhone.local")
    XCTAssertEqual(parser.device?.port, 49_153)
  }

  func testTunnelPortParserAcceptsIPv4AndIPv6Endpoints() {
    XCTAssertEqual(
      TunnelPortParser.port(in: "Got tunnel endpoint: '192.168.1.140%en1:60546'"),
      60_546
    )
    XCTAssertEqual(
      TunnelPortParser.port(in: "remotepairingd: Got tunnel endpoint: '100.64.0.2:49640'"),
      49_640
    )
    XCTAssertEqual(
      TunnelPortParser.port(in: "remotepairingd: Got tunnel endpoint: '[fd7a::2]:49641'"),
      49_641
    )
    XCTAssertEqual(
      TunnelPortParser.port(
        in: "remotepairingd: Got tunnel endpoint: 'fe80::10f8:361c:ce42:fa56%en0.57652'"
      ),
      57_652
    )
    XCTAssertNil(TunnelPortParser.port(in: "remotepairingd: endpoint unavailable"))
  }

  func testProfileUsesRequestedShapeAndValidatesTailscaleIP() throws {
    let profile = DeviceProfile(
      bonjourName: "Remote iPhone",
      bonjourTXT: ["identifier": "phone-id", "flags": "0"],
      provider: "tailscale",
      peerIP: "100.64.0.2",
      remotePort: 49_640,
      localPortRange: [55_000, 58_000]
    )

    let data = try JSONEncoder().encode(profile)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertTrue(json.contains("\"bonjourName\""))
    XCTAssertTrue(json.contains("\"localPortRange\""))
    XCTAssertEqual(
      try JSONDecoder().decode(DeviceProfile.self, from: data).bonjourTXT, profile.bonjourTXT)
    try profile.validate()
    XCTAssertTrue(NetworkSupport.isAllowedTailscaleIPv4("100.127.255.255"))
    XCTAssertFalse(NetworkSupport.isAllowedTailscaleIPv4("192.168.1.2"))
  }

  func testTargetDeviceRegistryKeepsMultipleDevicesIndependent() {
    let phoneService = BonjourDevice(
      instanceName: "iPhone",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "iphone.local",
      port: 49_152,
      txt: [:]
    )
    let tabletService = BonjourDevice(
      instanceName: "iPad",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "ipad.local",
      port: 49_153,
      txt: [:]
    )
    let phoneID = TargetDeviceIdentity.apple(
      pairedMacNodeID: "tailnet-mac",
      identifier: "phone-udid"
    )
    let tabletID = TargetDeviceIdentity.apple(
      pairedMacNodeID: "tailnet-mac",
      identifier: "tablet-udid"
    )

    var registry = TargetDeviceRegistry()
    registry.upsert(
      identity: phoneID,
      displayName: "Phone",
      kind: .iPhone,
      service: phoneService
    )
    registry.upsert(
      identity: tabletID,
      displayName: "Tablet",
      kind: .iPad,
      service: tabletService
    )

    XCTAssertEqual(registry.devices.count, 2)
    XCTAssertEqual(registry.orderedDevices.map(\.kind), [.iPhone, .iPad])
    XCTAssertEqual(registry.device(for: phoneID)?.service?.port, 49_152)

    registry.remove(phoneID)

    XCTAssertNil(registry.device(for: phoneID))
    XCTAssertEqual(registry.device(for: tabletID)?.kind, .iPad)
  }

  func testTargetDeviceKindInfersPhoneAndPadWithoutRequiringMetadata() {
    let phone = BonjourDevice(
      instanceName: "Office iPhone",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "phone.local",
      port: 49_152,
      txt: [:]
    )
    let tablet = BonjourDevice(
      instanceName: "Office tablet",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "tablet.local",
      port: 49_153,
      txt: ["model": "iPad Pro"]
    )
    let unknown = BonjourDevice(
      instanceName: "Apple device",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "device.local",
      port: 49_154,
      txt: [:]
    )

    XCTAssertEqual(TargetDeviceKind.inferred(from: phone), .iPhone)
    XCTAssertEqual(TargetDeviceKind.inferred(from: tablet), .iPad)
    XCTAssertEqual(TargetDeviceKind.inferred(from: unknown), .unknown)
  }

  func testMenuBarOptionDoesNotRequirePeerOrPortConfiguration() throws {
    let options = try CommandLineOptions.parse(["--menu-bar"])

    XCTAssertTrue(options.menuBar)
    XCTAssertNil(options.peerName)
    XCTAssertNil(options.remotePort)
    XCTAssertFalse(options.forwardRemote)
  }

  func testMenuBarStateUsesHonestVisibilityLanguage() {
    let device = TargetDevice(
      identity: .apple(pairedMacNodeID: "mac", identifier: "phone"),
      displayName: "Test iPhone",
      kind: .iPhone,
      service: nil
    )

    XCTAssertEqual(MenuBarViewState.discovering.statusTitle, "Looking for Target Devices…")
    XCTAssertEqual(MenuBarViewState.empty.statusTitle, "No Target Devices found")
    XCTAssertEqual(MenuBarViewState.loaded([device]).statusTitle, "1 Target Device found")
    XCTAssertEqual(
      MenuBarViewState.loaded([device, device]).accessibilityLabel,
      "Debagr. 2 Target Devices found"
    )
    XCTAssertEqual(
      MenuBarViewState.failed("Local network access denied").accessibilityLabel,
      "Debagr. Device discovery unavailable. Local network access denied"
    )
  }

  func testDiagnosticsExcludeBonjourTXTValues() {
    let service = BonjourDevice(
      instanceName: "Test iPhone",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "iphone.local",
      port: 49_152,
      txt: ["pairing_tag": "secret"]
    )
    let device = TargetDevice(
      identity: .provisional(pairedMacNodeID: "mac", service: service),
      displayName: "Test iPhone",
      kind: .iPhone,
      service: service
    )

    let report = ProductSupport.diagnostics(devices: [device])

    XCTAssertTrue(report.contains("Test iPhone"))
    XCTAssertTrue(report.contains("iphone.local:49152"))
    XCTAssertFalse(report.contains("secret"))
    XCTAssertFalse(report.contains("pairing_tag"))
  }

  func testCoreDeviceInventoryKeepsOnlyPhysicalIPhoneAndIPad() throws {
    let json = """
      {
        "result": {
          "devices": [
            {
              "properties": {
                "hardware": {
                  "deviceType": "iPhone",
                  "marketingName": "iPhone 16 Pro",
                  "reality": "physical",
                  "udid": "phone-udid"
                },
                "connection": { "state": "disconnected" }
              },
              "deviceProperties": { "name": "Test iPhone" }
            },
            {
              "properties": {
                "hardware": {
                  "deviceType": "iPad",
                  "marketingName": "iPad Pro",
                  "reality": "physical",
                  "udid": "tablet-udid"
                },
                "connection": { "state": "unavailable" }
              },
              "deviceProperties": { "name": "Test iPad" }
            },
            {
              "properties": {
                "hardware": {
                  "deviceType": "appleWatch",
                  "reality": "physical",
                  "udid": "watch-udid"
                }
              }
            },
            {
              "properties": {
                "hardware": {
                  "deviceType": "iPhone",
                  "reality": "simulated",
                  "udid": "simulator-udid"
                }
              }
            }
          ]
        }
      }
      """

    let devices = try CoreDeviceInventory.decodeDevices(
      from: try XCTUnwrap(json.data(using: .utf8)),
      pairedMacNodeID: "local-mac"
    )

    XCTAssertEqual(devices.map(\.displayName), ["Test iPhone", "Test iPad"])
    XCTAssertEqual(devices.map(\.kind), [.iPhone, .iPad])
    XCTAssertEqual(devices.map(\.status), [.paired, .unavailable])
  }

  func testRegistryMergesCoreDeviceWithMatchingBonjourService() {
    let service = BonjourDevice(
      instanceName: "RemotePairing",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "iphone.local",
      port: 49_152,
      txt: ["identifier": "phone-udid"]
    )
    var registry = TargetDeviceRegistry()
    registry.merge(
      TargetDevice(
        identity: .apple(pairedMacNodeID: "mac", identifier: "phone-udid"),
        displayName: "Test iPhone",
        kind: .iPhone,
        service: nil,
        status: .paired
      )
    )
    registry.merge(
      TargetDevice(
        identity: .provisional(pairedMacNodeID: "mac", service: service),
        displayName: service.suggestedDisplayName,
        kind: .iPhone,
        service: service,
        status: .visible
      )
    )

    XCTAssertEqual(registry.devices.count, 1)
    XCTAssertEqual(registry.orderedDevices[0].identity.source, .appleIdentifier)
    XCTAssertEqual(registry.orderedDevices[0].displayName, "Test iPhone")
    XCTAssertEqual(registry.orderedDevices[0].status, .visible)
    XCTAssertEqual(registry.orderedDevices[0].service?.port, 49_152)
  }

  func testRegistryMergesUniqueFriendlyNameWhenBonjourIdentifierDiffers() {
    let service = BonjourDevice(
      instanceName: "bonjour-id",
      serviceType: BonjourZoneParser.serviceType,
      hostName: "Jane--iPhone.local",
      port: 49_152,
      txt: [:]
    )
    var registry = TargetDeviceRegistry()
    registry.merge(
      TargetDevice(
        identity: .apple(pairedMacNodeID: "mac", identifier: "apple-udid"),
        displayName: "Jane - iPhone",
        kind: .iPhone,
        service: nil,
        status: .paired
      )
    )
    registry.merge(
      TargetDevice(
        identity: .provisional(pairedMacNodeID: "mac", service: service),
        displayName: service.suggestedDisplayName,
        kind: .iPhone,
        service: service,
        status: .visible
      )
    )

    XCTAssertEqual(registry.devices.count, 1)
    XCTAssertEqual(registry.orderedDevices[0].identity.value, "apple-udid")
    XCTAssertEqual(registry.orderedDevices[0].service?.hostName, "Jane--iPhone.local")
  }

  func testBonjourProxyArgumentsAreAnArgumentArray() {
    let arguments = BonjourProxy.makeArguments(
      interfaceName: "en0",
      instanceName: "Remote iPhone",
      serviceType: "_remotepairing._tcp",
      domain: "local",
      localPort: 55_000,
      localHost: "mac.local.",
      localIP: "192.168.1.10",
      txt: ["flags": "1"]
    )

    XCTAssertEqual(
      arguments.prefix(9),
      [
        "-i", "en0", "-P", "Remote iPhone", "_remotepairing._tcp",
        "local", "55000", "mac.local.", "192.168.1.10",
      ])
    XCTAssertEqual(arguments.last, "flags=1")
    let allInterfaces = BonjourProxy.makeArguments(
      interfaceName: "0", instanceName: "Remote iPhone",
      serviceType: "_remotepairing._tcp", domain: "local", localPort: 55_000,
      localHost: "mac.local.", localIP: "192.168.1.10", txt: [:])
    XCTAssertEqual(allInterfaces.first, "-P")
    XCTAssertFalse(allInterfaces.contains("-i"))
  }
}
