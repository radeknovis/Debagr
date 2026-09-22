import Foundation

enum BonjourHostResolverError: LocalizedError {
  case invalidHost(String)
  case timedOut(String)
  case noIPv4Address(String)

  var errorDescription: String? {
    switch self {
    case .invalidHost(let host):
      return "Bonjour host is not an allowed local name: \(host)."
    case .timedOut(let host):
      return "Timed out resolving Bonjour host \(host)."
    case .noIPv4Address(let host):
      return "No allowed local IPv4 address was resolved for Bonjour host \(host)."
    }
  }
}

final class BonjourHostResolver {
  func resolveIPv4(hostName: String, timeout: TimeInterval) throws -> String {
    let normalizedHost =
      hostName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))

    guard NetworkSupport.isAllowedBonjourDestinationHost(normalizedHost),
      normalizedHost.lowercased().hasSuffix(".local")
    else {
      throw BonjourHostResolverError.invalidHost(hostName)
    }

    let semaphore = DispatchSemaphore(value: 0)
    let result = LockedValue<String?>(nil)
    let process = OwnedLineProcess(
      executablePath: "/usr/bin/dns-sd",
      arguments: ["-G", "v4", normalizedHost],
      label: "debagr.bonjour-host-resolver"
    ) { line in
      let address = BonjourZoneParser.tokenize(line).first(where: {
        NetworkSupport.isValidIPv4($0) && NetworkSupport.isAllowedLocalIPv4($0)
      })
      guard let address else { return }
      result.set(address)
      semaphore.signal()
    }

    try process.start()
    guard semaphore.wait(timeout: .now() + timeout) == .success else {
      process.stop()
      throw BonjourHostResolverError.timedOut(normalizedHost)
    }

    process.stop()
    guard let address = result.get() else {
      throw BonjourHostResolverError.noIPv4Address(normalizedHost)
    }
    return address
  }
}
