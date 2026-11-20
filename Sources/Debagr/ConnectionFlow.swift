import SwiftUI

enum ConnectionPath: String, CaseIterable, Identifiable {
  case existing, usb, usbIP
  var id: Self { self }
  var title: String {
    switch self {
    case .existing: return "Use existing pairing"
    case .usb: return "USB via Mac"
    case .usbIP: return "Pair via USB/IP"
    }
  }
  var situation: String {
    switch self {
    case .existing: return "Device already trusts the Builder"
    case .usb: return "Paired device on a cable"
    case .usbIP: return "Device needs a new pairing"
    }
  }
  var subtitle: String {
    switch self {
    case .existing: return "Deploy from the paired Mac over your VPN."
    case .usb: return "Deploy through another Mac’s USB cable."
    case .usbIP: return "Share the cable from a second Mac to start Apple pairing."
    }
  }
  var symbol: String { self == .existing ? "link" : "cable.connector" }

  static let experimentalLabel = "Experimental"
  var accessibilityLabel: String {
    [situation, title, self == .existing ? nil : Self.experimentalLabel, subtitle]
      .compactMap { $0 }.joined(separator: ". ")
  }

  static var usbRequirements: String {
    "Requires existing Xcode pairing with this Builder, a phone connected to another Mac, Tailscale and trusted SSH access. Start the cable service bridge from the CLI."
  }

}

struct ExperimentalBadge: View {
  var body: some View {
    Text(ConnectionPath.experimentalLabel)
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(Color.primary)
      .padding(.horizontal, 6).padding(.vertical, 2)
      .background(Color.orange.opacity(0.25), in: Capsule())
  }
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
    case .checking: return "Checking device connection"
    case .ready: return "Device connection verified"
    case .attention: return "Connection needs attention"
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
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        ForEach([ConnectionPath.existing, .usbIP]) { path in
          Button {
            selection = path
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Image(systemName: path.symbol).font(.title3)
                  .foregroundStyle(selection == path ? SettingsStyle.accent : .primary)
                Spacer()
                if path != .existing { ExperimentalBadge() }
              }
              Text(path.situation).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
              Text(path.title).font(.system(size: 11, weight: .medium))
              Text(path.subtitle).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.primary)
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
          .accessibilityLabel(path.accessibilityLabel)
          .accessibilityAddTraits(selection == path ? .isSelected : [])
        }
      }
      Button {
        selection = .usb
      } label: {
        Label("USB via Mac · keep a paired device on a cable (Experimental)", systemImage: "cable.connector")
      }
      .buttonStyle(.link)
      .accessibilityLabel(ConnectionPath.usb.accessibilityLabel)
      .accessibilityAddTraits(selection == .usb ? .isSelected : [])
    }
    .accessibilityElement(children: .contain).accessibilityLabel("Pairing path")
  }
}

/// The diagram describes topology, not live connection status.
struct ConnectionDiagram: View {
  let path: ConnectionPath
  var deviceName = "Your iPhone"
  var usbLinkLabel = "CoreDevice over VPN"

  var topologyDescription: String {
    path == .existing
      ? "Connection diagram. Your device connects over a private VPN to the Builder that already owns its Apple pairing. No Client Mac is required."
      : "Connection diagram. Your iPhone connects by USB cable to a cable Mac. The cable Mac forwards device services to the already paired Builder using \(usbLinkLabel). Keep the USB cable connected."
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text(path == .existing ? "THE EVERYDAY CONNECTION" : "THE CABLE SERVICE BRIDGE")
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
          DiagramEndpoint(kind: .laptop, title: "Cable Mac", detail: "Forwards services")
          DiagramLink(label: usbLinkLabel, wireless: true)
        }
        DiagramEndpoint(
          kind: .server, title: "Builder",
          detail: path == .existing ? "Builds, signs & deploys" : "Uses existing pairing")
      }
      Label(
        path == .existing
          ? "Existing trust · the Builder stays paired"
          : "Existing trust · keep the USB cable connected",
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
          "Pair the device directly with this Builder first: connect it, unlock it, approve Trust, and enable Developer Mode. If the Builder is elsewhere, choose Pair via USB/IP to share the device from the Mac with the cable."
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
