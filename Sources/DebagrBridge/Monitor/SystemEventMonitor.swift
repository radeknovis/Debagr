import AppKit
import Foundation
import Network
import os

public enum SystemBridgeEvent: Sendable, Equatable {
  case networkChanged(isSatisfied: Bool)
  case systemWillSleep
  case systemDidWake
}

public protocol SystemEventMonitoring: Sendable {
  func events() -> AsyncStream<SystemBridgeEvent>
}

public final class MacOSNetworkAndSleepMonitor: SystemEventMonitoring, Sendable {
  public init() {}

  public func events() -> AsyncStream<SystemBridgeEvent> {
    AsyncStream { continuation in
      let monitor = NWPathMonitor()
      let queue = DispatchQueue(label: "dev.debagr.pathmonitor")
      let lastSatisfied = OSAllocatedUnfairLock<Bool?>(initialState: nil)

      monitor.pathUpdateHandler = { path in
        let satisfied = path.status == .satisfied
        let changed = lastSatisfied.withLock { prev -> Bool in
          if prev == satisfied { return false }
          prev = satisfied
          return true
        }
        if changed {
          continuation.yield(.networkChanged(isSatisfied: satisfied))
        }
      }
      monitor.start(queue: queue)

      let workspaceCenter = NSWorkspace.shared.notificationCenter
      let willSleepToken = workspaceCenter.addObserver(
        forName: NSWorkspace.willSleepNotification,
        object: nil,
        queue: nil
      ) { _ in
        continuation.yield(.systemWillSleep)
      }
      let didWakeToken = workspaceCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: nil
      ) { _ in
        continuation.yield(.systemDidWake)
      }

      final class CleanupState: @unchecked Sendable {
        let monitor: NWPathMonitor
        let center: NotificationCenter
        let tokens: [NSObjectProtocol]

        init(monitor: NWPathMonitor, center: NotificationCenter, tokens: [NSObjectProtocol]) {
          self.monitor = monitor
          self.center = center
          self.tokens = tokens
        }

        func cancel() {
          monitor.cancel()
          for token in tokens {
            center.removeObserver(token)
          }
        }
      }

      let cleanup = CleanupState(
        monitor: monitor,
        center: workspaceCenter,
        tokens: [willSleepToken, didWakeToken]
      )
      continuation.onTermination = { _ in
        cleanup.cancel()
      }
    }
  }
}
