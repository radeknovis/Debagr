import Foundation
import Network
import os

public protocol TCPProbing: Sendable {
  func probe(host: String, port: UInt16, timeoutSeconds: TimeInterval) async -> Bool
}

public final class NWConnectionTCPProbe: TCPProbing, Sendable {
  public init() {}

  public func probe(host: String, port: UInt16, timeoutSeconds: TimeInterval = 3.0) async -> Bool {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
    let nwHost = NWEndpoint.Host(host)
    let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
    let queue = DispatchQueue(label: "dev.debagr.tcpprobe.\(UUID().uuidString)")
    let finished = OSAllocatedUnfairLock(initialState: false)

    return await withCheckedContinuation { continuation in
      let resumeOnce: @Sendable (Bool) -> Void = { success in
        let shouldResume = finished.withLock { already -> Bool in
          if already { return false }
          already = true
          return true
        }
        guard shouldResume else { return }
        connection.cancel()
        continuation.resume(returning: success)
      }

      connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          resumeOnce(true)
        case .failed, .cancelled:
          resumeOnce(false)
        default:
          break
        }
      }

      connection.start(queue: queue)

      let effectiveTimeout = max(0.2, timeoutSeconds)
      queue.asyncAfter(deadline: .now() + effectiveTimeout) {
        resumeOnce(false)
      }
    }
  }
}
