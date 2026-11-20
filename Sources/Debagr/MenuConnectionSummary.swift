import AppKit

// Discovery, USB ownership, readiness, and a deployment receipt are different evidence.
enum MenuReadiness {
  case checking, ready
  case attention(String)
}

struct MenuConnectionPresentation {
  enum Tone: Equatable { case neutral, good, attention }
  let title: String
  let scope: String
  let status: String
  let detail: String
  let history: String
  let tone: Tone
  let actionTitle: String
  let iconState: MenuBarIconState

  init(
    configured: ConfiguredDevice?, selection: MachineRoleSelection?, usbActive: Bool,
    readiness: MenuReadiness, receipt: DeploymentReceipt?
  ) {
    scope =
      selection?.role == .client ? "Client" : selection?.role == .builder ? "Builder" : "This Mac"
    title =
      configured?.displayName
      ?? (selection?.role == .client ? "Your device, with you" : "Connect your iPhone")
    actionTitle = "Open Debagr"
    if usbActive {
      iconState = .usb
      status = selection?.role == .client ? "Temporary USB sharing" : "Temporary USB import"
      detail = "Open Connections to check the device or stop this setup session."
      tone = .neutral
    } else if configured == nil, selection?.role == .client {
      iconState = .idle
      status = "Client Mac"
      detail = "Builder: \(selection!.peerName). Open setup to share your plugged-in device."
      tone = .neutral
    } else if let configured {
      if !configured.enabled {
        iconState = .paused
        status = "Connection paused"
        detail = "Resume the connection when you want to deploy again."
        tone = .neutral
      } else {
        switch readiness {
        case .checking:
          iconState = .checking
          status = "Checking connection…"
          detail = "Waiting for Apple to confirm device connectivity."
          tone = .neutral
        case .ready:
          iconState = .ready
          status = "Ready for deployment"
          detail = "Device reachable and unlocked. Keep it awake for your next build."
          tone = .good
        case .attention(let recovery):
          iconState = .attention
          status = "Needs attention"
          detail = recovery
          tone = .attention
        }
      }
    } else {
      iconState = .idle
      status = "No device configured"
      detail = "Use an existing Apple pairing or create one with a nearby Mac."
      tone = .neutral
    }
    if let receipt, receipt.deviceIdentifier == configured?.deviceIdentifier {
      history =
        "Last deploy · \(receipt.launched ? "Installed & launched" : "Installed") · \(receipt.completedAt.formatted(date: .omitted, time: .shortened))"
    } else {
      history = "No deployment recorded for this device"
    }
  }
}

/// Read-only summary; all actions remain native menu rows with normal keyboard navigation.
final class MenuConnectionSummaryView: NSView {
  private let scope = NSTextField(labelWithString: "This Mac")
  private let target = NSTextField(labelWithString: "Connect your iPhone")
  private let status = NSTextField(labelWithString: "Checking connection…")
  private let detail = NSTextField(wrappingLabelWithString: "")
  private let history = NSTextField(labelWithString: "")
  private let dot = NSImageView()

  init() {
    super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 164))
    let brand = NSTextField(labelWithString: "Debagr")
    brand.font = .systemFont(ofSize: 12, weight: .semibold)
    scope.font = .systemFont(ofSize: 11)
    scope.textColor = .secondaryLabelColor
    let top = NSStackView(views: [brand, NSView(), scope])
    top.orientation = .horizontal
    target.font = .systemFont(ofSize: 18, weight: .semibold)
    target.lineBreakMode = .byTruncatingTail
    status.font = .systemFont(ofSize: 12, weight: .medium)
    dot.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
    dot.symbolConfiguration = .init(pointSize: 7, weight: .regular)
    dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
    let state = NSStackView(views: [dot, status])
    state.orientation = .horizontal
    state.spacing = 6
    detail.font = .systemFont(ofSize: 11)
    detail.textColor = .secondaryLabelColor
    detail.maximumNumberOfLines = 2
    detail.lineBreakMode = .byWordWrapping
    detail.cell?.wraps = true
    history.font = .systemFont(ofSize: 11)
    history.textColor = .secondaryLabelColor
    history.lineBreakMode = .byTruncatingMiddle
    let content = NSStackView(views: [top, target, state, detail, history])
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 7
    content.setCustomSpacing(12, after: top)
    content.setCustomSpacing(10, after: detail)
    content.translatesAutoresizingMaskIntoConstraints = false
    addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
    ])
    for view in [top, target, detail, history] {
      view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(_ presentation: MenuConnectionPresentation) {
    scope.stringValue = presentation.scope
    target.stringValue = presentation.title
    status.stringValue = presentation.status
    detail.stringValue = presentation.detail
    history.stringValue = presentation.history
    dot.contentTintColor =
      presentation.tone == .good
      ? .systemGreen
      : presentation.tone == .attention ? .systemOrange : .secondaryLabelColor
    target.toolTip = presentation.title
    detail.toolTip = presentation.detail
    history.toolTip = presentation.history
    setAccessibilityLabel(
      "Debagr. \(presentation.scope). \(presentation.title). \(presentation.status). \(presentation.detail). \(presentation.history)"
    )
  }
}
