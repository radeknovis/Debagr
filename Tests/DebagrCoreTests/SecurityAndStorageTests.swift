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

  @Test(
    "SystemVPNPeerDiscovery prefers Tailscale machine name over localhost and extracts status, lastSeen, owner, tags, and relay"
  )
  func tailscaleRichPeerMetadataAndSorting() {
    let json = #"""
      {
        "BackendState": "Running",
        "User": {
          "1001": {
            "ID": 1001,
            "LoginName": "radek@example.com",
            "DisplayName": "Radek Novak"
          },
          "1002": {
            "ID": 1002,
            "LoginName": "ci-bot@example.com",
            "DisplayName": ""
          }
        },
        "Peer": {
          "node-linux-active": {
            "ID": "n-linux",
            "HostName": "minipc",
            "DNSName": "minipc.tail680579.ts.net.",
            "OS": "linux",
            "TailscaleIPs": ["100.64.2.10"],
            "Online": true,
            "Active": true,
            "LastSeen": "0001-01-01T00:00:00Z",
            "Tags": ["tag:permanent"],
            "UserID": 1002,
            "Relay": "fra"
          },
          "node-mac": {
            "ID": "n-mac",
            "HostName": "Radek’s MacBook Pro",
            "DNSName": "radeks-macbook-pro.tail680579.ts.net.",
            "OS": "macOS",
            "TailscaleIPs": ["100.64.1.10"],
            "Online": true,
            "Active": false,
            "LastSeen": "2026-11-23T16:20:00.1Z",
            "UserID": 1001,
            "Relay": "prg"
          },
          "node-ipad-older": {
            "ID": "n-ipad",
            "HostName": "localhost",
            "DNSName": "ipad171.tail680579.ts.net.",
            "OS": "iOS",
            "TailscaleIPs": ["100.78.0.10"],
            "Online": false,
            "Active": false,
            "LastSeen": "2026-11-23T15:00:00.123456Z",
            "UserID": 1001,
            "Relay": "nue"
          },
          "node-iphone-newer": {
            "ID": "n-iphone",
            "HostName": "localhost",
            "DNSName": "iphone171.tail680579.ts.net.",
            "OS": "iOS",
            "TailscaleIPs": ["100.118.0.20", "fd7a:115c:a1e0::20"],
            "Online": false,
            "Active": false,
            "LastSeen": "2026-11-23T16:10:00.1Z",
            "UserID": 1001,
            "Relay": "ams"
          },
          "node-no-dns": {
            "ID": "n-host-fallback",
            "HostName": "work-mac-mini",
            "OS": "macOS",
            "TailscaleIPs": ["100.64.3.30"],
            "Online": false,
            "Active": false,
            "LastSeen": "2026-11-20T10:00:00Z"
          }
        }
      }
      """#

    let peers = SystemVPNPeerDiscovery.parseTailscaleStatusJSON(
      Data(json.utf8), provider: .tailscale)
    #expect(peers.count == 5)

    // 1. iOS peers first, sorted by newer LastSeen
    #expect(peers[0].name == "iphone171")
    #expect(peers[0].meaningfulHostName == nil)
    #expect(peers[0].isLikelyIPhone)
    #expect(!peers[0].isLikelyIPad)
    #expect(peers[0].ownerName == "Radek Novak")
    #expect(peers[0].relay == "ams")
    #expect(peers[0].lastSeen != nil)

    #expect(peers[1].name == "ipad171")
    #expect(peers[1].meaningfulHostName == nil)
    #expect(peers[1].isLikelyIPad)
    #expect(!peers[1].isLikelyIPhone)
    #expect(peers[1].relay == "nue")

    // 2. macOS peers next (online before offline), showing meaningful HostName
    #expect(peers[2].name == "radeks-macbook-pro")
    #expect(peers[2].meaningfulHostName == "Radek’s MacBook Pro")
    #expect(peers[2].isLikelyMacOSDevice)

    #expect(peers[3].name == "work-mac-mini")
    #expect(peers[3].meaningfulHostName == nil)
    #expect(peers[3].isLikelyMacOSDevice)

    // 3. Non-Apple peer last; zero Go time.Time ignored, LoginName fallback, tags decoded
    #expect(peers[4].name == "minipc")
    #expect(peers[4].active)
    #expect(peers[4].lastSeen == nil)
    #expect(peers[4].tags == ["tag:permanent"])
    #expect(peers[4].ownerName == "ci-bot@example.com")
    #expect(!peers[4].isLikelyAppleMobileDevice)
    #expect(!peers[4].isLikelyMacOSDevice)
  }
}
