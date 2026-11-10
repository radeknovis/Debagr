import XCTest

@testable import Debagr

final class TailscalePairingTrustTests: XCTestCase {
  func testCodeIsSkippedOnlyForActualDirectSocketsInsideTheCurrentMesh() throws {
    let local = "100.64.0.1"
    let remote = "100.64.0.2"
    var status: [String: Any] = [
      "BackendState": "Running", "CurrentTailnet": ["MagicDNSSuffix": "personal.ts.net"],
      "Self": ["ID": "mini", "TailscaleIPs": [local]],
      "Peer": [
        "air": [
          "ID": "air", "TailscaleIPs": [remote], "DNSName": "air.personal.ts.net.",
          "InNetworkMap": true, "Online": true,
        ]
      ],
    ]
    func trusted(_ localAddress: String = "100.64.0.1", _ remoteAddress: String = "100.64.0.2")
      throws -> Bool
    {
      TailscaleClient.isPersonalMeshConnection(
        status: try JSONSerialization.data(withJSONObject: status),
        localAddress: localAddress, remoteAddress: remoteAddress)
    }
    XCTAssertTrue(try trusted())  // Includes tagged personal machines; no user-ID comparison.
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
    ] {
      var peer: [String: Any] = [
        "ID": "air", "TailscaleIPs": [remote],
        "DNSName": "air.personal.ts.net.", "InNetworkMap": true, "Online": true,
      ]
      peer.merge(changes) { _, new in new }
      status["Peer"] = ["air": peer]
      XCTAssertFalse(try trusted(), "Must reject \(changes)")
    }
    XCTAssertFalse(
      TailscaleClient.isPersonalMeshConnection(
        status: Data("invalid".utf8), localAddress: local, remoteAddress: remote))
  }
}
