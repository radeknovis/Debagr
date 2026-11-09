import XCTest

@testable import Debagr

final class DeviceSetupTests: XCTestCase {
  func testInitialPairingRoutesToMacDiagramWithoutStartingVirtualHere() {
    let model = DeviceSetupModel(configured: nil)
    var opened = 0
    model.onInitialPairing = { opened += 1 }
    model.selectPath(.usb)
    XCTAssertEqual(opened, 1)
    XCTAssertEqual(model.path, .existing)
    XCTAssertFalse(model.usb.hasSession)
    model.isWorking = true
    model.selectPath(.usb)
    XCTAssertEqual(opened, 1)
  }

  private let device = TargetDevice(
    identity: .apple(pairedMacNodeID: "mac", identifier: "ipad"),
    displayName: "Test iPad", kind: .iPad, service: nil)
  private let peer = SelectedNetworkPeer(
    hostname: "ipad", dnsName: "", ipAddress: "10.20.0.2", online: false)
  private let profile = DeviceProfile(
    bonjourName: "device", bonjourTXT: ["identity": "test"], provider: "wireguard",
    peerIP: "10.20.0.2", remotePort: 49152, localPortRange: [55000, 58000])

  func testSetupPreservesKindAndRejectsMismatchedImportedProfile() throws {
    let configuration = try DeviceSetupModel.configuration(
      device: device, provider: .wireguard, peer: peer, profile: profile)
    XCTAssertEqual(configuration.kind, .iPad)
    XCTAssertEqual(configuration.peerName, peer.ipAddress)
    XCTAssertThrowsError(
      try DeviceSetupModel.configuration(
        device: device, provider: .netbird, peer: peer, profile: profile))
    let otherPeer = SelectedNetworkPeer(
      hostname: "other", dnsName: "", ipAddress: "10.20.0.3", online: false)
    XCTAssertThrowsError(
      try DeviceSetupModel.configuration(
        device: device, provider: .wireguard, peer: otherPeer, profile: profile))
  }

  func testMissingServiceRequiresImportAndChangingPeerClearsImport() {
    let model = DeviceSetupModel(configured: nil)
    model.updateDevices([device], services: [], status: "One device")
    model.provider = .wireguard
    model.peers = [peer]
    model.peerIP = peer.ipAddress
    XCTAssertFalse(model.canSave)
    model.importedProfile = profile
    XCTAssertTrue(model.canSave)
    model.peerIP = "10.20.0.3"
    XCTAssertNil(model.importedProfile)
    XCTAssertFalse(model.canSave)
  }

  func testInvalidAddressStaysEditableWithoutStartingDiscovery() {
    let model = DeviceSetupModel(configured: nil)
    model.provider = .wireguard
    model.address = "8.8.8.8"
    model.loadPeers()
    XCTAssertEqual(model.page, .setup)
    XCTAssertFalse(model.isWorking)
    XCTAssertNil(model.error)
    XCTAssertEqual(model.address, "8.8.8.8")
  }

  func testDiscoveryPreservesExplicitDeviceSelectionAcrossReordering() {
    let other = TargetDevice(
      identity: .apple(pairedMacNodeID: "mac", identifier: "other"),
      displayName: "Other device", kind: .iPhone, service: nil)
    let model = DeviceSetupModel(configured: nil)
    model.updateDevices([device, other], services: [], status: "Two devices")
    XCTAssertTrue(model.deviceID.isEmpty)
    model.deviceID = "ipad"
    model.updateDevices([other, device], services: [], status: "Two devices")
    XCTAssertEqual(model.deviceID, "ipad")
  }

  func testManualAddressUpdatesVPNSelectionWithoutAnotherStep() {
    let model = DeviceSetupModel(configured: nil)
    model.provider = .wireguard
    model.address = "10.20.0.2"
    model.loadPeers()
    XCTAssertEqual(model.page, .setup)
    XCTAssertEqual(model.peers.map(\.ipAddress), ["10.20.0.2"])
    XCTAssertEqual(model.peerIP, "10.20.0.2")
    XCTAssertFalse(model.isLoadingPeers)
    model.address = "8.8.8.8"
    model.updateManualPeer()
    XCTAssertTrue(model.peers.isEmpty)
    XCTAssertTrue(model.peerIP.isEmpty)
    XCTAssertFalse(model.canSave)
  }
  func testDeploymentPromptUsesStableTargetAndSeparateConfirmation() {
    let model = DeviceSetupModel(configured: nil)
    XCTAssertTrue(model.deploymentPrompt.contains("my target device"))
    model.deviceID = "test-device-id"
    XCTAssertTrue(model.deploymentPrompt.contains("device test-device-id"))
    XCTAssertTrue(model.deploymentPrompt.contains("/absolute/path/MyApp.app"))
    XCTAssertTrue(model.deploymentPrompt.contains("Confirm installation and launch separately"))
  }

  func testGuidedSetupRequiresDeviceThenCompleteConnection() {
    let model = DeviceSetupModel(configured: nil)
    model.advance()
    XCTAssertEqual(model.step, .device)
    model.updateDevices([device], services: [], status: "One device")
    model.advance()
    XCTAssertEqual(model.step, .network)
    model.advance()
    XCTAssertEqual(model.step, .network)
    model.provider = .wireguard
    model.address = peer.ipAddress
    model.loadPeers()
    model.importedProfile = profile
    model.advance()
    XCTAssertEqual(model.step, .review)
    model.updateDevices([], services: [], status: "Device removed")
    XCTAssertFalse(model.canContinue)
    XCTAssertFalse(model.canSave)
  }

  func testUSBPathCannotBypassItsOwnPairingWorkflow() throws {
    let configured = try DeviceSetupModel.configuration(
      device: device, provider: .wireguard, peer: peer, profile: profile)
    let model = DeviceSetupModel(configured: configured)
    model.updateDevices([device], services: [], status: "One device")
    model.loadPeers()
    XCTAssertTrue(model.canSave)
    model.path = .usb
    model.advance()
    model.save()
    XCTAssertEqual(model.step, .device)
    XCTAssertEqual(model.page, .setup)
    XCTAssertFalse(model.isWorking)
    XCTAssertFalse(model.canSave)
    XCTAssertFalse(model.canContinue)
  }

  func testReopeningSavedConnectionDoesNotRequireNearbyRecapture() throws {
    let configured = try DeviceSetupModel.configuration(
      device: device, provider: .wireguard, peer: peer, profile: profile)
    let model = DeviceSetupModel(configured: configured)
    model.updateDevices([device], services: [], status: "One device")
    model.loadPeers()
    XCTAssertEqual(model.importedProfile, profile)
    XCTAssertTrue(model.canSave)
    model.deviceID = "another-device"
    XCTAssertNil(model.importedProfile)
    model.importedProfile = profile
    model.provider = .netbird
    XCTAssertNil(model.importedProfile)
  }

  func testVerificationRequiresMatchingSavedConnectionAndReportsRecovery() throws {
    var configured = try DeviceSetupModel.configuration(
      device: device, provider: .wireguard, peer: peer, profile: profile)
    let model = DeviceSetupModel(configured: configured)
    model.page = .saved
    var otherConnection = configured
    otherConnection.interfaceName = "another-interface"
    model.updateVerification(device: otherConnection, result: .success("Ready"))
    XCTAssertEqual(model.verification, .checking)
    model.updateVerification(device: configured, result: .success("Ready via Apple connection"))
    XCTAssertEqual(model.verification, .ready("Ready via Apple connection"))
    model.updateVerification(
      device: configured, result: .failure(ManagedDeviceError.relayAlreadyRunning))
    guard case .attention(let recovery) = model.verification else {
      return XCTFail("Connection errors must give a recovery state")
    }
    XCTAssertFalse(recovery.isEmpty)
    configured.enabled = false
    model.updateVerification(device: configured, result: .success("Disconnected"))
    guard case .attention = model.verification else {
      return XCTFail("A disabled connection must never appear ready")
    }
  }

}
