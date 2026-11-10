import Darwin
import Foundation

final class LockedValue<Value> {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) {
    self.value = value
  }

  func withValue<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }

  func get() -> Value {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set(_ value: Value) {
    lock.lock()
    self.value = value
    lock.unlock()
  }
}

enum OwnedProcessError: LocalizedError {
  case alreadyRunning
  case failedToStart(String)

  var errorDescription: String? {
    switch self {
    case .alreadyRunning:
      return "The child process is already running."
    case .failedToStart(let path):
      return "Unable to start child process at \(path)."
    }
  }
}

/// Runs one explicitly owned child and forwards complete stdout/stderr lines.
///
/// The executable path and arguments are passed directly to Process. No shell
/// is involved, and stop() only signals this instance's process identifier.
final class OwnedLineProcess {
  private let executablePath: String
  private let arguments: [String]
  private let lineHandler: (String) -> Void
  private let terminationHandler: ((Int32) -> Void)?
  private let lineQueue: DispatchQueue

  private var process: Process?
  private var outputPipe: Pipe?
  private var bufferedOutput = Data()

  init(
    executablePath: String,
    arguments: [String],
    label: String,
    terminationHandler: ((Int32) -> Void)? = nil,
    lineHandler: @escaping (String) -> Void
  ) {
    self.executablePath = executablePath
    self.arguments = arguments
    self.lineHandler = lineHandler
    self.terminationHandler = terminationHandler
    self.lineQueue = DispatchQueue(label: label)
  }

  var isRunning: Bool {
    process?.isRunning == true
  }

  func start() throws {
    guard process == nil else {
      throw OwnedProcessError.alreadyRunning
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
        self?.flushOutput()
      } else {
        self?.appendOutput(data)
      }
    }

    process.terminationHandler = { [weak self] process in
      self?.flushOutput()
      self?.terminationHandler?(process.terminationStatus)
    }

    self.outputPipe = pipe
    self.process = process

    do {
      try process.run()
    } catch {
      pipe.fileHandleForReading.readabilityHandler = nil
      self.outputPipe = nil
      self.process = nil
      throw OwnedProcessError.failedToStart(executablePath)
    }
  }

  func stop() {
    guard let process else { return }

    outputPipe?.fileHandleForReading.readabilityHandler = nil

    guard process.isRunning else {
      flushOutput()
      return
    }

    process.terminate()

    // dns-sd/log stream are owned children. A cooperative termination is
    // preferred, with a narrowly scoped fallback for a stuck child.
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.75) {
      if process.isRunning {
        _ = kill(process.processIdentifier, SIGKILL)
      }
    }
  }

  deinit {
    stop()
  }

  func appendOutput(_ data: Data) {
    lineQueue.async { [weak self] in
      guard let self else { return }
      self.bufferedOutput.append(data)
      self.emitCompleteLines()
    }
  }

  func flushOutput() {
    lineQueue.async { [weak self] in
      guard let self else { return }
      self.emitCompleteLines()
      if !self.bufferedOutput.isEmpty {
        self.lineHandler(String(decoding: self.bufferedOutput, as: UTF8.self))
        self.bufferedOutput.removeAll(keepingCapacity: false)
      }
    }
  }

  private func emitCompleteLines() {
    while let newline = bufferedOutput.firstIndex(of: 10) {
      var line = String(decoding: bufferedOutput[..<newline], as: UTF8.self)
      if line.last == "\r" {
        line.removeLast()
      }
      bufferedOutput.removeSubrange(...newline)
      lineHandler(line)
    }
  }
}

func localBonjourHostName() -> String {
  let rawName = ProcessInfo.processInfo.hostName
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .trimmingCharacters(in: CharacterSet(charactersIn: "."))

  guard !rawName.isEmpty else { return "localhost.local." }

  if rawName.lowercased().hasSuffix(".local") {
    return rawName + "."
  }

  return rawName + ".local."
}

// Access to the stored value is serialized by NSLock.
extension LockedValue: @unchecked Sendable where Value: Sendable {}
