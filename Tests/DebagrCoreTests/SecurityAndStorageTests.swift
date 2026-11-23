import Foundation
import Testing

@testable import DebagrCore

@Suite("Security & Storage")
struct SecurityAndStorageTests {
  @Test("FileSecurity enforces 0700 directory, 0600 files, and symlink refusal")
  func secureDirectoryAndFilePermissions() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("debagr-sec-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let store = FileConfigStore(directoryURL: tempRoot)
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let profile = ManagedDeviceProfile(
      udid: "00008140-001E45990413C01C",
      coreDeviceID: "DFED0FBB-E09B-5FB5-8597-5FC3F02F55EA",
      displayName: "Dev iPhone",
      model: "iPhone 16 Pro",
      platform: .iOS,
      vpn: VPNEndpoint(provider: .tailscale, address: "100.64.12.34", peerName: "dev-iphone"),
      wirelessIdentity: WirelessIdentity(
        bonjourInstanceName: "aa:bb:cc:dd:ee:ff@1234567890abcdef",
        confirmedHardwareUDID: "00008140-001E45990413C01C",
        capturedAt: fixedDate
      ),
      savedAt: fixedDate
    )

    try store.save(DebagrConfig(managedDevice: profile))
    #expect(store.verifyPermissions())

    let dirAttrs = try FileManager.default.attributesOfItem(atPath: tempRoot.path)
    let dirMode = try #require((dirAttrs[.posixPermissions] as? NSNumber)?.intValue)
    #expect((dirMode & 0o777) == 0o700)

    let fileAttrs = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
    let fileMode = try #require((fileAttrs[.posixPermissions] as? NSNumber)?.intValue)
    #expect((fileMode & 0o777) == 0o600)

    let reloaded = try store.load()
    #expect(reloaded.managedDevice == profile)

    // Symlink target must be rejected
    let linkTarget = tempRoot.appendingPathComponent("target.txt")
    try Data("x".utf8).write(to: linkTarget)
    let symlinkURL = tempRoot.appendingPathComponent("bad-link.json")
    try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: linkTarget)
    #expect(throws: DebagrError.self) {
      try FileSecurity.writeSecureFile(Data("{}".utf8), to: symlinkURL)
    }
  }

  @Test("DEBAGR_HOME overrides data directory location")
  func dataDirectoryEnvironmentOverride() {
    let dir = FileSecurity.dataDirectoryURL(environment: ["DEBAGR_HOME": "/tmp/custom-debagr-home"])
    #expect(dir.path == "/tmp/custom-debagr-home")
  }

  @Test("IPValidation allows private VPN ranges and rejects public/loopback/link-local")
  func ipValidationRules() {
    #expect(IPValidation.isPrivateVPNAddress("100.64.0.1"))
    #expect(IPValidation.isPrivateVPNAddress("100.127.255.254"))
    #expect(IPValidation.isPrivateVPNAddress("10.0.0.42"))
    #expect(IPValidation.isPrivateVPNAddress("172.16.5.9"))
    #expect(IPValidation.isPrivateVPNAddress("192.168.1.25"))
    #expect(IPValidation.isPrivateVPNAddress("fd7a:115c:a1e0::1"))

    #expect(!IPValidation.isPrivateVPNAddress("8.8.8.8"))
    #expect(!IPValidation.isPrivateVPNAddress("100.63.255.1"))
    #expect(!IPValidation.isPrivateVPNAddress("100.128.0.1"))
    #expect(!IPValidation.isPrivateVPNAddress("127.0.0.1"))
    #expect(!IPValidation.isPrivateVPNAddress("169.254.1.20"))
    #expect(!IPValidation.isPrivateVPNAddress("0.0.0.0"))
    #expect(!IPValidation.isPrivateVPNAddress("::1"))
    #expect(!IPValidation.isPrivateVPNAddress("fe80::1"))
    #expect(!IPValidation.isPrivateVPNAddress("fe80::1%en0"))
    #expect(!IPValidation.isPrivateVPNAddress("2001:4860:4860::8888"))
    #expect(!IPValidation.isPrivateVPNAddress("not-an-ip"))
  }

  @Test("Redactor masks UDIDs, Bonjour pairing identities, and PEM material")
  func redactionRules() {
    #expect(Redactor.redactUDID("00008140-001E45990413C01C") == "0000...C01C")
    #expect(Redactor.redactIP("100.64.12.34", strict: true) == "100.64.*.*")
    #expect(Redactor.redactIP("100.64.12.34", strict: false) == "100.64.12.34")

    let raw =
      "Proxy active for aa:bb:cc:dd:ee:ff@9988776655443322 with -----BEGIN PRIVATE KEY-----\nSECRET\n-----END PRIVATE KEY-----"
    let sanitized = Redactor.redactFreeformText(raw, knownSensitiveValues: ["secret-token"])
    #expect(!sanitized.contains("aa:bb:cc:dd:ee:ff@9988776655443322"))
    #expect(!sanitized.contains("SECRET"))
    #expect(sanitized.contains("[redacted-wireless-identity]"))
    #expect(sanitized.contains("[redacted-key-material]"))
  }

  @Test(
    "SystemVPNPeerDiscovery decodes Tailscale JSON, drops public IPs, and prioritizes online iOS")
  func tailscalePeerDiscoveryParsing() {
    let json = #"""
      {
        "BackendState": "Running",
        "Peer": {
          "node-mac": {
            "ID": "n1",
            "HostName": "build-mac",
            "DNSName": "build-mac.tail.ts.net.",
            "OS": "macOS",
            "TailscaleIPs": ["100.64.1.10"],
            "Online": true
          },
          "node-public-only": {
            "ID": "n2",
            "HostName": "public-box",
            "OS": "linux",
            "TailscaleIPs": ["8.8.8.8"],
            "Online": true
          },
          "node-iphone": {
            "ID": "n3",
            "HostName": "pocket-iphone",
            "DNSName": "pocket-iphone.tail.ts.net.",
            "OS": "iOS",
            "TailscaleIPs": ["100.64.9.9", "fd7a:115c:a1e0::9"],
            "Online": true
          }
        }
      }
      """#

    let peers = SystemVPNPeerDiscovery.parseTailscaleStatusJSON(
      Data(json.utf8), provider: .tailscale)
    #expect(peers.count == 2)
    #expect(peers[0].name == "pocket-iphone")
    #expect(peers[0].isLikelyAppleMobileDevice)
    #expect(peers[0].preferredPrivateIP == "100.64.9.9")
    #expect(peers[1].name == "build-mac")
  }
}
