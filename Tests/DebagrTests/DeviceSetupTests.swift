import XCTest

@testable import Debagr

@MainActor
final class DeviceSetupTests: XCTestCase {

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
    model.confirmedSelection = true
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
  func testInvalidManualAddressHasInlineFeedback() {
    let model = DeviceSetupModel(configured: nil)
    model.provider = .wireguard
    model.address = "8.8.8.8"
    XCTAssertNotNil(model.addressValidationMessage)
    model.address = "10.20.0.2"
    XCTAssertNil(model.addressValidationMessage)
  }

  func testChangedDeviceInvalidatesIdentityConfirmation() {
    let model = DeviceSetupModel(configured: nil)
    model.confirmedSelection = true
    model.deviceID = "different"
    XCTAssertFalse(model.confirmedSelection)
  }

  func testCopiedDeployCommandUsesActualPathAndQuotesArguments() {
    let command = ProductSupport.deployCommand(
      deviceIdentifier: "a'b", executablePath: "/tmp/My App/Debagr")
    XCTAssertTrue(command.hasPrefix("'/tmp/My App/Debagr' "))
    XCTAssertTrue(command.contains("'a'\"'\"'b'"))
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

  func testCableGuideCannotSaveWirelessConfiguration() throws {
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

  func testReviewRequiresIdentityConfirmationAndProviderChangeInvalidatesIt() {
    let model = DeviceSetupModel(configured: nil)
    model.updateDevices([device], services: [], status: "One device")
    model.provider = .wireguard
    model.address = peer.ipAddress
    model.loadPeers()
    model.importedProfile = profile
    XCTAssertTrue(model.hasConnectionSelection)
    XCTAssertFalse(model.canSave)
    model.step = .review
    model.save()
    XCTAssertFalse(model.isWorking)
    XCTAssertEqual(model.page, .setup)
    model.confirmedSelection = true
    XCTAssertTrue(model.canSave)
    model.provider = .netbird
    XCTAssertFalse(model.confirmedSelection)
    XCTAssertNil(model.importedProfile)
  }

}
