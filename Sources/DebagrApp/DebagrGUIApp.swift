import AppKit
import DebagrCore
import SwiftUI

public struct DebagrGUIApp: App {
  @NSApplicationDelegateAdaptor(DebagrAppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel()
  @StateObject private var windowLifecycle = WindowLifecycleController()
  @Environment(\.openWindow) private var openWindow
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init() {}

  public var body: some Scene {
    MenuBarExtra {
      MenuBarView(model: model) {
        windowLifecycle.activateForWindow()
        openWindow(id: "main")
      } onOpenSettings: {
        windowLifecycle.activateForWindow()
      }
      .onAppear {
        registerTerminationHook()
      }
    } label: {
      Label("Debagr", systemImage: model.verdict.menuBarSymbol)
        .symbolEffect(
          .variableColor.iterative,
          options: .repeating,
          isActive: !reduceMotion
            && (model.isCheckingReadiness || model.bridgeSnapshot.state == .probingVPN)
        )
    }
    .menuBarExtraStyle(.window)

    Window("Debagr", id: "main") {
      MainWindowView(model: model, windowLifecycle: windowLifecycle)
        .frame(minWidth: 920, minHeight: 640)
        .onAppear {
          registerTerminationHook()
          windowLifecycle.activateForWindow()
        }
    }
    .defaultSize(width: 980, height: 700)
    .windowToolbarStyle(.unified)
    .commands {
      CommandGroup(after: .toolbar) {
        Button("Verify Connection") {
          Task { await model.refreshReadiness() }
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(model.config.managedDevice == nil || model.isCheckingReadiness)

        Button("Copy Redacted Diagnostics") {
          Task { _ = await model.copyRedactedDiagnostics() }
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
      }

      CommandMenu("Navigate") {
        Button("Overview") { model.navigate(to: .overview) }
          .keyboardShortcut("1", modifiers: .command)
        Button("Wireless Setup") { model.navigate(to: .wirelessSetup) }
          .keyboardShortcut("2", modifiers: .command)
        Button("Agent & SSH") { model.navigate(to: .agentOnboarding) }
          .keyboardShortcut("3", modifiers: .command)
        Button("Experimental") { model.navigate(to: .experimental) }
          .keyboardShortcut("4", modifiers: .command)
      }
    }

    Settings {
      PreferencesView(model: model)
        .onAppear {
          registerTerminationHook()
          windowLifecycle.activateForWindow()
        }
    }
  }

  private func registerTerminationHook() {
    let appModel = model
    DebagrAppDelegate.onTerminate = {
      await appModel.shutdownBridge()
    }
  }
}
