import XCTest

@testable import Debagr

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

}
