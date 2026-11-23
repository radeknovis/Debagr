import DebagrCore
import SwiftUI

public struct BridgeTopologyView: View {
  public enum Style: Sendable {
    case hero
    case compact
  }

  public let style: Style
  public let config: DebagrConfig
  public let snapshot: BridgeStateSnapshot
  public let readiness: ReadinessReport?
  public let isChecking: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(
    style: Style,
    config: DebagrConfig,
    snapshot: BridgeStateSnapshot,
    readiness: ReadinessReport?,
    isChecking: Bool
  ) {
    self.style = style
    self.config = config
    self.snapshot = snapshot
    self.readiness = readiness
    self.isChecking = isChecking
  }

  public var body: some View {
    let verdict = DeviceStatusVerdict.resolve(
      config: config,
      snapshot: snapshot,
      readiness: readiness,
      isChecking: isChecking
    )

    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !shouldAnimate)) { context in
      let phase =
        shouldAnimate
        ? -CGFloat(
          (context.date.timeIntervalSinceReferenceDate * 24).truncatingRemainder(dividingBy: 20))
        : 0

      Group {
        if style == .hero {
          ViewThatFits(in: .horizontal) {
            horizontalTopology(verdict: verdict, phase: phase)
            compactFallbackSummary(verdict: verdict)
          }
        } else {
          horizontalTopology(verdict: verdict, phase: phase)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityRouteSummary(verdict: verdict))
  }

  private func horizontalTopology(verdict: DeviceStatusVerdict, phase: CGFloat) -> some View {
    HStack(spacing: style == .hero ? 12 : 8) {
      nodeView(
        symbol: "desktopcomputer",
        title: "This Builder",
        subtitle: style == .hero ? "Pairing & Signing" : nil,
        tint: .primary,
        badgeSymbol: nil,
        badgeColor: nil
      )

      routeSegment(
        label: leftSegmentLabel,
        tone: leftSegmentTone,
        broken: snapshot.state == .vpnUnavailable,
        animated: shouldAnimate && snapshot.state != .vpnUnavailable,
        phase: phase
      )

      middleHopView(verdict: verdict)

      routeSegment(
        label: rightSegmentLabel,
        tone: verdict.tone,
        broken: snapshot.state == .deviceOffline || snapshot.state == .error,
        animated: shouldAnimate && snapshot.state != .deviceOffline && snapshot.state != .error,
        phase: phase
      )

      deviceNodeView(verdict: verdict)
    }
  }

  private func compactFallbackSummary(verdict: DeviceStatusVerdict) -> some View {
    let deviceName = config.managedDevice?.displayName ?? "iPhone / iPad"
    return HStack(spacing: 10) {
      Image(systemName: verdict.heroSymbol)
        .font(.title3)
        .foregroundStyle(verdict.tone.color)
      VStack(alignment: .leading, spacing: 2) {
        Text("This Builder → \(leftSegmentLabel) → \(deviceName)")
          .font(.callout.weight(.semibold))
          .lineLimit(1)
        Text("\(verdict.pillLabel) • \(rightSegmentLabel)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(8)
  }

  private var shouldAnimate: Bool {
    !reduceMotion
      && (snapshot.state == .bridgingActive || snapshot.state == .probingVPN || isChecking)
  }

  private var leftSegmentTone: StatusTone {
    switch snapshot.state {
    case .vpnUnavailable: .offline
    case .nativeLocalStandby: .local
    case .bridgingActive: .ready
    case .deviceOffline, .error: .attention
    case .probingVPN: .probing
    case .paused, .unconfigured: .idle
    }
  }

  private var leftSegmentLabel: String {
    if snapshot.state == .nativeLocalStandby {
      return snapshot.nativeTransport == .wired ? "USB" : "Wi-Fi"
    }
    if snapshot.state == .vpnUnavailable {
      return "VPN Down"
    }
    return config.managedDevice?.vpn.provider.displayName ?? "VPN"
  }

  private var rightSegmentLabel: String {
    switch snapshot.state {
    case .nativeLocalStandby:
      return snapshot.nativeTransport == .wired ? "Direct" : "Local"
    case .deviceOffline:
      return "No Reply"
    case .vpnUnavailable:
      return "Blocked"
    case .paused:
      return "Paused"
    case .probingVPN:
      return "Probing"
    case .bridgingActive:
      return "Port \(config.managedDevice?.vpn.lockdownPort ?? 62078)"
    case .unconfigured:
      return "Not Set"
    case .error:
      return "Error"
    }
  }

  private var middleSymbol: String {
    switch snapshot.state {
    case .nativeLocalStandby:
      snapshot.nativeTransport == .wired ? "cable.connector" : "wifi"
    case .vpnUnavailable, .deviceOffline, .error:
      "bolt.slash.fill"
    case .paused:
      "pause.circle"
    default:
      "lock.shield.fill"
    }
  }

  private func middleHopView(verdict: DeviceStatusVerdict) -> some View {
    VStack(spacing: 3) {
      ZStack {
        Circle()
          .fill(verdict.tone.color.opacity(0.14))
          .frame(width: style == .hero ? 34 : 24, height: style == .hero ? 34 : 24)
        Image(systemName: middleSymbol)
          .font(style == .hero ? .callout.weight(.semibold) : .caption2.weight(.semibold))
          .foregroundStyle(verdict.tone.color)
      }
      if style == .hero {
        Text(snapshot.state == .nativeLocalStandby ? "Native" : "Tunnel")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func deviceNodeView(verdict: DeviceStatusVerdict) -> some View {
    let device = config.managedDevice
    let symbol = device?.platform == .iPadOS ? "ipad" : "iphone"
    let title = device?.displayName ?? "iPhone / iPad"

    let subtitle: String?
    if style == .hero {
      switch snapshot.state {
      case .deviceOffline, .vpnUnavailable, .error, .paused:
        subtitle = verdict.pillLabel
      default:
        subtitle = DebagrFormatters.humanLockState(readiness?.lockState)
      }
    } else {
      subtitle = nil
    }

    return nodeView(
      symbol: symbol,
      title: title,
      subtitle: subtitle,
      tint: device == nil ? .secondary : verdict.tone.color,
      badgeSymbol: verdict.deviceBadgeSymbol,
      badgeColor: verdict.deviceBadgeColor
    )
  }

  private func nodeView(
    symbol: String,
    title: String,
    subtitle: String?,
    tint: Color,
    badgeSymbol: String?,
    badgeColor: Color?
  ) -> some View {
    VStack(spacing: style == .hero ? 5 : 2) {
      ZStack(alignment: .bottomTrailing) {
        RoundedRectangle(cornerRadius: style == .hero ? 11 : 8, style: .continuous)
          .fill(Color.primary.opacity(0.06))
          .frame(width: style == .hero ? 46 : 32, height: style == .hero ? 46 : 32)
          .overlay(
            RoundedRectangle(cornerRadius: style == .hero ? 11 : 8, style: .continuous)
              .strokeBorder(tint.opacity(0.35), lineWidth: 1)
          )

        Image(systemName: symbol)
          .font(style == .hero ? .title3 : .callout)
          .foregroundStyle(tint)
          .frame(width: style == .hero ? 46 : 32, height: style == .hero ? 46 : 32)

        if let badgeSymbol, let badgeColor {
          Image(systemName: badgeSymbol)
            .font(.system(size: style == .hero ? 11 : 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(3)
            .background(badgeColor, in: Circle())
            .offset(x: 4, y: 4)
        }
      }

      if style == .hero {
        Text(title)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
          .truncationMode(.tail)
        if let subtitle {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
    .frame(width: style == .hero ? 104 : 36)
  }

  private func routeSegment(
    label: String,
    tone: StatusTone,
    broken: Bool,
    animated: Bool,
    phase: CGFloat
  ) -> some View {
    VStack(spacing: 3) {
      GeometryReader { geo in
        Path { path in
          let y = geo.size.height / 2
          path.move(to: CGPoint(x: 0, y: y))
          path.addLine(to: CGPoint(x: geo.size.width, y: y))
        }
        .stroke(
          broken ? Color.red.opacity(0.65) : tone.color.opacity(0.75),
          style: StrokeStyle(
            lineWidth: style == .hero ? 2.5 : 2,
            lineCap: .round,
            dash: broken || animated || tone == .idle ? [5, 5] : [],
            dashPhase: animated ? phase : 0
          )
        )
      }
      .frame(height: 10)

      if style == .hero {
        Text(label)
          .font(.caption2.weight(.medium))
          .foregroundStyle(broken ? .red : .secondary)
          .lineLimit(1)
      }
    }
    .frame(minWidth: style == .hero ? 58 : 26, maxWidth: .infinity)
  }

  private func accessibilityRouteSummary(verdict: DeviceStatusVerdict) -> String {
    let deviceName = config.managedDevice?.displayName ?? "no configured device"
    return "Route from This Builder via \(leftSegmentLabel) to \(deviceName): \(verdict.heroTitle)"
  }
}
