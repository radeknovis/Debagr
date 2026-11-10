import Darwin
import Foundation
import dnssd

enum BonjourProxyError: LocalizedError {
  case invalidPort(UInt16)
  case invalidValue(String)

  var errorDescription: String? {
    switch self {
    case .invalidPort(let port):
      return "Invalid Bonjour proxy port: \(port)."
    case .invalidValue(let value):
      return "Invalid Bonjour proxy value: \(value)."
    }
  }
}

final class BonjourProxy {
  private let interfaceName: String
  private let instanceName: String
  private let serviceType: String
  private let domain: String
  private let localPort: UInt16
  private let localHost: String
  private let localIP: String
  private let txt: [String: String]
  private let processQueue = DispatchQueue(label: "debagr.bonjour-proxy")

  private let healthy = LockedValue(false)
  var isHealthy: Bool { healthy.get() }
  private var service: DNSServiceRef?
  private var hostRecord: DNSServiceRef?

  init(
    interfaceName: String,
    instanceName: String,
    serviceType: String = BonjourZoneParser.serviceType,
    domain: String = BonjourZoneParser.domain,
    localPort: UInt16,
    localHost: String,
    localIP: String,
    txt: [String: String] = [:]
  ) throws {
    guard localPort > 0 else { throw BonjourProxyError.invalidPort(localPort) }
    guard !instanceName.isEmpty,
      instanceName.rangeOfCharacter(from: .controlCharacters) == nil
    else {
      throw BonjourProxyError.invalidValue("instance name")
    }
    guard !localHost.isEmpty, NetworkSupport.isValidIPv4(localIP) else {
      throw BonjourProxyError.invalidValue("local endpoint")
    }

    self.interfaceName = interfaceName
    self.instanceName = instanceName
    self.serviceType = serviceType
    self.domain = domain
    self.localPort = localPort
    self.localHost = localHost
    self.localIP = localIP
    self.txt = txt
  }

  func start() throws {
    try processQueue.sync {
      guard service == nil else { return }
      let index = interfaceName == "0" ? 0 : if_nametoindex(interfaceName)
      guard interfaceName == "0" || index != 0 else {
        throw BonjourProxyError.invalidValue("interface")
      }
      var bytes = Data()
      for key in txt.keys.sorted() {
        let value = txt[key] ?? ""
        let entry = Data((value.isEmpty ? key : "\(key)=\(value)").utf8)
        guard entry.count <= 255 else { throw BonjourProxyError.invalidValue("TXT record") }
        bytes.append(UInt8(entry.count))
        bytes.append(entry)
      }
      guard bytes.count <= Int(UInt16.max) else {
        throw BonjourProxyError.invalidValue("TXT record length")
      }
      let context = Unmanaged.passUnretained(self).toOpaque()
      do {
        var connection: DNSServiceRef?
        try check(DNSServiceCreateConnection(&connection))
        hostRecord = connection
        guard let connection else { throw BonjourProxyError.invalidValue("DNS connection") }
        var address = in_addr()
        guard inet_pton(AF_INET, localIP, &address) == 1 else {
          throw BonjourProxyError.invalidValue("IPv4 address")
        }
        var record: DNSRecordRef?
        try check(
          DNSServiceRegisterRecord(
            connection, &record, DNSServiceFlags(kDNSServiceFlagsUnique),
            index, localHost, 1, 1, 4, &address, 120,
            { _, _, _, error, context in
              guard error != 0, let context else { return }
              Unmanaged<BonjourProxy>.fromOpaque(context).takeUnretainedValue().healthy.set(false)
            }, context))
        try check(DNSServiceSetDispatchQueue(connection, processQueue))
        var registration: DNSServiceRef?
        let result = bytes.withUnsafeBytes { buffer in
          DNSServiceRegister(
            &registration, 0, index, instanceName, serviceType, domain,
            localHost, localPort.bigEndian, UInt16(bytes.count), buffer.baseAddress,
            { _, _, error, _, _, _, context in
              guard error != 0, let context else { return }
              Unmanaged<BonjourProxy>.fromOpaque(context).takeUnretainedValue().healthy.set(false)
            }, context)
        }
        try check(result)
        service = registration
        guard let registration else { throw BonjourProxyError.invalidValue("DNS registration") }
        try check(DNSServiceSetDispatchQueue(registration, processQueue))
        healthy.set(true)
      } catch {
        stopOnQueue()
        throw error
      }
    }
  }

  private func check(_ status: DNSServiceErrorType) throws {
    guard status == kDNSServiceErr_NoError else {
      throw BonjourProxyError.invalidValue("DNS-SD registration failed (\(status))")
    }
  }

  private func stopOnQueue() {
    healthy.set(false)
    if let service { DNSServiceRefDeallocate(service) }
    if let hostRecord { DNSServiceRefDeallocate(hostRecord) }
    service = nil
    hostRecord = nil
  }

  func stop() { processQueue.sync { stopOnQueue() } }

  deinit {
    stop()
  }
}
