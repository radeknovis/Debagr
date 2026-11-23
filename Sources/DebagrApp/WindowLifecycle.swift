import AppKit
import Foundation

@MainActor
public final class DebagrAppDelegate: NSObject, NSApplicationDelegate {
  public static var onTerminate: (@MainActor () async -> Void)?

  public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let handler = Self.onTerminate else {
      return .terminateNow
    }
    Self.onTerminate = nil
    Task { @MainActor in
      await handler()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
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
