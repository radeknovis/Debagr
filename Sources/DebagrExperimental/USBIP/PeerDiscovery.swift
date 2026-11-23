import DebagrCore
import Foundation
import Network

public struct DiscoveredUSBIPPeer: Codable, Sendable, Equatable, Identifiable {
  public var id: String { "\(name)-\(host):\(port)" }
  public let name: String
  public let host: String
  public let port: UInt16
  public let source: String

  public init(name: String, host: String, port: UInt16, source: String) {
    self.name = name
    self.host = host
    self.port = port
    self.source = source
  }
}

public protocol OnDemandUSBIPPeerDiscovering: Sendable {
  func discoverLocalPeers(timeoutSeconds: TimeInterval) async -> [DiscoveredUSBIPPeer]
  func validateManualPeer(address: String, port: UInt16) throws -> DiscoveredUSBIPPeer
}

public final class SystemUSBIPPeerDiscovery: OnDemandUSBIPPeerDiscovering, Sendable {
  public static let bonjourServiceType = "_debagr-usbip._tcp"

  public init() {}

  public func discoverLocalPeers(timeoutSeconds: TimeInterval = 2.5) async -> [DiscoveredUSBIPPeer]
  {
    await withCheckedContinuation { continuation in
      let browser = NWBrowser(
        for: .bonjour(type: Self.bonjourServiceType, domain: nil), using: .tcp)
      let queue = DispatchQueue(label: "dev.debagr.usbip.browse")
      let box = DiscoveredPeersBox()

      browser.browseResultsChangedHandler = { results, _ in
        var found: [DiscoveredUSBIPPeer] = []
        for result in results {
          if case .service(let name, _, _, _) = result.endpoint {
            found.append(
              DiscoveredUSBIPPeer(
                name: name,
                host: "\(name).local",
                port: 3240,
                source: "bonjour-on-demand"
              )
            )
          }
        }
        box.replace(found)
      }

      browser.start(queue: queue)
      queue.asyncAfter(deadline: .now() + max(0.3, min(6.0, timeoutSeconds))) {
        browser.cancel()
        continuation.resume(returning: box.snapshot())
      }
    }
  }

  public func validateManualPeer(address: String, port: UInt16 = 3240) throws
    -> DiscoveredUSBIPPeer
  {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    switch IPValidation.classify(trimmed) {
    case .privateVPNv4, .privateVPNv6:
      return DiscoveredUSBIPPeer(
        name: trimmed,
        host: trimmed,
        port: port,
        source: "manual-private-vpn"
      )
    case .invalidOrDisallowed(let reason):
      throw DebagrError(
        code: .vpnAddressInvalid,
        category: "experimental_usbip",
        message: "Manual peer address rejected: \(reason)",
        recoverable: true
      )
    }
  }
}

private final class DiscoveredPeersBox: @unchecked Sendable {
  private let lock = NSLock()
  private var peers: [DiscoveredUSBIPPeer] = []

  func replace(_ next: [DiscoveredUSBIPPeer]) {
    lock.withLock { peers = next }
  }

  func snapshot() -> [DiscoveredUSBIPPeer] {
    lock.withLock { peers }
  }
}
