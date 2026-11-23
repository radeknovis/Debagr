import AppKit
import DebagrCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Segmented Control

private struct SegmentAnchorKey: PreferenceKey {
  static let defaultValue: [Int: Anchor<CGRect>] = [:]

  static func reduce(
    value: inout [Int: Anchor<CGRect>],
    nextValue: () -> [Int: Anchor<CGRect>]
  ) {
    value.merge(nextValue()) { _, rhs in rhs }
  }
}

public struct DebagrSegmentedControl<Option: Hashable>: View {
  private let label: String
  private let options: [Option]
  @Binding private var selection: Option
  private let title: (Option) -> String
  private let systemImage: ((Option) -> String?)?
  private let helpText: ((Option) -> String?)?
  private let equalWidth: Bool

  @State private var hoveredOption: Option?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isEnabled) private var isEnabled

  public init(
    _ label: String,
    selection: Binding<Option>,
    options: [Option],
    equalWidth: Bool = false,
    title: @escaping (Option) -> String,
    systemImage: ((Option) -> String?)? = nil,
    helpText: ((Option) -> String?)? = nil
  ) {
    self.label = label
    self._selection = selection
    self.options = options
    self.equalWidth = equalWidth
    self.title = title
    self.systemImage = systemImage
    self.helpText = helpText
  }

  public var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(options.enumerated()), id: \.offset) { index, option in
        segmentButton(index: index, option: option)
      }
    }
    .padding(3)
    .frame(minHeight: DesignTokens.controlHeight)
    .background {
      RoundedRectangle(cornerRadius: DesignTokens.containerRadius, style: .continuous)
        .fill(trackBackgroundColor)
    }
    .backgroundPreferenceValue(SegmentAnchorKey.self) { anchors in
      GeometryReader { proxy in
        if let selectedIndex = options.firstIndex(of: selection),
          let anchor = anchors[selectedIndex]
        {
          let rect = proxy[anchor]
          RoundedRectangle(
            cornerRadius: DesignTokens.controlRadius - 1,
            style: .continuous
          )
          .fill(Color(nsColor: .controlColor))
          .overlay(
            RoundedRectangle(
              cornerRadius: DesignTokens.controlRadius - 1,
              style: .continuous
            )
            .strokeBorder(selectedPillBorder, lineWidth: 1)
          )
          .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.08),
            radius: 2,
            x: 0,
            y: 1
          )
          .frame(width: rect.width, height: rect.height)
          .offset(x: rect.minX, y: rect.minY)
          .animation(
            reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.84),
            value: selection
          )
        }
      }
    }
    .overlay(
      RoundedRectangle(cornerRadius: DesignTokens.containerRadius, style: .continuous)
        .strokeBorder(trackBorderColor, lineWidth: 1)
    )
    .opacity(isEnabled ? 1.0 : 0.55)
    .focusable(isEnabled)
    .focusEffectDisabled(false)
    .contentShape(
      .focusEffect,
      RoundedRectangle(cornerRadius: DesignTokens.containerRadius, style: .continuous)
    )
    .onKeyPress(.leftArrow) {
      moveSelection(by: -1)
    }
    .onKeyPress(.rightArrow) {
      moveSelection(by: 1)
    }
    .onKeyPress(.home) {
      selectBoundary(first: true)
    }
    .onKeyPress(.end) {
      selectBoundary(first: false)
    }
    .onChange(of: isEnabled) { _, enabled in
      if !enabled {
        hoveredOption = nil
      }
    }
    .accessibilityRepresentation {
      Picker(label, selection: $selection) {
        ForEach(options, id: \.self) { option in
          Text(title(option)).tag(option)
        }
      }
      .pickerStyle(.segmented)
    }
  }

  @ViewBuilder
  private func segmentButton(index: Int, option: Option) -> some View {
    let isSelected = selection == option
    let isHovered = isEnabled && hoveredOption == option && !isSelected
    let iconName = systemImage?(option)
    let tip = helpText?(option)

    Button {
      guard isEnabled else { return }
      selection = option
    } label: {
      HStack(spacing: 5) {
        if let iconName {
          Image(systemName: iconName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        Text(title(option))
          .font(.subheadline.weight(isSelected ? .semibold : .medium))
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .foregroundStyle(isSelected ? .primary : (isHovered ? .primary : .secondary))
      .padding(.horizontal, 10)
      .frame(
        maxWidth: equalWidth ? .infinity : nil,
        minHeight: DesignTokens.controlHeight - 6
      )
      .contentShape(
        RoundedRectangle(cornerRadius: DesignTokens.controlRadius - 1, style: .continuous)
      )
      .background {
        if isHovered {
          RoundedRectangle(
            cornerRadius: DesignTokens.controlRadius - 1,
            style: .continuous
          )
          .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
        }
      }
    }
    .buttonStyle(.plain)
    .focusable(false)
    .anchorPreference(key: SegmentAnchorKey.self, value: .bounds) { anchor in
      [index: anchor]
    }
    .onHover { hovering in
      guard isEnabled else {
        hoveredOption = nil
        return
      }
      hoveredOption = hovering ? option : (hoveredOption == option ? nil : hoveredOption)
    }
    .modifier(OptionalHelpModifier(text: tip))
  }

  private func moveSelection(by delta: Int) -> KeyPress.Result {
    guard isEnabled, !options.isEmpty, let current = options.firstIndex(of: selection) else {
      return .ignored
    }
    let next = (current + delta + options.count) % options.count
    selection = options[next]
    return .handled
  }

  private func selectBoundary(first: Bool) -> KeyPress.Result {
    guard isEnabled else { return .ignored }
    guard let target = first ? options.first : options.last else {
      return .ignored
    }
    selection = target
    return .handled
  }

  private var trackBackgroundColor: Color {
    Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.055)
  }

  private var trackBorderColor: Color {
    Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.09)
  }

  private var selectedPillBorder: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.18)
      : Color.black.opacity(0.10)
  }
}

private struct OptionalHelpModifier: ViewModifier {
  let text: String?

  func body(content: Content) -> some View {
    if let text, !text.isEmpty {
      content.help(text)
    } else {
      content
    }
  }
}

// MARK: - Buttons

public enum DebagrControlTone: Sendable, Equatable {
  case neutral
  case accent
  case positive
  case warning
  case destructive

  public var color: Color {
    switch self {
    case .neutral: .secondary
    case .accent: .accentColor
    case .positive: StatusTone.ready.color
    case .warning: StatusTone.attention.color
    case .destructive: StatusTone.offline.color
    }
  }
}

public struct DebagrButtonLabel: View {
  public let title: String
  public let systemImage: String
  public let isLoading: Bool

  public init(title: String, systemImage: String, isLoading: Bool = false) {
    self.title = title
    self.systemImage = systemImage
    self.isLoading = isLoading
  }

  public var body: some View {
    HStack(spacing: 6) {
      ZStack {
        if isLoading {
          ProgressView()
            .controlSize(.small)
        } else {
          Image(systemName: systemImage)
            .font(.caption.weight(.semibold))
        }
      }
      .frame(width: 16, height: 16)
      Text(title)
    }
  }
}

public struct DebagrPrimaryButtonStyle: ButtonStyle {
  public var fullWidth: Bool
  public var compact: Bool
  public var isLoading: Bool
  public var tone: DebagrControlTone

  public init(
    fullWidth: Bool = false,
    compact: Bool = false,
    isLoading: Bool = false,
    tone: DebagrControlTone = .accent
  ) {
    self.fullWidth = fullWidth
    self.compact = compact
    self.isLoading = isLoading
    self.tone = tone
  }

  public func makeBody(configuration: Configuration) -> some View {
    PrimaryButtonBody(
      configuration: configuration,
      fullWidth: fullWidth,
      compact: compact,
      isLoading: isLoading,
      tone: tone
    )
  }

  private struct PrimaryButtonBody: View {
    let configuration: Configuration
    let fullWidth: Bool
    let compact: Bool
    let isLoading: Bool
    let tone: DebagrControlTone

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
      let radius = compact ? DesignTokens.compactControlRadius : DesignTokens.controlRadius
      let height = compact ? DesignTokens.compactControlHeight : DesignTokens.controlHeight
      let showDisabled = !isEnabled && !isLoading
      let interactive = isEnabled && !isLoading
      let baseColor = tone.color

      configuration.label
        .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
        .foregroundStyle(
          showDisabled ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.white)
        )
        .environment(\.colorScheme, showDisabled ? colorScheme : .dark)
        .padding(.horizontal, compact ? 11 : 14)
        .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
        .background {
          if showDisabled {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
              .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
          } else {
            ZStack {
              RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
              RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(baseColor)
              RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                  LinearGradient(
                    colors: [Color.white.opacity(0.16), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                  )
                )
              if isHovered && interactive {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                  .fill(Color.white.opacity(0.10))
              }
              if configuration.isPressed && interactive {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                  .fill(Color.black.opacity(0.15))
              }
            }
          }
        }
        .overlay(
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
              showDisabled
                ? Color.primary.opacity(0.08)
                : Color.white.opacity(colorScheme == .dark ? 0.22 : 0.28),
              lineWidth: 1
            )
        )
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .contentShape(
          .focusEffect,
          RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .allowsHitTesting(!isLoading)
        .onChange(of: interactive) { _, canInteract in
          if !canInteract {
            isHovered = false
          }
        }
        .onHover { hovering in
          guard interactive else {
            isHovered = false
            return
          }
          if reduceMotion {
            isHovered = hovering
          } else {
            withAnimation(.easeOut(duration: 0.12)) {
              isHovered = hovering
            }
          }
        }
    }
  }
}

public struct DebagrSecondaryButtonStyle: ButtonStyle {
  public var fullWidth: Bool
  public var compact: Bool
  public var isLoading: Bool
  public var tone: DebagrControlTone

  public init(
    fullWidth: Bool = false,
    compact: Bool = false,
    isLoading: Bool = false,
    tone: DebagrControlTone = .neutral
  ) {
    self.fullWidth = fullWidth
    self.compact = compact
    self.isLoading = isLoading
    self.tone = tone
  }

  public func makeBody(configuration: Configuration) -> some View {
    SecondaryButtonBody(
      configuration: configuration,
      fullWidth: fullWidth,
      compact: compact,
      isLoading: isLoading,
      tone: tone
    )
  }

  private struct SecondaryButtonBody: View {
    let configuration: Configuration
    let fullWidth: Bool
    let compact: Bool
    let isLoading: Bool
    let tone: DebagrControlTone

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
      let radius = compact ? DesignTokens.compactControlRadius : DesignTokens.controlRadius
      let height = compact ? DesignTokens.compactControlHeight : DesignTokens.controlHeight
      let showDisabled = !isEnabled && !isLoading
      let interactive = isEnabled && !isLoading
      let isTinted = tone != .neutral

      configuration.label
        .font((compact ? Font.caption : Font.subheadline).weight(.medium))
        .foregroundStyle(
          showDisabled
            ? AnyShapeStyle(Color.secondary)
            : (isTinted ? AnyShapeStyle(tone.color) : AnyShapeStyle(Color.primary))
        )
        .padding(.horizontal, compact ? 10 : 13)
        .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
        .background {
          ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
              .fill(
                showDisabled
                  ? Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04)
                  : Color(nsColor: .controlColor)
              )
            if isTinted && !showDisabled {
              RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tone.color.opacity(isHovered && interactive ? 0.16 : 0.10))
            } else if isHovered && interactive {
              RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
            }
            if configuration.isPressed && interactive {
              RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.09))
            }
          }
        }
        .overlay(
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
              borderColor(isTinted: isTinted, showDisabled: showDisabled, interactive: interactive),
              lineWidth: 1
            )
        )
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .contentShape(
          .focusEffect,
          RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .allowsHitTesting(!isLoading)
        .onChange(of: interactive) { _, canInteract in
          if !canInteract {
            isHovered = false
          }
        }
        .onHover { hovering in
          guard interactive else {
            isHovered = false
            return
          }
          if reduceMotion {
            isHovered = hovering
          } else {
            withAnimation(.easeOut(duration: 0.12)) {
              isHovered = hovering
            }
          }
        }
    }

    private func borderColor(isTinted: Bool, showDisabled: Bool, interactive: Bool) -> Color {
      if showDisabled {
        return Color.primary.opacity(0.08)
      }
      if isTinted {
        return tone.color.opacity(isHovered && interactive ? 0.42 : 0.25)
      }
      return Color.primary.opacity(
        isHovered && interactive ? 0.24 : (colorScheme == .dark ? 0.16 : 0.13)
      )
    }
  }
}

// MARK: - Text Field

public enum DebagrFieldValidation: Equatable, Sendable {
  case none
  case valid(String?)
  case warning(String)
  case invalid(String)

  var message: String? {
    switch self {
    case .none:
      return nil
    case .valid(let note):
      return note
    case .warning(let note), .invalid(let note):
      return note
    }
  }

  var iconName: String? {
    switch self {
    case .none:
      return nil
    case .valid:
      return "checkmark.circle.fill"
    case .warning:
      return "exclamationmark.triangle.fill"
    case .invalid:
      return "xmark.circle.fill"
    }
  }

  var tone: DebagrControlTone {
    switch self {
    case .none:
      return .neutral
    case .valid:
      return .positive
    case .warning:
      return .warning
    case .invalid:
      return .destructive
    }
  }
}

public struct DebagrTextField: View {
  private let label: String?
  @Binding private var text: String
  private let prompt: String
  private let monospaced: Bool
  private let leadingIcon: String?
  private let numericOnly: Bool
  private let maxLength: Int?
  private let validation: DebagrFieldValidation
  private let showClearButton: Bool
  private let acceptsFileDrop: Bool
  private let trailingActionIcon: String?
  private let trailingActionHelp: String?
  private let trailingAction: (() -> Void)?

  @FocusState private var isFocused: Bool
  @State private var isHovered = false
  @State private var isDropTargeted = false
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled

  public init(
    label: String? = nil,
    text: Binding<String>,
    prompt: String,
    monospaced: Bool = true,
    leadingIcon: String? = nil,
    numericOnly: Bool = false,
    maxLength: Int? = nil,
    validation: DebagrFieldValidation = .none,
    showClearButton: Bool = false,
    acceptsFileDrop: Bool = false,
    trailingActionIcon: String? = nil,
    trailingActionHelp: String? = nil,
    trailingAction: (() -> Void)? = nil
  ) {
    self.label = label
    self._text = text
    self.prompt = prompt
    self.monospaced = monospaced
    self.leadingIcon = leadingIcon
    self.numericOnly = numericOnly
    self.maxLength = maxLength
    self.validation = validation
    self.showClearButton = showClearButton
    self.acceptsFileDrop = acceptsFileDrop
    self.trailingActionIcon = trailingActionIcon
    self.trailingActionHelp = trailingActionHelp
    self.trailingAction = trailingAction
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if let label, !label.isEmpty {
        Text(label)
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      }

      fieldBox
        .modifier(
          OptionalFileDropModifier(
            enabled: acceptsFileDrop && isEnabled,
            isDropTargeted: $isDropTargeted
          ) { path in
            text = path
          }
        )

      if let note = validation.message, !note.isEmpty {
        Label(note, systemImage: validation.iconName ?? "info.circle")
          .font(.caption2)
          .foregroundStyle(validation.tone.color)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .opacity(isEnabled ? 1.0 : 0.6)
  }

  private var fieldBox: some View {
    let radius = DesignTokens.controlRadius
    let showClear = showClearButton && isEnabled && !text.isEmpty && (isFocused || isHovered)

    return HStack(spacing: 8) {
      if let leadingIcon {
        Image(systemName: leadingIcon)
          .font(.caption.weight(.semibold))
          .foregroundStyle(leadingIconColor)
          .frame(width: 14)
      }

      TextField(label ?? prompt, text: $text, prompt: Text(prompt))
        .textFieldStyle(.plain)
        .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
        .focused($isFocused)
        .disabled(!isEnabled)
        .onChange(of: text) { _, newValue in
          var filtered = newValue
          if numericOnly {
            let digitsOnly = filtered.filter { $0.isASCII && $0.isNumber }
            if digitsOnly != filtered {
              filtered = digitsOnly
            }
          }
          if let maxLength, filtered.count > maxLength {
            filtered = String(filtered.prefix(maxLength))
          }
          if filtered != newValue {
            text = filtered
          }
        }

      if showClear {
        FieldAccessoryButton(
          systemImage: "xmark.circle.fill",
          help: "Clear \(label ?? "field")",
          size: 20
        ) {
          text = ""
          isFocused = true
        }
      }

      if let validationIcon = validation.iconName {
        Image(systemName: validationIcon)
          .font(.caption.weight(.semibold))
          .foregroundStyle(validation.tone.color)
          .accessibilityHidden(true)
      }

      if let trailingActionIcon, let trailingAction {
        FieldAccessoryButton(
          systemImage: trailingActionIcon,
          help: trailingActionHelp ?? "Field action",
          size: 22,
          action: trailingAction
        )
        .disabled(!isEnabled)
      }
    }
    .padding(.horizontal, 10)
    .frame(minHeight: DesignTokens.controlHeight)
    .background(
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(Color(nsColor: .textBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .strokeBorder(borderColor, lineWidth: isFocused || isDropTargeted ? 1.5 : 1)
    )
    .overlay(
      RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
        .strokeBorder(
          isFocused || isDropTargeted ? focusRingColor.opacity(0.28) : Color.clear,
          lineWidth: 2
        )
        .padding(-2)
    )
    .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    .onTapGesture {
      if isEnabled {
        isFocused = true
      }
    }
    .onHover { hovering in
      guard isEnabled else {
        isHovered = false
        return
      }
      if reduceMotion {
        isHovered = hovering
      } else {
        withAnimation(.easeOut(duration: 0.12)) {
          isHovered = hovering
        }
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isFocused)
  }

  private var leadingIconColor: Color {
    if isFocused || isDropTargeted {
      return focusRingColor
    }
    if case .invalid = validation {
      return DebagrControlTone.destructive.color
    }
    return .secondary
  }

  private var focusRingColor: Color {
    if case .invalid = validation {
      return DebagrControlTone.destructive.color
    }
    return Color.accentColor
  }

  private var borderColor: Color {
    if isDropTargeted || isFocused {
      return focusRingColor
    }
    switch validation {
    case .invalid:
      return DebagrControlTone.destructive.color.opacity(0.65)
    case .warning:
      return DebagrControlTone.warning.color.opacity(0.55)
    case .valid:
      return DebagrControlTone.positive.color.opacity(0.45)
    case .none:
      if isHovered {
        return Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.22)
      }
      return Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.13)
    }
  }
}

private struct FieldAccessoryButton: View {
  let systemImage: String
  let help: String
  let size: CGFloat
  let action: () -> Void

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(isHovered ? .primary : .secondary)
        .frame(width: size, height: size)
        .background(
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(
              Color.primary.opacity(
                isHovered
                  ? (colorScheme == .dark ? 0.16 : 0.11)
                  : (colorScheme == .dark ? 0.09 : 0.05)
              )
            )
        )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
    .help(help)
    .accessibilityLabel(help)
  }
}

private struct OptionalFileDropModifier: ViewModifier {
  let enabled: Bool
  @Binding var isDropTargeted: Bool
  let onDropPath: (String) -> Void

  func body(content: Content) -> some View {
    if enabled {
      content.dropDestination(for: URL.self) { urls, _ in
        guard let url = urls.first, url.isFileURL else {
          return false
        }
        onDropPath(url.path)
        return true
      } isTargeted: { targeted in
        isDropTargeted = targeted
      }
    } else {
      content
    }
  }
}

// MARK: - File Picker Helper

@MainActor
public enum DebagrFilePicker {
  public enum ExecutablePickResult: Sendable, Equatable {
    case picked(String)
    case notExecutable(String)
    case cancelled
  }

  public static func pickApplicationBundle(
    title: String = "Select Builder App Bundle",
    initialPath: String? = nil
  ) async -> String? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.prompt = "Select App"
    panel.allowedContentTypes = [.applicationBundle]
    panel.treatsFilePackagesAsDirectories = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    configureInitialDirectory(on: panel, path: initialPath)

    let response = await present(panel)
    guard response == .OK, let url = panel.url else {
      return nil
    }
    return url.path
  }

  public static func pickExecutable(
    title: String = "Select Binary",
    initialPath: String? = nil
  ) async -> ExecutablePickResult {
    let panel = NSOpenPanel()
    panel.title = title
    panel.prompt = "Select Binary"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.showsHiddenFiles = true
    configureInitialDirectory(on: panel, path: initialPath)

    let response = await present(panel)
    guard response == .OK, let url = panel.url else {
      return .cancelled
    }
    guard FileManager.default.isExecutableFile(atPath: url.path) else {
      return .notExecutable(url.path)
    }
    return .picked(url.path)
  }

  private static func configureInitialDirectory(on panel: NSOpenPanel, path: String?) {
    guard let path, !path.isEmpty else { return }
    let expanded = (path as NSString).expandingTildeInPath
    panel.directoryURL = URL(fileURLWithPath: expanded).deletingLastPathComponent()
  }

  private static func present(_ panel: NSOpenPanel) async -> NSApplication.ModalResponse {
    if let window = NSApp.keyWindow {
      return await panel.beginSheetModal(for: window)
    }
    return panel.runModal()
  }
}

// MARK: - Terminal Command Field

public struct TerminalCommandField: View {
  public let code: String
  public let contextTag: String?
  public let syntax: TerminalSyntax
  public let showPromptGutter: Bool
  public let wrapLines: Bool?
  public let maxHeight: CGFloat?

  @State private var copiedCode: String?
  @State private var copyGeneration = 0
  @State private var highlightedLines: [AttributedString] = []
  @State private var highlightedFull = AttributedString()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  public init(
    code: String,
    contextTag: String? = nil,
    syntax: TerminalSyntax = .shell,
    showPromptGutter: Bool = true,
    wrapLines: Bool? = nil,
    maxHeight: CGFloat? = nil
  ) {
    self.code = code
    self.contextTag = contextTag
    self.syntax = syntax
    self.showPromptGutter = showPromptGutter
    self.wrapLines = wrapLines
    self.maxHeight = maxHeight
  }

  public var body: some View {
    let effectiveWrap = wrapLines ?? (syntax == .shell)
    let hasPlaceholders = (syntax == .shell) && TerminalTokenizer.containsShellPlaceholders(code)
    let isCopied = (copiedCode == code)
    let radius = DesignTokens.containerRadius

    VStack(alignment: .leading, spacing: 0) {
      headerBar(hasPlaceholders: hasPlaceholders, isCopied: isCopied)

      Rectangle()
        .fill(dividerColor)
        .frame(height: 1)

      commandBody(effectiveWrap: effectiveWrap)
    }
    .frame(maxHeight: maxHeight)
    .background(
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(surfaceColor)
    )
    .overlay(
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .strokeBorder(isCopied ? copiedBorderColor : borderColor, lineWidth: 1)
    )
    .onAppear {
      rebuildHighlight()
    }
    .onChange(of: code) { _, _ in
      copiedCode = nil
      rebuildHighlight()
    }
    .onChange(of: syntax) { _, _ in
      rebuildHighlight()
    }
    .onChange(of: colorScheme) { _, _ in
      rebuildHighlight()
    }
    .accessibilityElement(children: .contain)
  }

  private func headerBar(hasPlaceholders: Bool, isCopied: Bool) -> some View {
    HStack(spacing: 8) {
      Image(systemName: syntax == .shell ? "terminal" : "curlybraces")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(headerGlyphColor)

      Text(contextTag ?? "Terminal Command")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(headerTitleColor)
        .lineLimit(1)

      if let badge = syntax.badgeLabel {
        Text(badge)
          .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
          .foregroundStyle(badgeForegroundColor)
          .padding(.horizontal, 5)
          .padding(.vertical, 1.5)
          .background(
            Capsule()
              .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
          )
      }

      if hasPlaceholders {
        Label("Fill placeholders", systemImage: "exclamationmark.triangle.fill")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(StatusTone.attention.color)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            Capsule()
              .fill(StatusTone.attention.color.opacity(0.14))
          )
      }

      Spacer(minLength: 8)

      Button {
        copyToPasteboard()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            .font(.caption2.weight(.semibold))
          Text(isCopied ? "Copied" : (hasPlaceholders ? "Copy Template" : "Copy"))
            .font(.caption2.weight(.semibold))
        }
      }
      .buttonStyle(
        TerminalCopyButtonStyle(
          isCopied: isCopied,
          isTemplate: hasPlaceholders
        )
      )
      .help(
        hasPlaceholders
          ? "Contains <placeholder> tokens — replace them before running in Terminal"
          : "Copy to clipboard"
      )
      .accessibilityLabel(isCopied ? "Copied to clipboard" : "Copy \(contextTag ?? "command")")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(headerSurfaceColor)
    .clipShape(
      UnevenRoundedRectangle(
        topLeadingRadius: DesignTokens.containerRadius,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: DesignTokens.containerRadius,
        style: .continuous
      )
    )
  }

  @ViewBuilder
  private func commandBody(effectiveWrap: Bool) -> some View {
    let useLineGutters = (syntax == .shell && showPromptGutter)

    if effectiveWrap {
      if maxHeight != nil {
        ScrollView(.vertical, showsIndicators: true) {
          wrappedContent(useLineGutters: useLineGutters)
        }
      } else {
        wrappedContent(useLineGutters: useLineGutters)
      }
    } else {
      ScrollView(
        maxHeight != nil ? [.horizontal, .vertical] : .horizontal,
        showsIndicators: true
      ) {
        unwrappedContent(useLineGutters: useLineGutters)
      }
    }
  }

  @ViewBuilder
  private func wrappedContent(useLineGutters: Bool) -> some View {
    if useLineGutters {
      VStack(alignment: .leading, spacing: 5) {
        ForEach(Array(highlightedLines.enumerated()), id: \.offset) { _, lineAttr in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("$")
              .font(.system(size: 11.5, weight: .bold, design: .monospaced))
              .foregroundStyle(promptColor)
              .accessibilityHidden(true)

            Text(lineAttr)
              .font(.system(size: 11.5, design: .monospaced))
              .lineSpacing(3)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
    } else {
      Text(highlightedFull)
        .font(.system(size: 11.5, design: .monospaced))
        .lineSpacing(3)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
  }

  @ViewBuilder
  private func unwrappedContent(useLineGutters: Bool) -> some View {
    if useLineGutters {
      VStack(alignment: .leading, spacing: 5) {
        ForEach(Array(highlightedLines.enumerated()), id: \.offset) { _, lineAttr in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("$")
              .font(.system(size: 11.5, weight: .bold, design: .monospaced))
              .foregroundStyle(promptColor)
              .accessibilityHidden(true)

            Text(lineAttr)
              .font(.system(size: 11.5, design: .monospaced))
              .lineSpacing(3)
              .textSelection(.enabled)
              .fixedSize(horizontal: true, vertical: true)
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
    } else {
      Text(highlightedFull)
        .font(.system(size: 11.5, design: .monospaced))
        .lineSpacing(3)
        .textSelection(.enabled)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
  }

  private func copyToPasteboard() {
    let pb = NSPasteboard.general
    pb.clearContents()
    let wrote = pb.setString(code, forType: .string)
    guard wrote else { return }

    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)

    let targetCode = code
    copyGeneration += 1
    let currentGen = copyGeneration

    if reduceMotion {
      copiedCode = targetCode
    } else {
      withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
        copiedCode = targetCode
      }
    }

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.8))
      guard copyGeneration == currentGen, copiedCode == targetCode else { return }
      if reduceMotion {
        copiedCode = nil
      } else {
        withAnimation(.easeOut(duration: 0.18)) {
          copiedCode = nil
        }
      }
    }
  }

  private func rebuildHighlight() {
    let dark = (colorScheme == .dark)
    highlightedFull = renderAttributed(for: code, dark: dark)
    let rawLines = code.split(separator: "\n", omittingEmptySubsequences: false)
    highlightedLines = rawLines.map { renderAttributed(for: String($0), dark: dark) }
  }

  private func renderAttributed(for source: String, dark: Bool) -> AttributedString {
    let tokens = TerminalTokenizer.tokenize(source, syntax: syntax)
    var result = AttributedString()
    for token in tokens {
      var part = AttributedString(token.text)
      part.foregroundColor = color(for: token.kind, dark: dark)
      if token.kind == .command || token.kind == .key || token.kind == .placeholder {
        part.font = .system(size: 11.5, weight: .semibold, design: .monospaced)
      }
      result.append(part)
    }
    return result
  }

  private func color(for kind: TerminalTokenKind, dark: Bool) -> Color {
    switch kind {
    case .plain:
      return dark
        ? Color(red: 0.90, green: 0.93, blue: 0.96)
        : Color(red: 0.11, green: 0.12, blue: 0.14)
    case .command, .key:
      return dark
        ? Color(red: 0.47, green: 0.75, blue: 1.00)
        : Color(red: 0.02, green: 0.31, blue: 0.68)
    case .flag:
      return dark
        ? Color(red: 0.82, green: 0.66, blue: 1.00)
        : Color(red: 0.40, green: 0.22, blue: 0.73)
    case .string:
      return dark
        ? Color(red: 0.49, green: 0.90, blue: 0.56)
        : Color(red: 0.07, green: 0.39, blue: 0.16)
    case .numberOrEnv:
      return dark
        ? Color(red: 1.00, green: 0.65, blue: 0.34)
        : Color(red: 0.58, green: 0.22, blue: 0.00)
    case .placeholder:
      return dark
        ? Color(red: 0.98, green: 0.75, blue: 0.14)
        : Color(red: 0.71, green: 0.33, blue: 0.04)
    case .punctuation, .comment:
      return dark
        ? Color(red: 0.55, green: 0.58, blue: 0.65)
        : Color(red: 0.34, green: 0.38, blue: 0.42)
    }
  }

  private var surfaceColor: Color {
    colorScheme == .dark
      ? Color(red: 0.07, green: 0.08, blue: 0.105)
      : Color(red: 0.965, green: 0.97, blue: 0.98)
  }

  private var headerSurfaceColor: Color {
    colorScheme == .dark
      ? Color(red: 0.10, green: 0.115, blue: 0.145)
      : Color(red: 0.925, green: 0.935, blue: 0.955)
  }

  private var dividerColor: Color {
    Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08)
  }

  private var borderColor: Color {
    Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.12)
  }

  private var copiedBorderColor: Color {
    StatusTone.ready.color.opacity(0.65)
  }

  private var headerGlyphColor: Color {
    colorScheme == .dark
      ? Color(red: 0.47, green: 0.75, blue: 1.00)
      : Color.accentColor
  }

  private var headerTitleColor: Color {
    colorScheme == .dark
      ? Color(red: 0.84, green: 0.87, blue: 0.92)
      : Color(red: 0.20, green: 0.23, blue: 0.27)
  }

  private var badgeForegroundColor: Color {
    colorScheme == .dark
      ? Color(red: 0.62, green: 0.67, blue: 0.75)
      : Color(red: 0.34, green: 0.38, blue: 0.42)
  }

  private var promptColor: Color {
    colorScheme == .dark
      ? Color(red: 0.49, green: 0.90, blue: 0.56)
      : Color(red: 0.07, green: 0.39, blue: 0.16)
  }
}

private struct TerminalCopyButtonStyle: ButtonStyle {
  let isCopied: Bool
  let isTemplate: Bool

  @State private var isHovered = false
  @Environment(\.colorScheme) private var colorScheme

  func makeBody(configuration: Configuration) -> some View {
    let tint: Color =
      isCopied
      ? StatusTone.ready.color
      : (isTemplate ? StatusTone.attention.color : .primary)

    configuration.label
      .foregroundStyle(isCopied || isTemplate ? tint : .primary)
      .padding(.horizontal, 8)
      .padding(.vertical, 3.5)
      .background {
        Capsule()
          .fill(backgroundColor(isPressed: configuration.isPressed))
      }
      .overlay(
        Capsule()
          .strokeBorder(borderColor, lineWidth: 1)
      )
      .contentShape(Capsule())
      .onHover { hovering in
        isHovered = hovering
      }
  }

  private func backgroundColor(isPressed: Bool) -> Color {
    if isCopied {
      return StatusTone.ready.color.opacity(isPressed ? 0.25 : 0.16)
    }
    if isTemplate {
      return StatusTone.attention.color.opacity(isPressed ? 0.24 : (isHovered ? 0.18 : 0.12))
    }
    if isPressed {
      return Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.14)
    }
    return isHovered
      ? Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.09)
      : Color(nsColor: .controlColor).opacity(colorScheme == .dark ? 0.85 : 0.95)
  }

  private var borderColor: Color {
    if isCopied {
      return StatusTone.ready.color.opacity(0.55)
    }
    if isTemplate {
      return StatusTone.attention.color.opacity(isHovered ? 0.55 : 0.38)
    }
    return Color.primary.opacity(isHovered ? 0.24 : 0.14)
  }
}
