import XCTest

@testable import Debagr

final class TailscalePairingTrustTests: XCTestCase {
  func testCodeIsSkippedOnlyForTheSameUsersDirectSocketsInsideTheCurrentMesh() throws {
    let local = "100.64.0.1"
    let remote = "100.64.0.2"
    let air: [String: Any] = [
      "ID": "air", "UserID": 7, "TailscaleIPs": [remote], "DNSName": "air.personal.ts.net.",
      "InNetworkMap": true, "Online": true,
    ]
    var status: [String: Any] = [
      "BackendState": "Running", "CurrentTailnet": ["MagicDNSSuffix": "personal.ts.net"],
      "Self": ["ID": "mini", "UserID": 7, "TailscaleIPs": [local]],
      "Peer": ["air": air],
    ]
    func trusted(_ localAddress: String = "100.64.0.1", _ remoteAddress: String = "100.64.0.2")
      throws -> Bool
    {
      TailscaleClient.isPersonalMeshConnection(
        status: try JSONSerialization.data(withJSONObject: status),
        localAddress: localAddress, remoteAddress: remoteAddress)
    }
    XCTAssertTrue(try trusted(), "A peer owned by the same Tailscale user needs no code")
    XCTAssertFalse(try trusted("192.168.1.2", remote))
    XCTAssertFalse(try trusted(local, "192.168.1.3"))
    XCTAssertFalse(try trusted(local, "100.64.0.99"))
    XCTAssertFalse(try trusted("100.64.0.99", remote))
    XCTAssertFalse(try trusted(local, local))
    status["BackendState"] = "Stopped"
    XCTAssertFalse(try trusted())
    status["BackendState"] = "Running"
    for changes: [String: Any] in [
      ["Online": false], ["InNetworkMap": false], ["DNSName": "air.shared.ts.net."],
      ["DNSName": "air.evilpersonal.ts.net."], ["ID": "mini"], ["TailscaleIPs": ["100.64.0.3"]],
      ["UserID": 8], ["UserID": 0], ["UserID": "7"], ["Tags": ["tag:server"]],
    ] {
      status["Peer"] = ["air": air.merging(changes) { _, new in new }]
      XCTAssertFalse(try trusted(), "Must reject \(changes)")
    }
    status["Peer"] = ["air": air.filter { $0.key != "UserID" }]
    XCTAssertFalse(try trusted(), "A peer without an owner must use the pairing code")
    status["Peer"] = ["air": air]
    for owner: [String: Any] in [
      ["ID": "mini", "TailscaleIPs": [local]],
      ["ID": "mini", "UserID": 8, "TailscaleIPs": [local]],
      ["ID": "mini", "UserID": 7, "TailscaleIPs": [local], "Tags": ["tag:server"]],
    ] {
      status["Self"] = owner
      XCTAssertFalse(try trusted(), "Must reject this Mac as \(owner)")
    }
    // An absent owner is reported as 0 on both sides; equal zeros are not the same user.
    status["Self"] = ["ID": "mini", "UserID": 0, "TailscaleIPs": [local]]
    status["Peer"] = ["air": air.merging(["UserID": 0]) { _, new in new }]
    XCTAssertFalse(try trusted(), "Two devices without an owner must use the pairing code")
    XCTAssertFalse(
      TailscaleClient.isPersonalMeshConnection(
        status: Data("invalid".utf8), localAddress: local, remoteAddress: remote))
  }
}
