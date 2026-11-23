import Foundation
import os

public struct CommandResult: Sendable, Equatable {
  public let exitCode: Int32
  public let stdout: Data
  public let stderr: Data
  public let timedOut: Bool
  public let durationMs: Int

  public init(
    exitCode: Int32,
    stdout: Data,
    stderr: Data,
    timedOut: Bool,
    durationMs: Int
  ) {
    self.exitCode = exitCode
    self.stdout = stdout
    self.stderr = stderr
    self.timedOut = timedOut
    self.durationMs = durationMs
  }

  public var stdoutString: String {
    String(decoding: stdout, as: UTF8.self)
  }

  public var stderrString: String {
    String(decoding: stderr, as: UTF8.self)
  }
}

public protocol CommandRunning: Sendable {
  func run(
    executable: String,
    arguments: [String],
    environment: [String: String]?,
    timeoutSeconds: TimeInterval
  ) async throws -> CommandResult
}

extension CommandRunning {
  public func run(
    executable: String,
    arguments: [String],
    timeoutSeconds: TimeInterval = 30
  ) async throws -> CommandResult {
    try await run(
      executable: executable,
      arguments: arguments,
      environment: nil,
      timeoutSeconds: timeoutSeconds
    )
  }
}

public final class SubprocessRunner: CommandRunning, Sendable {
  public init() {}

  public func run(
    executable: String,
    arguments: [String],
    environment: [String: String]? = nil,
    timeoutSeconds: TimeInterval = 30
  ) async throws -> CommandResult {
    let start = ContinuousClock.now
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let environment {
      var merged = ProcessInfo.processInfo.environment
      for (key, value) in environment {
        merged[key] = value
      }
      process.environment = merged
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.standardInput = FileHandle.nullDevice

    let timeoutFlag = OSAllocatedUnfairLock(initialState: false)
    let finishLock = OSAllocatedUnfairLock(initialState: false)

    return try await withCheckedThrowingContinuation { continuation in
      let readQueue = DispatchQueue(
        label: "dev.debagr.subprocess.read",
        attributes: .concurrent
      )
      let group = DispatchGroup()
      let capturedOut = OSAllocatedUnfairLock(initialState: Data())
      let capturedErr = OSAllocatedUnfairLock(initialState: Data())

      process.terminationHandler = { terminated in
        group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
          let alreadyFinished = finishLock.withLock { done -> Bool in
            if done { return true }
            done = true
            return false
          }
          guard !alreadyFinished else { return }

          let outData = capturedOut.withLock { $0 }
          let errData = capturedErr.withLock { $0 }
          let didTimeout = timeoutFlag.withLock { $0 }
          let elapsed = ContinuousClock.now - start
          let ms = Int(
            elapsed.components.seconds * 1000
              + elapsed.components.attoseconds / 1_000_000_000_000_000
          )
          continuation.resume(
            returning: CommandResult(
              exitCode: terminated.terminationStatus,
              stdout: outData,
              stderr: errData,
              timedOut: didTimeout,
              durationMs: max(0, ms)
            )
          )
        }
      }

      do {
        try process.run()
      } catch {
        let alreadyFinished = finishLock.withLock { done -> Bool in
          if done { return true }
          done = true
          return false
        }
        if !alreadyFinished {
          continuation.resume(throwing: error)
        }
        return
      }

      group.enter()
      readQueue.async {
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        capturedOut.withLock { $0 = data }
        group.leave()
      }

      group.enter()
      readQueue.async {
        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        capturedErr.withLock { $0 = data }
        group.leave()
      }

      if timeoutSeconds > 0 {
        let deadline = DispatchTime.now() + timeoutSeconds
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
          guard process.isRunning else { return }
          timeoutFlag.withLock { $0 = true }
          process.terminate()
          DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            if process.isRunning {
              kill(process.processIdentifier, SIGKILL)
            }
          }
        }
      }
    }
  }
}
