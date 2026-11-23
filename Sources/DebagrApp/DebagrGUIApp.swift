import AppKit
import DebagrCore
import SwiftUI

public struct DebagrGUIApp: App {
  @StateObject private var model = AppModel()
  @Environment(\.openWindow) private var openWindow

  public init() {}

  public var body: some Scene {
    MenuBarExtra {
      MenuBarView(model: model) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
      }
    } label: {
      Label("Debagr", systemImage: model.menuBarIconName)
    }
    .menuBarExtraStyle(.window)

    Window("Debagr", id: "main") {
      MainWindowView(model: model)
        .frame(minWidth: 900, minHeight: 620)
        .onAppear {
          NSApp.setActivationPolicy(.regular)
          NSApp.activate(ignoringOtherApps: true)
        }
    }
    .defaultSize(width: 980, height: 680)
  }
}
