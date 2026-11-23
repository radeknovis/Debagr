import DebagrCore
import Foundation

public struct BonjourServiceRecord: Codable, Sendable, Equatable, Identifiable {
  public var id: String { "\(instanceName).\(serviceType).\(domain)" }

  public let instanceName: String
  public let serviceType: String
  public let domain: String
  public let hostTarget: String
  public let port: UInt16
  public let txtRecords: [String: String]

  public init(
    instanceName: String,
    serviceType: String = WirelessIdentity.mobdevServiceType,
    domain: String = WirelessIdentity.defaultDomain,
    hostTarget: String,
    port: UInt16,
    txtRecords: [String: String] = [:]
  ) {
    self.instanceName = instanceName
    self.serviceType = serviceType
    self.domain = domain
    self.hostTarget = hostTarget
    self.port = port
    self.txtRecords = txtRecords
  }
}

public struct ProxyRegistrationSpec: Codable, Sendable, Equatable {
  public let instanceName: String
  public let serviceType: String
  public let domain: String
  public let port: UInt16
  public let proxyHost: String
  public let targetIP: String
  public let txtRecords: [String: String]

  public init(
    instanceName: String,
    serviceType: String = WirelessIdentity.mobdevServiceType,
    domain: String = WirelessIdentity.defaultDomain,
    port: UInt16,
    proxyHost: String,
    targetIP: String,
    txtRecords: [String: String] = [:]
  ) {
    self.instanceName = instanceName
    self.serviceType = serviceType
    self.domain = domain
    self.port = port
    self.proxyHost = proxyHost
    self.targetIP = targetIP
    self.txtRecords = txtRecords
  }
}

public struct ProxyHandle: Sendable, Equatable {
  public let id: UUID
  public let spec: ProxyRegistrationSpec

  public init(id: UUID = UUID(), spec: ProxyRegistrationSpec) {
    self.id = id
    self.spec = spec
  }
}
