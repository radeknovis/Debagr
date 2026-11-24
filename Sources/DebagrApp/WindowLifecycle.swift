import AppKit
import Foundation
import os

@MainActor
public final class DebagrAppDelegate: NSObject, NSApplicationDelegate {
  public static var onPrepareTerminate: (@MainActor () -> (@Sendable () async -> Void))?
  private var isTerminating = false

  public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if isTerminating {
      return .terminateLater
    }
    guard let prepare = Self.onPrepareTerminate else {
      return .terminateNow
    }
    isTerminating = true
    Self.onPrepareTerminate = nil
    let asyncCleanup = prepare()
    Self.runTerminationCleanup(asyncCleanup, timeout: .seconds(3)) {
      NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  private static func runTerminationCleanup(
    _ asyncCleanup: @escaping @Sendable () async -> Void,
    timeout: Duration,
    onFinished: @escaping @MainActor @Sendable () -> Void
  ) {
    let replied = OSAllocatedUnfairLock(initialState: false)
    let finishOnce: @Sendable () -> Void = {
      let shouldFinish = replied.withLock { already -> Bool in
        if already { return false }
        already = true
        return true
      }
      guard shouldFinish else { return }
      scheduleOnMainRunLoop(onFinished)
    }

    let timeoutTask = Task.detached(priority: .userInitiated) {
      do {
        try await Task.sleep(for: timeout)
        finishOnce()
      } catch {
        // Cancelled because cleanup completed before the timeout.
      }
    }

    Task.detached(priority: .userInitiated) {
      await asyncCleanup()
      timeoutTask.cancel()
      finishOnce()
    }
  }

  private nonisolated static func scheduleOnMainRunLoop(
    _ body: @escaping @MainActor @Sendable () -> Void
  ) {
    let mainRunLoop = CFRunLoopGetMain()
    let modes: CFTypeRef
    if let currentMode = CFRunLoopCopyCurrentMode(mainRunLoop) {
      modes = [CFRunLoopMode.commonModes.rawValue, currentMode.rawValue] as CFArray
    } else {
      modes = CFRunLoopMode.commonModes.rawValue
    }
    CFRunLoopPerformBlock(mainRunLoop, modes) {
      MainActor.assumeIsolated {
        body()
      }
    }
    CFRunLoopWakeUp(mainRunLoop)
  }
}

@MainActor
public final class WindowLifecycleController: ObservableObject {
  private final class ObserverBox: @unchecked Sendable {
    var token: NSObjectProtocol?

    deinit {
      if let token {
        NotificationCenter.default.removeObserver(token)
      }
    }
  }

  private let observerBox = ObserverBox()

  public init() {
    observerBox.token = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        // Wait briefly so the closing window transitions out of visible state
        try? await Task.sleep(for: .milliseconds(150))
        Self.updateActivationPolicyForVisibleWindows()
      }
    }
  }

  public func activateForWindow() {
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  private static func updateActivationPolicyForVisibleWindows() {
    let hasStandardWindow = NSApp.windows.contains { win in
      (win.isVisible || win.isMiniaturized) && win.canBecomeMain && !(win is NSPanel)
    }
    if !hasStandardWindow && NSApp.activationPolicy() != .accessory {
      NSApp.setActivationPolicy(.accessory)
    }
  }
}
