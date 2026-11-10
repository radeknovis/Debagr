import Foundation

struct TunnelPortParser {
  static func port(in line: String) -> UInt16? {
    guard let marker = line.range(of: "Got tunnel endpoint: '") else { return nil }
    let endpointStart = marker.upperBound
    guard let endpointEnd = line[endpointStart...].firstIndex(of: "'") else { return nil }

    let endpoint = line[endpointStart..<endpointEnd]
    let separator: String.Index?
    if let scope = endpoint.lastIndex(of: "%"),
      let scopeSeparator = endpoint[scope...].lastIndex(of: ".")
    {
      separator = scopeSeparator
    } else {
      separator = endpoint.lastIndex(of: ":")
    }
    guard let separator else { return nil }

    let portText = endpoint[endpoint.index(after: separator)...]
    guard let port = UInt32(portText), port > 0, port <= 65_535 else { return nil }
    return UInt16(port)
  }
}

final class TunnelPortWatcher {
  static let predicate =
    "process == \"remotepairingd\" AND eventMessage CONTAINS \"Got tunnel endpoint\""

  private let queue = DispatchQueue(label: "debagr.tunnel-port-watcher")
  private let stateLock = NSLock()
  private var process: OwnedLineProcess?
  private var generation = 0
  private var seenPorts = Set<UInt16>()
  private var callback: ((UInt16) -> Void)?

  func start(onNewPort: @escaping (UInt16) -> Void) throws {
    stop()

    stateLock.lock()
    generation += 1
    let currentGeneration = generation
    callback = onNewPort
    seenPorts.removeAll()
    stateLock.unlock()

    let process = OwnedLineProcess(
      executablePath: "/usr/bin/log",
      arguments: [
        "stream",
        "--style",
        "compact",
        "--predicate",
        Self.predicate,
      ],
      label: "debagr.tunnel-log-process",
      terminationHandler: { [weak self] _ in
        self?.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
          guard let self, self.isActive(currentGeneration) else { return }
          self.stateLock.lock()
          let callback = self.callback
          self.stateLock.unlock()
          if let callback { try? self.start(onNewPort: callback) }
        }
      },
      lineHandler: { [weak self] line in
        self?.queue.async { [weak self] in
          self?.consume(line, generation: currentGeneration)
        }
      })

    stateLock.lock()
    self.process = process
    stateLock.unlock()

    do {
      try process.start()
    } catch {
      stop()
      throw error
    }
  }

  func forget(port: UInt16) {
    stateLock.lock()
    seenPorts.remove(port)
    stateLock.unlock()
  }

  func stop() {
    stateLock.lock()
    generation += 1
    let process = self.process
    self.process = nil
    callback = nil
    stateLock.unlock()

    process?.stop()
  }

  deinit {
    stop()
  }

  private func consume(_ line: String, generation: Int) {
    guard isActive(generation), let port = TunnelPortParser.port(in: line) else { return }

    stateLock.lock()
    let isNew = seenPorts.insert(port).inserted
    let callback = self.callback
    stateLock.unlock()

    if isNew {
      callback?(port)
    }
  }

  private func isActive(_ expectedGeneration: Int) -> Bool {
    stateLock.lock()
    let active = generation == expectedGeneration
    stateLock.unlock()
    return active
  }
}
