import Darwin
import Foundation
import Network

struct InterfaceBinding {
  let name: String
  let ipv4Address: String
  let networkInterface: NWInterface
}

enum NetworkSupportError: LocalizedError {
  case noIPv4Address(interface: String)
  case noTailscaleIPv4Address
  case noNetworkInterface(interface: String)
  case interfaceLookupTimedOut(interface: String)
  case invalidIPv4Address(String)

  var errorDescription: String? {
    switch self {
    case .noIPv4Address(let interface):
      return "Interface \(interface) has no usable IPv4 address."
    case .noTailscaleIPv4Address:
      return "No usable Tailscale IPv4 address was found on this Mac."
    case .noNetworkInterface(let interface):
      return "Network.framework could not resolve interface \(interface)."
    case .interfaceLookupTimedOut(let interface):
      return "Timed out while resolving network interface \(interface)."
    case .invalidIPv4Address(let address):
      return "Invalid IPv4 address: \(address)."
    }
  }
}

enum NetworkSupport {
  static func resolveInterface(named name: String) throws -> InterfaceBinding {
    let address = try ipv4Address(for: name)
    let networkInterface = try networkInterface(named: name)
    return InterfaceBinding(name: name, ipv4Address: address, networkInterface: networkInterface)
  }

  static func resolveTailscaleInterface() throws -> InterfaceBinding {
    var firstAddress: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&firstAddress) == 0 else {
      throw NetworkSupportError.noTailscaleIPv4Address
    }
    defer { freeifaddrs(firstAddress) }

    var current = firstAddress
    while let address = current {
      let entry = address.pointee
      current = entry.ifa_next

      guard let namePointer = entry.ifa_name,
        let socketAddress = entry.ifa_addr,
        socketAddress.pointee.sa_family == sa_family_t(AF_INET),
        (entry.ifa_flags & UInt32(IFF_UP)) != 0,
        let interfaceName = String(validatingCString: namePointer),
        let ipv4Address = numericIPv4Address(for: socketAddress),
        isAllowedTailscaleIPv4(ipv4Address)
      else {
        continue
      }

      let networkInterface = try networkInterface(named: interfaceName)
      return InterfaceBinding(
        name: interfaceName,
        ipv4Address: ipv4Address,
        networkInterface: networkInterface
      )
    }

    throw NetworkSupportError.noTailscaleIPv4Address
  }

  static func ipv4Address(for interfaceName: String) throws -> String {
    var firstAddress: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&firstAddress) == 0 else {
      throw NetworkSupportError.noIPv4Address(interface: interfaceName)
    }
    defer { freeifaddrs(firstAddress) }

    var current = firstAddress
    while let address = current {
      let entry = address.pointee
      current = entry.ifa_next

      guard let namePointer = entry.ifa_name,
        String(cString: namePointer) == interfaceName,
        let socketAddress = entry.ifa_addr,
        socketAddress.pointee.sa_family == sa_family_t(AF_INET),
        (entry.ifa_flags & UInt32(IFF_UP)) != 0
      else {
        continue
      }

      if let address = numericIPv4Address(for: socketAddress) {
        return address
      }
    }

    throw NetworkSupportError.noIPv4Address(interface: interfaceName)
  }

  static func isValidIPv4(_ address: String) -> Bool {
    ipv4Value(address) != nil
  }

  /// Tailscale's normal IPv4 allocation is CGNAT space (100.64.0.0/10).
  /// Restricting the relay destination to that range prevents a profile or
  /// future input path from turning this tool into a generic TCP proxy.
  static func isAllowedTailscaleIPv4(_ address: String) -> Bool {
    guard let value = ipv4Value(address) else { return false }
    let lower: UInt32 = (100 << 24) | (64 << 16)
    let upper: UInt32 = (100 << 24) | (127 << 16) | (255 << 8) | 255
    return (lower...upper).contains(value)
  }

  private static func ipv4Value(_ address: String) -> UInt32? {
    let components = address.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count == 4 else { return nil }

    let octets = components.compactMap { UInt32($0) }
    guard octets.count == 4, octets.allSatisfy({ $0 <= 255 }) else { return nil }

    return (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
  }

  private static func numericIPv4Address(
    for socketAddress: UnsafeMutablePointer<sockaddr>
  ) -> String? {
    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let result = getnameinfo(
      socketAddress,
      socklen_t(socketAddress.pointee.sa_len),
      &host,
      socklen_t(host.count),
      nil,
      0,
      NI_NUMERICHOST
    )
    return result == 0 ? String(cString: host) : nil
  }

  private static func networkInterface(named name: String) throws -> NWInterface {
    let monitor = NWPathMonitor()
    let monitorQueue = DispatchQueue(label: "nuticast-poc.interface-monitor")
    let resultLock = NSLock()
    var result: NWInterface?
    let found = DispatchSemaphore(value: 0)

    monitor.pathUpdateHandler = { path in
      resultLock.lock()
      defer { resultLock.unlock() }

      guard result == nil,
        let interface = path.availableInterfaces.first(where: { $0.name == name })
      else {
        return
      }

      result = interface
      found.signal()
    }
    monitor.start(queue: monitorQueue)

    guard found.wait(timeout: .now() + 3) == .success else {
      monitor.cancel()
      throw NetworkSupportError.interfaceLookupTimedOut(interface: name)
    }

    monitor.cancel()

    resultLock.lock()
    let resolved = result
    resultLock.unlock()

    guard let resolved else {
      throw NetworkSupportError.noNetworkInterface(interface: name)
    }
    return resolved
  }
}
