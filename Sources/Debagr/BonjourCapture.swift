import Foundation

enum BonjourCaptureError: LocalizedError {
  case processExited(Int32)

  var errorDescription: String? {
    switch self {
    case .processExited(let status):
      return "Device discovery stopped unexpectedly (status \(status))."
    }
  }
}

struct BonjourDevice: Codable, Equatable {
  let instanceName: String
  let serviceType: String
  let hostName: String
  let port: UInt16
  let txt: [String: String]

  var suggestedDisplayName: String {
    let candidate =
      hostName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      .replacingOccurrences(of: ".local", with: "")
      .replacingOccurrences(of: "-", with: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")

    guard !candidate.isEmpty, !Self.looksLikeIdentifier(candidate) else {
      return instanceName
    }
    return candidate
  }

  private static func looksLikeIdentifier(_ value: String) -> Bool {
    let compact = value.replacingOccurrences(of: " ", with: "")
    guard compact.count == 32 else { return false }
    return compact.allSatisfy { $0.isHexDigit }
  }
}

struct BonjourZoneParser {
  private struct PartialRecord {
    var instanceName: String?
    var hostName: String?
    var port: UInt16?
    var txt: [String: String] = [:]
  }

  static let serviceType = "_remotepairing._tcp"
  static let domain = "local"

  private var records: [String: PartialRecord] = [:]
  private let preferredHostName: String?

  init(preferredHostName: String? = nil) {
    self.preferredHostName = preferredHostName.map(Self.canonicalDNSName)
  }

  var devices: [BonjourDevice] {
    records.keys.sorted().compactMap { key in
      guard let record = records[key],
        let instanceName = record.instanceName,
        let hostName = record.hostName,
        let port = record.port
      else {
        return nil
      }

      guard
        preferredHostName == nil
          || Self.canonicalDNSName(hostName) == preferredHostName
      else {
        return nil
      }

      return BonjourDevice(
        instanceName: instanceName,
        serviceType: Self.serviceType,
        hostName: hostName,
        port: port,
        txt: record.txt
      )
    }
  }

  var device: BonjourDevice? {
    devices.first
  }

  mutating func consume(_ line: String) {
    let tokens = Self.tokenize(line)
    guard
      let typeIndex = tokens.firstIndex(where: { ["PTR", "SRV", "TXT"].contains($0.uppercased()) }),
      typeIndex > 0
    else {
      return
    }

    let recordType = tokens[typeIndex].uppercased()
    guard
      let rawOwner = tokens[..<typeIndex]
        .reversed()
        .first(where: { token in
          let candidate = Self.canonicalDNSName(token)
          return Self.isServiceName(candidate) || Self.isInstanceName(candidate)
        })
    else {
      return
    }
    let owner = Self.canonicalDNSName(rawOwner)

    switch recordType {
    case "PTR":
      guard tokens.count > typeIndex + 1,
        Self.isServiceName(owner)
      else { return }

      let rawTarget = Self.trimDNSName(tokens[typeIndex + 1])
      let target = Self.canonicalDNSName(rawTarget)
      guard Self.isInstanceName(target) else { return }

      var record = records[target, default: PartialRecord()]
      record.instanceName = Self.instanceName(from: rawTarget)
      records[target] = record

    case "SRV":
      guard tokens.count > typeIndex + 4,
        let port = UInt16(tokens[typeIndex + 3]),
        port > 0
      else { return }
      guard Self.isInstanceName(owner) else { return }

      var record = records[owner, default: PartialRecord()]
      record.instanceName = record.instanceName ?? Self.instanceName(from: rawOwner)
      record.port = port
      record.hostName = Self.hostName(from: tokens[typeIndex + 4])
      records[owner] = record
    case "TXT":
      guard Self.isInstanceName(owner) else { return }

      var record = records[owner, default: PartialRecord()]
      for value in tokens.dropFirst(typeIndex + 1) {
        let unescaped = Self.unescapeDNS(value)
        if let equals = unescaped.firstIndex(of: "=") {
          let key = String(unescaped[..<equals])
          let value = String(unescaped[unescaped.index(after: equals)...])
          if !key.isEmpty {
            record.txt[key] = value
          }
        } else if !unescaped.isEmpty {
          record.txt[unescaped] = ""
        }
      }
      records[owner] = record

    default:
      break
    }
  }

  static func tokenize(_ line: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false

    func finishToken() {
      guard !current.isEmpty else { return }
      tokens.append(current)
      current.removeAll(keepingCapacity: true)
    }

    for character in line {
      if escaping {
        current.append(character)
        escaping = false
        continue
      }

      if character == "\\" {
        current.append(character)
        escaping = true
        continue
      }

      if let activeQuote = quote {
        if character == activeQuote {
          quote = nil
          continue
        }
        current.append(character)
        continue
      }

      if character == "\"" || character == "'" {
        quote = character
      } else if character.isWhitespace {
        finishToken()
      } else {
        current.append(character)
      }
    }

    if escaping {
      current.append("\\")
    }
    finishToken()
    return tokens
  }

  private static func canonicalDNSName(_ value: String) -> String {
    trimDNSName(value).lowercased()
  }

  private static func trimDNSName(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
  }

  private static func isServiceName(_ value: String) -> Bool {
    value == "\(serviceType).\(domain)" || value == serviceType
  }

  private static func isInstanceName(_ value: String) -> Bool {
    value.hasSuffix(".\(serviceType).\(domain)")
      || value.hasSuffix(".\(serviceType)")
  }

  private static func instanceName(from value: String) -> String {
    let suffixes = [".\(serviceType).\(domain)", ".\(serviceType)"]
    for suffix in suffixes {
      if let range = value.range(of: suffix, options: [.caseInsensitive, .backwards]) {
        return unescapeDNS(String(value[..<range.lowerBound]))
      }
    }
    return unescapeDNS(value)
  }

  private static func hostName(from value: String) -> String {
    unescapeDNS(value).trimmingCharacters(in: CharacterSet(charactersIn: "."))
  }

  private static func unescapeDNS(_ value: String) -> String {
    var output = ""
    let characters = Array(value)
    var index = 0

    while index < characters.count {
      let character = characters[index]
      index += 1
      guard character == "\\" else {
        output.append(character)
        continue
      }

      var digits = ""
      while index < characters.count, digits.count < 3, characters[index].isNumber {
        digits.append(characters[index])
        index += 1
      }
      if !digits.isEmpty, let scalar = UInt32(digits), let unicode = UnicodeScalar(scalar) {
        output.append(Character(unicode))
      } else if index < characters.count {
        output.append(characters[index])
        index += 1
      }
    }
    return output
  }
}

final class BonjourCapture {
  private enum Mode: Equatable {
    case none
    case zone
    case browse
  }

  private let queue = DispatchQueue(label: "debagr.bonjour-capture")
  private let stateLock = NSLock()
  private var process: OwnedLineProcess?
  private var mode: Mode = .none
  private var generation = 0
  private var zoneParser = BonjourZoneParser()
  private var zoneDevicesCallback: (([BonjourDevice]) -> Void)?
  private var zoneFailureCallback: ((Error) -> Void)?
  private var browseCallback: ((String) -> Void)?
  private var deliveryScheduled = false
  private var lastDeliveredDevices: [BonjourDevice] = []

  func startZoneCapture(
    matchingHostName: String? = nil,
    onFailure: ((Error) -> Void)? = nil,
    onDevice: @escaping (BonjourDevice) -> Void
  ) throws {
    try startZoneCaptureAll(
      matchingHostName: matchingHostName,
      onFailure: onFailure,
      onDevices: { devices in
        guard let device = devices.first else { return }
        onDevice(device)
      })
  }

  func startZoneCaptureAll(
    matchingHostName: String? = nil,
    onFailure: ((Error) -> Void)? = nil,
    onDevices: @escaping ([BonjourDevice]) -> Void
  ) throws {
    stop()

    let currentGeneration = activate(mode: .zone)
    queue.sync {
      zoneParser = BonjourZoneParser(preferredHostName: matchingHostName)
      zoneDevicesCallback = onDevices
      zoneFailureCallback = onFailure
      browseCallback = nil
      deliveryScheduled = false
      lastDeliveredDevices.removeAll()
    }

    let process = OwnedLineProcess(
      executablePath: "/usr/bin/dns-sd",
      arguments: ["-Z", BonjourZoneParser.serviceType, BonjourZoneParser.domain],
      label: "debagr.bonjour-zone-process",
      terminationHandler: { [weak self] status in
        self?.queue.async { [weak self] in
          guard let self, self.isActive(currentGeneration, mode: .zone) else { return }
          self.zoneFailureCallback?(BonjourCaptureError.processExited(status))
        }
      },
      lineHandler: { [weak self] line in
        self?.queue.async { [weak self] in
          self?.consumeZoneLine(line, generation: currentGeneration)
        }
      })

    setProcess(process)
    do {
      try process.start()
    } catch {
      stop()
      throw error
    }
  }

  func startBrowsing(onVisible: @escaping (String) -> Void) throws {
    stop()

    let currentGeneration = activate(mode: .browse)
    queue.sync {
      zoneParser = BonjourZoneParser()
      zoneDevicesCallback = nil
      zoneFailureCallback = nil
      browseCallback = onVisible
      deliveryScheduled = false
      lastDeliveredDevices.removeAll()
    }

    let process = OwnedLineProcess(
      executablePath: "/usr/bin/dns-sd",
      arguments: ["-B", BonjourZoneParser.serviceType, BonjourZoneParser.domain],
      label: "debagr.bonjour-browse-process"
    ) { [weak self] line in
      self?.queue.async { [weak self] in
        self?.consumeBrowseLine(line, generation: currentGeneration)
      }
    }

    setProcess(process)
    do {
      try process.start()
    } catch {
      stop()
      throw error
    }
  }

  func stop() {
    stateLock.lock()
    generation += 1
    mode = .none
    let process = self.process
    self.process = nil
    stateLock.unlock()

    process?.stop()

    queue.async { [weak self] in
      guard let self else { return }
      self.zoneDevicesCallback = nil
      self.zoneFailureCallback = nil
      self.browseCallback = nil
      self.deliveryScheduled = false
      self.lastDeliveredDevices.removeAll()
    }
  }

  deinit {
    stop()
  }

  private func activate(mode: Mode) -> Int {
    stateLock.lock()
    generation += 1
    self.mode = mode
    let result = generation
    stateLock.unlock()
    return result
  }

  private func setProcess(_ process: OwnedLineProcess) {
    stateLock.lock()
    self.process = process
    stateLock.unlock()
  }

  private func isActive(_ expectedGeneration: Int, mode expectedMode: Mode) -> Bool {
    stateLock.lock()
    let active = generation == expectedGeneration && mode == expectedMode
    stateLock.unlock()
    return active
  }

  private func consumeZoneLine(_ line: String, generation: Int) {
    guard isActive(generation, mode: .zone) else { return }
    zoneParser.consume(line)

    guard !zoneParser.devices.isEmpty, !deliveryScheduled else { return }
    deliveryScheduled = true
    queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      guard let self,
        self.isActive(generation, mode: .zone),
        let callback = self.zoneDevicesCallback
      else {
        self?.deliveryScheduled = false
        return
      }

      let devices = self.zoneParser.devices
      guard devices != self.lastDeliveredDevices else {
        self.deliveryScheduled = false
        return
      }

      self.lastDeliveredDevices = devices
      self.deliveryScheduled = false
      callback(devices)
    }
  }

  private func consumeBrowseLine(_ line: String, generation: Int) {
    guard isActive(generation, mode: .browse), line.contains("Add") else { return }

    let tokens = BonjourZoneParser.tokenize(line)
    guard
      let serviceIndex = tokens.firstIndex(where: {
        BonjourZoneParser.canonicalServiceToken($0)
      }), tokens.count > serviceIndex + 1
    else {
      return
    }

    let instance = tokens.dropFirst(serviceIndex + 1).joined(separator: " ")
    browseCallback?(instance)
  }
}

extension BonjourZoneParser {
  fileprivate static func canonicalServiceToken(_ value: String) -> Bool {
    let normalized =
      value
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      .lowercased()
    return normalized == serviceType
  }
}
