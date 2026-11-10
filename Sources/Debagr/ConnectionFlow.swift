import SwiftUI

enum ConnectionPath: String, CaseIterable, Identifiable {
  case existing, usb
  var id: Self { self }
  var title: String { self == .existing ? "Use existing pairing" : "Initial device pairing" }
  var subtitle: String {
    self == .existing
      ? "Your Builder already knows this device." : "Forward USB from a Mac near your iPhone."
  }
  var symbol: String { self == .existing ? "link" : "cable.connector" }
}

enum ConnectionStep: Int, CaseIterable, Identifiable {
  case device, network, review
  var id: Self { self }
  var title: String {
    switch self {
    case .device: return "Pairing"
    case .network: return "Connection"
    case .review: return "Review"
    }
  }
}

enum ConnectionVerification: Equatable {
  case checking
  case ready(String)
  case attention(String)

  var title: String {
    switch self {
    case .checking: return "Checking the way through."
    case .ready: return "Ready for your next build."
    case .attention: return "One more thing to resolve."
    }
  }

  var detail: String {
    switch self {
    case .checking:
      return "Your setup is saved. Debagr is checking the device through Apple’s connection."
    case .ready(let detail), .attention(let detail): return detail
    }
  }

  var symbol: String {
    switch self {
    case .checking: return "circle.dotted"
    case .ready: return "checkmark.circle"
    case .attention: return "exclamationmark.circle"
    }
  }
}

struct ConnectionPathPicker: View {
  @Binding var selection: ConnectionPath

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ForEach(ConnectionPath.allCases) { path in
        Button {
          selection = path
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Image(systemName: path.symbol).font(.title3)
              Spacer()
              Text(path == .existing ? "EVERYDAY" : "ONE-TIME SETUP")
                .font(.system(size: 9, weight: .semibold)).tracking(0.6)
            }
            Text(path.title).font(.headline)
            Text(path.subtitle).font(.caption).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .foregroundStyle(selection == path ? SettingsStyle.accent : .primary)
          .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
          .padding(12)
          .contentShape(Rectangle())
          .background(
            selection == path ? SettingsStyle.accent.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(
                selection == path ? SettingsStyle.accent : SettingsStyle.border,
                lineWidth: selection == path ? 1.5 : 1
              )
              .allowsHitTesting(false))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == path ? .isSelected : [])
      }
    }
    .accessibilityElement(children: .contain).accessibilityLabel("Pairing path")
  }
}

/// The diagram describes topology, not live connection status.
struct ConnectionDiagram: View {
  let path: ConnectionPath
  var deviceName = "Your iPhone"
  var usbLinkLabel = "USB over SSH"

  var topologyDescription: String {
    path == .existing
      ? "Connection diagram. Your device connects over a private VPN to the Builder that already owns its Apple pairing. No Client Mac is required."
      : "Connection diagram. Your iPhone connects by USB cable to a Client Mac. The Client forwards USB to the remote Builder using \(usbLinkLabel). Approve new trust on the iPhone. The cable is required during pairing."
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text(path == .existing ? "THE EVERYDAY CONNECTION" : "THE ONE-TIME USB BRIDGE")
          .font(.system(size: 9, weight: .semibold)).tracking(1)
        Spacer()
        Image(systemName: "arrow.left.arrow.right").accessibilityHidden(true)
      }
      .foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: 0) {
        DiagramEndpoint(kind: .phone, title: deviceName, detail: "With you")
        DiagramLink(
          label: path == .existing ? "Private VPN" : "USB cable", wireless: path == .existing)
        if path == .usb {
          DiagramEndpoint(kind: .laptop, title: "Client Mac", detail: "Shares USB")
          DiagramLink(label: usbLinkLabel, wireless: true)
        }
        DiagramEndpoint(
          kind: .server, title: "Builder",
          detail: path == .existing ? "Owns Apple pairing" : "Creates Apple pairing")
      }
      Label(
        path == .existing
          ? "Existing trust · the Builder stays paired"
          : "New trust · approve the Builder on your iPhone",
        systemImage: "lock.shield"
      )
      .font(.caption).foregroundStyle(SettingsStyle.accent)
    }
    .padding(16)
    .frame(height: 202)
    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(topologyDescription)
  }
}

struct ConnectionDeviceIcon: View {
  enum Kind { case phone, laptop, server }
  let kind: Kind
  var body: some View {
    ZStack {
      switch kind {
      case .phone:
        RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.7), lineWidth: 2)
          .frame(width: 32, height: 58)
        Capsule().fill(.primary.opacity(0.7)).frame(width: 12, height: 3).offset(y: -23)
        Image(systemName: "app.dashed").font(.system(size: 15)).foregroundStyle(
          SettingsStyle.accent)
      case .laptop:
        RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.7), lineWidth: 2)
          .frame(width: 64, height: 41).offset(y: -3)
        Capsule().fill(.primary.opacity(0.7)).frame(width: 76, height: 3).offset(y: 20)
        Image(systemName: "cable.connector").foregroundStyle(SettingsStyle.accent).offset(y: -3)
      case .server:
        RoundedRectangle(cornerRadius: 10).fill(SettingsStyle.surface)
          .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.7), lineWidth: 2)
          )
          .frame(width: 65, height: 49)
        Image(systemName: "hammer").font(.system(size: 18)).foregroundStyle(SettingsStyle.accent)
        Circle().fill(SettingsStyle.accent).frame(width: 3, height: 3).offset(x: 24, y: 16)
      }
    }
    .frame(width: 76, height: 58)
  }
}

private struct DiagramEndpoint: View {
  let kind: ConnectionDeviceIcon.Kind
  let title: String
  let detail: String

  var body: some View {
    VStack(spacing: 8) {
      ConnectionDeviceIcon(kind: kind)
      Text(title).font(.system(size: 12, weight: .semibold))
        .multilineTextAlignment(.center).lineLimit(2)
      Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct DiagramLink: View {
  let label: String
  let wireless: Bool

  var body: some View {
    VStack(spacing: 8) {
      Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      GeometryReader { geometry in
        Path { path in
          path.move(to: CGPoint(x: 0, y: 4))
          path.addLine(to: CGPoint(x: geometry.size.width, y: 4))
        }
        .stroke(
          SettingsStyle.accent.opacity(0.55),
          style: StrokeStyle(lineWidth: 1.5, dash: wireless ? [4, 4] : []))
      }
      .frame(height: 8)
    }
    .padding(.top, 12).frame(maxWidth: .infinity)
  }
}

struct ConnectionProgress: View {
  let step: ConnectionStep
  var isInitialPairing = false

  private func title(_ step: ConnectionStep) -> String {
    isInitialPairing ? ["Macs", "Device trust", "Wireless"][step.rawValue] : step.title
  }

  var body: some View {
    HStack(spacing: 12) {
      ForEach(ConnectionStep.allCases) { item in
        HStack(spacing: 8) {
          Text("\(item.rawValue + 1)")
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 23, height: 23)
            .background(
              item == step ? SettingsStyle.accent : Color.primary.opacity(0.06), in: Circle()
            )
            .foregroundStyle(item == step ? .white : .secondary)
          Text(title(item)).font(.system(size: 12, weight: item == step ? .semibold : .regular))
            .foregroundStyle(item == step ? .primary : .secondary)
        }
        if item != .review { Rectangle().fill(SettingsStyle.border).frame(height: 1) }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Step \(step.rawValue + 1) of 3: \(title(step))")
  }
}

struct PairingLocationGuide: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Set up on the Mac that will deploy your builds", systemImage: "desktopcomputer")
        .font(.callout.weight(.medium))
      Text(
        "This window configures this Mac as the build server. If your agent runs elsewhere, it sends the deployment here through SSH."
      )
      .font(.callout).foregroundStyle(.secondary)
      DisclosureGroup("Paired with a different Mac, or not paired yet?") {
        Text(
          "A pairing on your Client Mac does not pair your Builder. Connect the device directly to the Builder once, unlock it, approve Trust, and enable Developer Mode. If the Builder is far away, use the new-pairing USB flow above."
        )
        .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
      }
      .font(.callout)
    }
  }
}

struct ConnectionActionBar<Content: View>: View {
  @ViewBuilder let content: Content
  var body: some View {
    VStack(spacing: 0) {
      Divider()
      content.padding(.horizontal, 32).padding(.vertical, 18)
    }
    .frame(maxWidth: .infinity)
    .background(SettingsStyle.surface)
  }
}
