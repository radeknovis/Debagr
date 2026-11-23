import Foundation

public enum IPValidation: Sendable {
  public enum AddressKind: Sendable, Equatable {
    case privateVPNv4
    case privateVPNv6
    case invalidOrDisallowed(reason: String)

    public var isValidPrivateVPN: Bool {
      switch self {
      case .privateVPNv4, .privateVPNv6: true
      case .invalidOrDisallowed: false
      }
    }
  }

  public static func classify(_ rawAddress: String) -> AddressKind {
    let trimmed = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .invalidOrDisallowed(reason: "Address is empty.")
    }

    var addr4 = in_addr()
    if trimmed.withCString({ inet_pton(AF_INET, $0, &addr4) }) == 1 {
      let hostOrder = UInt32(bigEndian: addr4.s_addr)
      return classifyIPv4(hostOrder)
    }

    // Reject zone-scoped link-local literals like fe80::1%en0
    if trimmed.contains("%") {
      return .invalidOrDisallowed(
        reason: "Zone-scoped link-local IPv6 addresses are not routable over a private VPN."
      )
    }

    var addr6 = in6_addr()
    if trimmed.withCString({ inet_pton(AF_INET6, $0, &addr6) }) == 1 {
      return classifyIPv6(addr6)
    }

    return .invalidOrDisallowed(
      reason:
        "Expected an IPv4 or IPv6 private VPN literal (e.g., 100.64.x.y, 10.x.y.z, or fd7a::...)."
    )
  }

  public static func isPrivateVPNAddress(_ rawAddress: String) -> Bool {
    classify(rawAddress).isValidPrivateVPN
  }

  private static func classifyIPv4(_ ip: UInt32) -> AddressKind {
    let firstOctet = (ip >> 24) & 0xff
    let secondOctet = (ip >> 16) & 0xff

    // Disallow unspecified 0.0.0.0/8, loopback 127.0.0.0/8, link-local 169.254.0.0/16, multicast/reserved >= 224
    if firstOctet == 0 {
      return .invalidOrDisallowed(reason: "Unspecified IPv4 range 0.0.0.0/8 is not allowed.")
    }
    if firstOctet == 127 {
      return .invalidOrDisallowed(reason: "Loopback IPv4 127.0.0.0/8 is not a remote VPN address.")
    }
    if firstOctet == 169 && secondOctet == 254 {
      return .invalidOrDisallowed(reason: "Link-local IPv4 169.254.0.0/16 is not a VPN address.")
    }
    if firstOctet >= 224 {
      return .invalidOrDisallowed(reason: "Multicast or reserved IPv4 range is not allowed.")
    }

    // RFC 1918: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
    let isRFC1918 =
      firstOctet == 10
      || (firstOctet == 172 && (16...31).contains(secondOctet))
      || (firstOctet == 192 && secondOctet == 168)

    // RFC 6598 CGNAT: 100.64.0.0/10 (Tailscale / Headscale / NetBird)
    let isCGNAT = firstOctet == 100 && (64...127).contains(secondOctet)

    if isRFC1918 || isCGNAT {
      return .privateVPNv4
    }

    return .invalidOrDisallowed(
      reason:
        "Public IPv4 addresses are rejected; Debagr requires a private VPN address (RFC 1918 or 100.64.0.0/10)."
    )
  }

  private static func classifyIPv6(_ addr: in6_addr) -> AddressKind {
    let bytes = withUnsafeBytes(of: addr) { Array($0) }
    guard bytes.count == 16 else {
      return .invalidOrDisallowed(reason: "Malformed IPv6 address.")
    }

    let isAllZero = bytes.allSatisfy { $0 == 0 }
    if isAllZero {
      return .invalidOrDisallowed(reason: "Unspecified :: address is not allowed.")
    }

    let isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
    if isLoopback {
      return .invalidOrDisallowed(reason: "Loopback ::1 is not a remote VPN address.")
    }

    // ULA fc00::/7 (includes fd00::/8 and Tailscale fd7a:115c:a1e0::/48)
    if (bytes[0] & 0xfe) == 0xfc {
      return .privateVPNv6
    }

    return .invalidOrDisallowed(
      reason: "Only private IPv6 ULA addresses (fc00::/7) are permitted for VPN endpoints."
    )
  }
}
