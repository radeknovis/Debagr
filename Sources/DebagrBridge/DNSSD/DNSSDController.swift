import DebagrCore
import Foundation

public protocol DNSSDControlling: Sendable {
  func browseMobdevServices(timeoutSeconds: TimeInterval) async throws -> [BonjourServiceRecord]
  func startProxy(_ spec: ProxyRegistrationSpec) async throws -> ProxyHandle
  func stopProxy(_ handle: ProxyHandle) async
  func stopAllProxies() async
}

public actor SystemDNSSDController: DNSSDControlling {
  private let dnsSDPath: String
  private var activeProcesses: [UUID: Process] = [:]

  public init(dnsSDPath: String = "/usr/bin/dns-sd") {
    self.dnsSDPath = dnsSDPath
  }

  deinit {
    for process in activeProcesses.values where process.isRunning {
      process.terminate()
    }
  }

  public func browseMobdevServices(timeoutSeconds: TimeInterval = 3.0) async throws
    -> [BonjourServiceRecord]
  {
    let browseOutput = try await runTimedDNSSD(
      arguments: ["-B", WirelessIdentity.mobdevServiceType, "local."],
      captureDuration: max(1.0, min(10.0, timeoutSeconds))
    )

    let instances = Self.parseBrowseInstances(from: browseOutput)
    var records: [BonjourServiceRecord] = []
    for instance in instances {
      let lookupOutput = try await runTimedDNSSD(
        arguments: ["-L", instance, WirelessIdentity.mobdevServiceType, "local."],
        captureDuration: 1.5
      )
      if let record = Self.parseLookupOutput(
        instanceName: instance,
        serviceType: WirelessIdentity.mobdevServiceType,
        domain: "local.",
        output: lookupOutput
      ) {
        records.append(record)
      }
    }
    return records
  }

  public func startProxy(_ spec: ProxyRegistrationSpec) async throws -> ProxyHandle {
    guard FileManager.default.isExecutableFile(atPath: dnsSDPath) else {
      throw DebagrError(
        code: .bridgeError,
        category: "bridge",
        message: "System DNS-SD utility not found at \(dnsSDPath).",
        recoverable: false
      )
    }

    var args = [
      "-P",
      spec.instanceName,
      spec.serviceType,
      spec.domain,
      String(spec.port),
      spec.proxyHost,
      spec.targetIP,
    ]
    for key in spec.txtRecords.keys.sorted() {
      if let value = spec.txtRecords[key] {
        args.append(value.isEmpty ? key : "\(key)=\(value)")
      }
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: dnsSDPath)
    process.arguments = args
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    let errPipe = Pipe()
    process.standardError = errPipe

    do {
      try process.run()
    } catch {
      throw DebagrError(
        code: .bridgeError,
        category: "bridge",
        message: "Failed starting dns-sd proxy: \(error.localizedDescription)",
        recoverable: true
      )
    }

    try? await Task.sleep(for: .milliseconds(200))
    if !process.isRunning {
      let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
      let errText = String(decoding: errData, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      throw DebagrError(
        code: .bridgeError,
        category: "bridge",
        message:
          "dns-sd proxy exited immediately (status \(process.terminationStatus)): \(errText)",
        recoverable: true
      )
    }

    let handle = ProxyHandle(spec: spec)
    activeProcesses[handle.id] = process
    return handle
  }

  public func stopProxy(_ handle: ProxyHandle) async {
    guard let process = activeProcesses.removeValue(forKey: handle.id) else { return }
    terminateProcess(process)
  }

  public func stopAllProxies() async {
    let all = activeProcesses.values
    activeProcesses.removeAll()
    for process in all {
      terminateProcess(process)
    }
  }

  private func terminateProcess(_ process: Process) {
    guard process.isRunning else { return }
    process.terminate()
    let pid = process.processIdentifier
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) {
      if process.isRunning {
        kill(pid, SIGKILL)
      }
    }
  }

  private func runTimedDNSSD(arguments: [String], captureDuration: TimeInterval) async throws
    -> String
  {
    guard FileManager.default.isExecutableFile(atPath: dnsSDPath) else {
      throw DebagrError(
        code: .bridgeError,
        category: "bridge",
        message: "System DNS-SD utility not found at \(dnsSDPath).",
        recoverable: false
      )
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: dnsSDPath)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    let stdoutPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = FileHandle.nullDevice

    try process.run()
    try await Task.sleep(for: .seconds(captureDuration))
    if process.isRunning {
      process.terminate()
    }
    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    return String(decoding: data, as: UTF8.self)
  }

  public static func parseBrowseInstances(from output: String) -> [String] {
    var added: Set<String> = []
    var ordered: [String] = []
    for rawLine in output.split(separator: "\n") {
      let line = String(rawLine)
      guard line.contains(" Add "), line.contains("_apple-mobdev2._tcp.") else { continue }
      if let range = line.range(of: "_apple-mobdev2._tcp.") {
        let instance = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !instance.isEmpty, !added.contains(instance) {
          added.insert(instance)
          ordered.append(instance)
        }
      }
    }
    return ordered
  }

  public static func parseLookupOutput(
    instanceName: String,
    serviceType: String,
    domain: String,
    output: String
  ) -> BonjourServiceRecord? {
    // Expected line like:
    // " 11:02:00.123  ... can be reached at 00008140-....local.:62078 (interface 14)"
    let lines = output.split(separator: "\n").map(String.init)
    var hostTarget: String?
    var port: UInt16 = VPNEndpoint.defaultLockdownPort
    var txtRecords: [String: String] = [:]

    for line in lines {
      if let reachRange = line.range(of: "can be reached at ") {
        let after = line[reachRange.upperBound...]
        let hostPortPart = after.split(separator: " ").first.map(String.init) ?? ""
        if let colonIdx = hostPortPart.lastIndex(of: ":") {
          let host = String(hostPortPart[..<colonIdx])
          let portStr = String(hostPortPart[hostPortPart.index(after: colonIdx)...])
          if !host.isEmpty {
            hostTarget = host
          }
          if let parsedPort = UInt16(portStr) {
            port = parsedPort
          }
        }
      } else if line.contains("=") && !line.hasPrefix("DATE:") && !line.hasPrefix("Lookup ") {
        let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        for token in tokens where token.contains("=") {
          let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
          if parts.count == 2 {
            txtRecords[parts[0]] = parts[1]
          }
        }
      }
    }

    guard let hostTarget else { return nil }
    return BonjourServiceRecord(
      instanceName: instanceName,
      serviceType: serviceType,
      domain: domain,
      hostTarget: hostTarget,
      port: port,
      txtRecords: txtRecords
    )
  }
}
