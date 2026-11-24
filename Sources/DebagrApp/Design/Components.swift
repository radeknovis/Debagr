import AppKit
import SwiftUI

public struct SurfaceCard<Content: View>: View {
  private let padding: CGFloat
  private let content: Content

  public init(padding: CGFloat = DesignTokens.cardPadding, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  public var body: some View {
    content
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
          .fill(.quaternary.opacity(0.45))
      )
      .overlay(
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
          .strokeBorder(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 0.75)
      )
  }
}

public struct DebagrEmptyState<Actions: View>: View {
  public let symbolName: String
  public let title: String
  public let description: String
  private let hasActions: Bool
  private let actions: Actions

  public init(
    symbolName: String,
    title: String,
    description: String,
    @ViewBuilder actions: () -> Actions
  ) {
    self.symbolName = symbolName
    self.title = title
    self.description = description
    self.hasActions = true
    self.actions = actions()
  }

  public var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbolName)
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 48, height: 48)
        .background(
          Color.primary.opacity(0.06),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.75)
        )

      VStack(spacing: 5) {
        Text(title)
          .font(.headline)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.center)

        Text(description)
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 460)
      }

      if hasActions {
        HStack(spacing: 10) {
          actions
        }
        .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.horizontal, 16)
    .padding(.vertical, 20)
  }
}

extension DebagrEmptyState where Actions == EmptyView {
  public init(symbolName: String, title: String, description: String) {
    self.symbolName = symbolName
    self.title = title
    self.description = description
    self.hasActions = false
    self.actions = EmptyView()
  }
}

public struct RelativeTimeText: View {
  public let date: Date?
  public var prefix: String = ""

  public init(date: Date?, prefix: String = "") {
    self.date = date
    self.prefix = prefix
  }

  public var body: some View {
    TimelineView(.periodic(from: .now, by: 5)) { context in
      Text(prefix + DebagrFormatters.relativeTimestamp(from: date, now: context.date))
    }
  }
}

public struct StatusPill: View {
  public let tone: StatusTone
  public let symbolName: String
  public let label: String
  public var compact: Bool = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(
    tone: StatusTone,
    symbolName: String? = nil,
    label: String,
    compact: Bool = false
  ) {
    self.tone = tone
    self.symbolName = symbolName ?? tone.symbolName
    self.label = label
    self.compact = compact
  }

  public var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbolName)
        .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
        .foregroundStyle(tone.color)
        .symbolEffect(.pulse, options: .repeating, isActive: tone == .probing && !reduceMotion)
      Text(label)
        .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
    }
    .padding(.horizontal, compact ? 8 : 10)
    .padding(.vertical, compact ? 4 : 5)
    .background(tone.color.opacity(0.14), in: Capsule())
    .overlay(Capsule().strokeBorder(tone.color.opacity(0.35), lineWidth: 0.75))
    .accessibilityElement(children: .combine)
  }
}

public struct SelectableOptionCard<Content: View>: View {
  public let isSelected: Bool
  public let action: () -> Void
  private let content: Content

  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(
    isSelected: Bool,
    action: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) {
    self.isSelected = isSelected
    self.action = action
    self.content = content()
  }

  public var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
          .contentTransition(.symbolEffect(.replace))

        content
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(
            isSelected
              ? Color.accentColor.opacity(0.11)
              : (isHovered ? Color.primary.opacity(0.05) : Color.primary.opacity(0.02))
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(
            isSelected
              ? Color.accentColor
              : Color(nsColor: .separatorColor).opacity(isHovered ? 0.95 : 0.72),
            lineWidth: isSelected ? 1.5 : 0.75
          )
      )
    }
    .buttonStyle(.plain)
    .onHover { inside in
      isHovered = inside
    }
    .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isSelected)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

public struct DiagonalHatchBanner: View {
  public let title: String
  public let subtitle: String

  public init(title: String, subtitle: String) {
    self.title = title
    self.subtitle = subtitle
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "flask.fill")
        .font(.title2)
        .foregroundStyle(.orange)
        .padding(8)
        .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(title)
            .font(.headline)
          ExperimentalBadge()
        }
        Text(subtitle)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      ZStack {
        Color.orange.opacity(0.06)
        Canvas { context, size in
          let stripeSpacing: CGFloat = 14
          let stripeWidth: CGFloat = 5
          var x: CGFloat = -size.height
          while x < size.width + size.height {
            var path = Path()
            path.move(to: CGPoint(x: x, y: size.height))
            path.addLine(to: CGPoint(x: x + size.height, y: 0))
            path.addLine(to: CGPoint(x: x + size.height + stripeWidth, y: 0))
            path.addLine(to: CGPoint(x: x + stripeWidth, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(.orange.opacity(0.11)))
            x += stripeSpacing
          }
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
        .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
    )
  }
}

public struct ExperimentalBadge: View {
  public init() {}

  public var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(Color.orange)
        .frame(width: 6, height: 6)
      Text("Experimental")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.primary)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Color.orange.opacity(0.16), in: Capsule())
    .overlay(Capsule().strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.75))
  }
}

public struct InlineNotice: View {
  public let symbolName: String
  public let color: Color
  public let title: String
  public let message: String

  public init(symbolName: String, color: Color, title: String, message: String) {
    self.symbolName = symbolName
    self.color = color
    self.title = title
    self.message = message
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbolName)
        .foregroundStyle(color)
        .font(.body)
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.semibold))
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(color.opacity(0.28), lineWidth: 0.75)
    )
  }
}

public struct ExpandableErrorCard: View {
  public let message: String
  public let onDismiss: () -> Void
  @State private var expanded = false
  @State private var copied = false

  public init(message: String, onDismiss: @escaping () -> Void) {
    self.message = message
    self.onDismiss = onDismiss
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.octagon.fill")
          .foregroundStyle(.red)
        Text(message)
          .font(.callout)
          .lineLimit(expanded ? nil : 2)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: 6) {
          if message.count > 100 {
            Button(expanded ? "Less" : "Details") {
              withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            }
            .buttonStyle(DebagrSecondaryButtonStyle(compact: true))
          }
          Button(copied ? "Copied" : "Copy") {
            let pb = NSPasteboard.general
            pb.clearContents()
            let wrote = pb.setString(message, forType: .string)
            guard wrote else { return }
            copied = true
            Task { @MainActor in
              try? await Task.sleep(for: .seconds(1.4))
              copied = false
            }
          }
          .buttonStyle(DebagrSecondaryButtonStyle(compact: true))

          Button {
            onDismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.borderless)
          .help("Dismiss error")
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color.red.opacity(0.11))
    .overlay(Rectangle().fill(Color.red.opacity(0.3)).frame(height: 0.75), alignment: .bottom)
  }
}

public struct FloatingToastOverlay: View {
  public let message: String

  public init(message: String) {
    self.message = message
  }

  public var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
      Text(message)
        .font(.callout.weight(.medium))
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.75))
    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
  }
}
