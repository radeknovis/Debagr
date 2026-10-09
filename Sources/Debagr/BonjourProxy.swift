import Darwin
import Foundation

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
  private let executablePath = "/usr/bin/dns-sd"
  private let interfaceName: String
  private let instanceName: String
  private let serviceType: String
  private let domain: String
  private let localPort: UInt16
  private let localHost: String
  private let localIP: String
  private let txt: [String: String]
  private let processQueue = DispatchQueue(label: "debagr.bonjour-proxy")

  private var process: Process?

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

  static func makeArguments(
    interfaceName: String,
    instanceName: String,
    serviceType: String,
    domain: String,
    localPort: UInt16,
    localHost: String,
    localIP: String,
    txt: [String: String]
  ) -> [String] {
    // dns-sd rejects `-i 0`; omitting -i selects all interfaces.
    var arguments = interfaceName == "0" ? [] : ["-i", interfaceName]
    arguments += [
      "-P",
      instanceName,
      serviceType,
      domain,
      String(localPort),
      localHost,
      localIP,
    ]

    for key in txt.keys.sorted() {
      let value = txt[key] ?? ""
      arguments.append(value.isEmpty ? key : "\(key)=\(value)")
    }
    return arguments
  }

  func start() throws {
    guard process == nil else { return }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = Self.makeArguments(
      interfaceName: interfaceName,
      instanceName: instanceName,
      serviceType: serviceType,
      domain: domain,
      localPort: localPort,
      localHost: localHost,
      localIP: localIP,
      txt: txt
    )
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { [weak self] _ in
      self?.processQueue.async { [weak self] in
        self?.process = nil
      }
    }

    try process.run()
    self.process = process
  }

  func stop() {
    guard let process else { return }
    self.process = nil

    guard process.isRunning else { return }
    process.terminate()
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.75) {
      if process.isRunning {
        _ = kill(process.processIdentifier, SIGKILL)
      }
    }
  }

  deinit {
    stop()
  }
}
