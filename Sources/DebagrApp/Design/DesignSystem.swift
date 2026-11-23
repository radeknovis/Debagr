import DebagrCore
import SwiftUI

public enum StatusTone: Sendable, Equatable {
  case ready
  case local
  case probing
  case attention
  case offline
  case idle

  public var color: Color {
    switch self {
    case .ready: .green
    case .local: .teal
    case .probing: .accentColor
    case .attention: .orange
    case .offline: .red
    case .idle: .secondary
    }
  }

  public var symbolName: String {
    switch self {
    case .ready: "checkmark.circle.fill"
    case .local: "cable.connector"
    case .probing: "antenna.radiowaves.left.and.right"
    case .attention: "exclamationmark.triangle.fill"
    case .offline: "wifi.slash"
    case .idle: "pause.circle.fill"
    }
  }
}

public struct DeviceStatusVerdict: Sendable, Equatable {
  public let tone: StatusTone
  public let pillLabel: String
  public let heroTitle: String
  public let heroSymbol: String
  public let menuBarSymbol: String
  public let deviceBadgeSymbol: String?
  public let deviceBadgeColor: Color?

  public static func resolve(
    config: DebagrConfig,
    snapshot: BridgeStateSnapshot,
    readiness: ReadinessReport?,
    isChecking: Bool
  ) -> DeviceStatusVerdict {
    guard config.managedDevice != nil else {
      return DeviceStatusVerdict(
        tone: .idle,
        pillLabel: "Not Configured",
        heroTitle: "No Device Configured",
        heroSymbol: "iphone.slash",
        menuBarSymbol: "iphone.slash",
        deviceBadgeSymbol: nil,
        deviceBadgeColor: nil
      )
    }

    if isChecking || snapshot.state == .probingVPN {
      return DeviceStatusVerdict(
        tone: .probing,
        pillLabel: "Checking",
        heroTitle: "Checking Device & VPN Route…",
        heroSymbol: "antenna.radiowaves.left.and.right",
        menuBarSymbol: "iphone.gen3.radiowaves.left.and.right",
        deviceBadgeSymbol: nil,
        deviceBadgeColor: nil
      )
    }

    // Current route failures and pause states always take strict precedence over cached readiness.
    switch snapshot.state {
    case .unconfigured:
      return DeviceStatusVerdict(
        tone: .idle,
        pillLabel: "Not Configured",
        heroTitle: "No Device Configured",
        heroSymbol: "iphone.slash",
        menuBarSymbol: "iphone.slash",
        deviceBadgeSymbol: nil,
        deviceBadgeColor: nil
      )

    case .paused:
      return DeviceStatusVerdict(
        tone: .idle,
        pillLabel: "Paused",
        heroTitle: "Wireless Bridge Paused",
        heroSymbol: "pause.circle.fill",
        menuBarSymbol: "pause.circle",
        deviceBadgeSymbol: "pause.fill",
        deviceBadgeColor: .secondary
      )

    case .vpnUnavailable:
      return DeviceStatusVerdict(
        tone: .offline,
        pillLabel: "VPN Offline",
        heroTitle: "VPN Interface Offline",
        heroSymbol: "exclamationmark.triangle.fill",
        menuBarSymbol: "exclamationmark.triangle",
        deviceBadgeSymbol: "wifi.slash",
        deviceBadgeColor: .red
      )

    case .deviceOffline:
      return DeviceStatusVerdict(
        tone: .offline,
        pillLabel: "Offline",
        heroTitle: "Device Unreachable Over VPN",
        heroSymbol: "wifi.slash",
        menuBarSymbol: "exclamationmark.triangle",
        deviceBadgeSymbol: "wifi.slash",
        deviceBadgeColor: .red
      )

    case .error:
      return DeviceStatusVerdict(
        tone: .offline,
        pillLabel: "Bridge Error",
        heroTitle: "Wireless Bridge Error",
        heroSymbol: "exclamationmark.octagon.fill",
        menuBarSymbol: "exclamationmark.triangle",
        deviceBadgeSymbol: "exclamationmark",
        deviceBadgeColor: .red
      )

    case .nativeLocalStandby, .bridgingActive:
      if let readiness {
        if readiness.ready {
          let isLocal = snapshot.state == .nativeLocalStandby
          return DeviceStatusVerdict(
            tone: .ready,
            pillLabel: isLocal ? "Ready (Local)" : "Ready",
            heroTitle: "Ready to Deploy",
            heroSymbol: "checkmark.circle.fill",
            menuBarSymbol: isLocal
              ? "cable.connector" : "iphone.gen3.radiowaves.left.and.right",
            deviceBadgeSymbol: "checkmark.circle.fill",
            deviceBadgeColor: .green
          )
        }
        if readiness.lockState.blocksForegroundLaunch {
          return DeviceStatusVerdict(
            tone: .attention,
            pillLabel: "Device Locked",
            heroTitle: "Device Locked — Unlock to Launch",
            heroSymbol: "lock.iphone",
            menuBarSymbol: "lock.iphone",
            deviceBadgeSymbol: "lock.fill",
            deviceBadgeColor: .orange
          )
        }
        return DeviceStatusVerdict(
          tone: .attention,
          pillLabel: "Action Needed",
          heroTitle: readiness.blockers.first?.message ?? "Device Not Ready",
          heroSymbol: "exclamationmark.triangle.fill",
          menuBarSymbol: "exclamationmark.triangle",
          deviceBadgeSymbol: "exclamationmark",
          deviceBadgeColor: .orange
        )
      }

      if snapshot.state == .nativeLocalStandby {
        return DeviceStatusVerdict(
          tone: .local,
          pillLabel: "Local · Unchecked",
          heroTitle: "Native Local Link · Device Unchecked",
          heroSymbol: "cable.connector",
          menuBarSymbol: "cable.connector",
          deviceBadgeSymbol: nil,
          deviceBadgeColor: nil
        )
      }

      return DeviceStatusVerdict(
        tone: .local,
        pillLabel: "Bridge Active",
        heroTitle: "Bridge Active · Device Unchecked",
        heroSymbol: "antenna.radiowaves.left.and.right",
        menuBarSymbol: "iphone.gen3.radiowaves.left.and.right",
        deviceBadgeSymbol: nil,
        deviceBadgeColor: nil
      )

    case .probingVPN:
      return DeviceStatusVerdict(
        tone: .probing,
        pillLabel: "Checking",
        heroTitle: "Probing VPN Endpoint…",
        heroSymbol: "antenna.radiowaves.left.and.right",
        menuBarSymbol: "iphone.gen3.radiowaves.left.and.right",
        deviceBadgeSymbol: nil,
        deviceBadgeColor: nil
      )
    }
  }
}

public enum DesignTokens {
  public static let maxContentWidth: CGFloat = 780
  public static let cardRadius: CGFloat = 12
  public static let cardPadding: CGFloat = 16
  public static let pagePadding: CGFloat = 24
  public static let controlHeight: CGFloat = 32
  public static let compactControlHeight: CGFloat = 26
  public static let controlRadius: CGFloat = 8
  public static let compactControlRadius: CGFloat = 6
  public static let containerRadius: CGFloat = 10
}

public enum DebagrFormatters {
  public static func humanLockState(_ state: LockState?) -> String {
    switch state {
    case .unlocked: "Unlocked"
    case .locked: "Locked"
    case .passcodeRequired: "Passcode Required"
    case .unknown, .none: "Unknown"
    }
  }

  public static func humanOutcome(_ outcome: DeploymentOutcome) -> String {
    switch outcome {
    case .succeeded: "Succeeded"
    case .partialSuccessLaunchFailed: "Installed · Launch Failed"
    case .uncertainTimeout: "Outcome Unknown"
    case .failed: "Failed"
    }
  }

  public static func humanOperation(_ op: DeploymentOperation) -> String {
    switch op {
    case .deploy: "Deploy"
    case .install: "Install"
    case .launch: "Launch"
    }
  }

  public static func humanDuration(ms: Int) -> String {
    if ms < 1000 {
      return "\(ms) ms"
    }
    let totalSeconds = Double(ms) / 1000.0
    if totalSeconds < 60 {
      return String(format: "%.1fs", totalSeconds)
    }
    let minutes = Int(totalSeconds) / 60
    let rem = Int(totalSeconds) % 60
    return "\(minutes)m \(rem)s"
  }

  public static func relativeTimestamp(from date: Date?, now: Date = Date()) -> String {
    guard let date else { return "Never" }
    let delta = Int(max(0, now.timeIntervalSince(date)))
    if delta < 5 { return "Just now" }
    if delta < 60 { return "\(delta)s ago" }
    let minutes = delta / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    return "\(hours / 24)d ago"
  }

  public static func humanCheckTitle(_ raw: String) -> String {
    switch raw {
    case "target_device_selection": "Target Profile"
    case "coredevice_presence": "CoreDevice Link"
    case "device_eligibility": "Paired Hardware"
    case "developer_mode": "Developer Mode"
    case "device_lock_state": "Screen Lock"
    default:
      raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }

  public static func formatHostPort(host: String, port: UInt16) -> String {
    if host.contains(":") && !host.hasPrefix("[") {
      return "[\(host)]:\(port)"
    }
    return "\(host):\(port)"
  }

  public static func shortenedHomePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
      return "~" + path.dropFirst(home.count)
    }
    return path
  }

  public static func parseTCPPort(_ raw: String) -> UInt16? {
    PortValidation.parseTCPPort(raw)
  }

  public static func shellSingleQuote(_ value: String) -> String {
    ShellFormatting.singleQuote(value)
  }

  /// Quotes the host when needed and quotes the entire remote command as a single local shell
  /// argument so spaces inside remote paths survive both local shell and remote `sh -c` parsing.
  public static func formatRemoteSSHCommand(host: String, remoteCommand: String) -> String {
    ShellFormatting.formatRemoteSSHCommand(host: host, remoteCommand: remoteCommand)
  }
}
