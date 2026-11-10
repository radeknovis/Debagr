import AppKit
import SwiftUI

struct PairingFlowAction: Identifiable {
  let id: String
  let title: String
  let enabled: Bool
  let primary: Bool
  let perform: () -> Void
}

/// Presentation supplied by the USB/IP coordinator to the common connection screen.
final class InitialPairingPresentation: ObservableObject {
  @Published var step = ConnectionStep.device
  @Published var status = "Choose your Builder and Client."
  @Published var actions: [PairingFlowAction] = []
  @Published var canLeave = true
  @Published var revision = 0
  var content: NSView?
}

struct InitialPairingContent: View {
  @ObservedObject var presentation: InitialPairingPresentation
  var body: some View {
    ConnectionProgress(step: presentation.step, isInitialPairing: true)
    if let content = presentation.content {
      NativeFlowContent(content: content, revision: presentation.revision)
    }
  }
}

struct InitialPairingActions: View {
  @ObservedObject var presentation: InitialPairingPresentation
  var body: some View {
    HStack(spacing: 12) {
      Text(presentation.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
      Spacer(minLength: 0)
      if presentation.actions.isEmpty {
        Button("Continue") {}.buttonStyle(.borderedProminent).controlSize(.large).disabled(true)
      }
      ForEach(presentation.actions) { action in
        if action.primary {
          Button(action.title, action: action.perform)
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction).disabled(!action.enabled)
        } else {
          Button(action.title, action: action.perform)
            .buttonStyle(.bordered).controlSize(.large).disabled(!action.enabled)
        }
      }
    }
  }
}

/// The coordinator retains native pickers and sheets; the parent owns scrolling and layout.
private struct NativeFlowContent: NSViewRepresentable {
  let content: NSView
  let revision: Int
  func makeNSView(context: Context) -> NSView {
    let container = NSView()
    content.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      content.topAnchor.constraint(equalTo: container.topAnchor),
      content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    return container
  }
  func updateNSView(_ view: NSView, context: Context) { view.needsLayout = true }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
    let width = proposal.width ?? 660
    return CGSize(width: width, height: max(0, content.fittingSize.height))
  }
}
