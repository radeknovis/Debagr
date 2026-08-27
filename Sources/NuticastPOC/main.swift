import Darwin
import Foundation

enum CLIError: LocalizedError {
  case missingValue(String)
  case unknownOption(String)
  case missingPeer
  case missingRemotePort
  case invalidPort(String)
  case invalidTimeout(String)
  case discoveryTimedOut
  case remotePortMismatch(discovered: UInt16, requested: UInt16)

  var errorDescription: String? {
    switch self {
    case .missingValue(let option):
      return "Missing value for \(option)."
    case .unknownOption(let option):
      return "Unknown option: \(option)."
    case .missingPeer:
      return "An explicit peer selection is required: --peer <hostname>."
    case .missingRemotePort:
      return "Provide --remote-port <port> initially, or use a profile containing remotePort."
    case .invalidPort(let value):
      return "Invalid port: \(value)."
    case .invalidTimeout(let value):
      return "Invalid timeout: \(value)."
    case .discoveryTimedOut:
      return "No _remotepairing._tcp service was captured before the timeout."
    case .remotePortMismatch(let discovered, let requested):
      return "Captured RemotePairing port \(discovered), but --remote-port requested \(requested)."
    }
  }
}

struct CommandLineOptions {
  var peerName: String?
  var remotePort: UInt16?
  var bonjourName: String?
  var interfaceName: String
  var forwardRemote: Bool
  var profileURL: URL
  var watchTunnels: Bool
  var discover: Bool
  var timeout: TimeInterval
  var allowLANClients: Bool
  var showHelp: Bool

  static func parse(_ arguments: [String]) throws -> CommandLineOptions {
    var peerName: String?
    var remotePort: UInt16?
    var bonjourName: String?
    var interfaceName = "en0"
    var forwardRemote = false
    var profileURL = ProfileStore.defaultStore.url
    var watchTunnels = false
    var discover = false
    var timeout: TimeInterval = 5
    var allowLANClients = false
    var showHelp = false

    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "-h", "--help":
        showHelp = true
      case "--discover":
        discover = true
      case "--watch-tunnels":
        watchTunnels = true
      case "--allow-lan":
        allowLANClients = true
      case "--forward-remote":
        forwardRemote = true
      case "--peer":
        peerName = try requiredValue(for: argument, arguments: arguments, index: &index)
      case "--remote-port":
        let value = try requiredValue(for: argument, arguments: arguments, index: &index)
        remotePort = try parsePort(value)
      case "--bonjour-name":
        bonjourName = try requiredValue(for: argument, arguments: arguments, index: &index)
      case "--interface":
        interfaceName = try requiredValue(for: argument, arguments: arguments, index: &index)
      case "--profile":
        let value = try requiredValue(for: argument, arguments: arguments, index: &index)
        profileURL = expandedURL(value)
      case "--timeout":
        let value = try requiredValue(for: argument, arguments: arguments, index: &index)
        guard let parsed = TimeInterval(value), parsed > 0, parsed <= 60 else {
          throw CLIError.invalidTimeout(value)
        }
        timeout = parsed
      default:
        throw CLIError.unknownOption(argument)
      }
      index += 1
    }

    return CommandLineOptions(
      peerName: peerName,
      remotePort: remotePort,
      bonjourName: bonjourName,
      interfaceName: interfaceName,
      forwardRemote: forwardRemote,
      profileURL: profileURL,
      watchTunnels: watchTunnels,
      discover: discover,
      timeout: timeout,
      allowLANClients: allowLANClients,
      showHelp: showHelp
    )
  }

  private static func requiredValue(
    for option: String,
    arguments: [String],
    index: inout Int
  ) throws -> String {
    index += 1
    guard index < arguments.count, !arguments[index].isEmpty else {
      throw CLIError.missingValue(option)
    }
    return arguments[index]
  }

  private static func parsePort(_ value: String) throws -> UInt16 {
    guard let parsed = UInt32(value), parsed > 0, parsed <= 65_535 else {
      throw CLIError.invalidPort(value)
    }
    return UInt16(parsed)
  }

  private static func expandedURL(_ value: String) -> URL {
    if value == "~" {
      return FileManager.default.homeDirectoryForCurrentUser
    }
    if value.hasPrefix("~/") {
      return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(String(value.dropFirst(2)))
    }
    return URL(fileURLWithPath: value)
  }
}

protocol ApplicationLifecycle: AnyObject {
  func start() throws
  func stop()
}

final class NuticastApplication: ApplicationLifecycle {
  private let options: CommandLineOptions
  private let profileStore: ProfileStore

  private var relayManager: RelayManager?
  private var proxy: BonjourProxy?
  private var bonjourBrowser: BonjourCapture?
  private var tunnelWatcher: TunnelPortWatcher?
  private var controlRemotePort: UInt16?
  private let shutdownLock = NSLock()
  private var hasStopped = false

  init(options: CommandLineOptions) {
    self.options = options
    self.profileStore = ProfileStore(url: options.profileURL)
  }

  func start() throws {
    do {
      let binding = try NetworkSupport.resolveInterface(named: options.interfaceName)
      let selectedPeerName = try requirePeerName()
      let peer = try TailscaleClient().selectPeer(named: selectedPeerName)
      let previousProfile = try profileStore.load()
      let matchingProfile = previousProfile?.peerIP == peer.ipAddress ? previousProfile : nil

      let remotePort = options.remotePort ?? matchingProfile?.remotePort
      guard let remotePort else { throw CLIError.missingRemotePort }

      let bonjourName =
        options.bonjourName
        ?? matchingProfile?.bonjourName
        ?? "\(peer.hostname)-RemotePairing"
      let localPortRange = matchingProfile?.localPortRange ?? DeviceProfile.defaultLocalPortRange
      let profile = DeviceProfile(
        bonjourName: bonjourName,
        provider: "tailscale",
        peerIP: peer.ipAddress,
        remotePort: remotePort,
        localPortRange: localPortRange
      )
      try profileStore.save(profile)

      let manager = try RelayManager(
        bindInterface: binding.networkInterface,
        remoteHost: peer.ipAddress,
        localInterfaceAddress: binding.ipv4Address,
        localPortRange: profile.localPortBounds,
        allowLANClients: options.allowLANClients
      )
      relayManager = manager
      controlRemotePort = remotePort

      if options.allowLANClients {
        print("Warning: relay listeners accept LAN clients on en0.")
      } else {
        print("Relay access policy: local Mac address only (\(binding.ipv4Address)).")
      }

      let localPort = try startControlRelay(manager: manager, remotePort: remotePort)
      print(
        "Selected Tailscale peer: \(peer.hostname) (\(peer.dnsName.isEmpty ? "no DNS name" : peer.dnsName))"
      )
      print("RemotePairing destination: \(peer.ipAddress):\(remotePort)")
      print("TCP and UDP relays ready on \(binding.ipv4Address):\(localPort).")

      let proxy = try BonjourProxy(
        interfaceName: binding.name,
        instanceName: bonjourName,
        localPort: localPort,
        localHost: localBonjourHostName(),
        localIP: binding.ipv4Address
      )
      try proxy.start()
      self.proxy = proxy
      print(
        "Bonjour proxy registration started: \(bonjourName).\(BonjourZoneParser.serviceType).local")

      let browser = BonjourCapture()
      try browser.startBrowsing { instance in
        if instance.contains(bonjourName) {
          print("Bonjour proxy visible to dns-sd: \(bonjourName)")
        }
      }
      bonjourBrowser = browser

      if options.watchTunnels {
        let watcher = TunnelPortWatcher()
        try watcher.start { [weak self] remoteTunnelPort in
          self?.startTunnelRelay(remotePort: remoteTunnelPort)
        }
        tunnelWatcher = watcher
        print("Watching remotepairingd for tunnel endpoints.")
      }

      print("Run: xcrun devicectl list devices")
    } catch {
      stop()
      throw error
    }
  }

  func stop() {
    shutdownLock.lock()
    guard !hasStopped else {
      shutdownLock.unlock()
      return
    }
    hasStopped = true
    shutdownLock.unlock()

    // Preserve the ownership/lifecycle boundary: stop log watching first,
    // then only our dns-sd children, and close relay sockets last.
    tunnelWatcher?.stop()
    tunnelWatcher = nil
    bonjourBrowser?.stop()
    bonjourBrowser = nil
    proxy?.stop()
    proxy = nil
    relayManager?.stop()
    relayManager = nil
  }

  private func requirePeerName() throws -> String {
    guard let peerName = options.peerName, !peerName.isEmpty else {
      throw CLIError.missingPeer
    }
    return peerName
  }

  private func startControlRelay(manager: RelayManager, remotePort: UInt16) throws -> UInt16 {
    let semaphore = DispatchSemaphore(value: 0)
    let result = LockedValue<Result<UInt16, Error>?>(nil)
    manager.start(remotePort: remotePort) { value in
      result.set(value)
      semaphore.signal()
    }

    guard semaphore.wait(timeout: .now() + 30) == .success else {
      manager.stop()
      throw RelayError.startupTimedOut
    }

    guard let value = result.get() else {
      throw RelayError.startupTimedOut
    }
    return try value.get()
  }

  private func startTunnelRelay(remotePort: UInt16) {
    if remotePort == controlRemotePort {
      return
    }

    relayManager?.start(remotePort: remotePort) { result in
      switch result {
      case .success(let localPort):
        print("Tunnel relay ready: local \(localPort) -> selected peer:\(remotePort) (TCP/UDP)")
      case .failure(let error):
        writeError(
          "Unable to start tunnel relay for remote port \(remotePort): \(error.localizedDescription)"
        )
      }
    }
  }
}

final class SignalHandler {
  private let queue = DispatchQueue(label: "nuticast-poc.signal-handler")
  private var sources: [DispatchSourceSignal] = []

  init(onSignal: @escaping () -> Void) {
    for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
      Darwin.signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
      source.setEventHandler(handler: onSignal)
      source.resume()
      sources.append(source)
    }
  }

  func stop() {
    for source in sources {
      source.cancel()
    }
    sources.removeAll()
  }

  deinit {
    stop()
  }
}

func runBonjourDiscovery(timeout: TimeInterval) throws {
  let capture = BonjourCapture()
  let semaphore = DispatchSemaphore(value: 0)
  let result = LockedValue<BonjourDevice?>(nil)

  try capture.startZoneCapture { device in
    result.set(device)
    capture.stop()
    semaphore.signal()
  }

  guard semaphore.wait(timeout: .now() + timeout) == .success else {
    capture.stop()
    throw CLIError.discoveryTimedOut
  }

  guard let device = result.get() else {
    throw CLIError.discoveryTimedOut
  }

  print("Bonjour service: \(device.instanceName) \(device.serviceType)")
  print("SRV endpoint: \(device.hostName):\(device.port)")
  print("TXT records captured: \(device.txt.count) (values intentionally not logged)")
}

func writeError(_ message: String) {
  guard let data = (message + "\n").data(using: .utf8) else { return }
  FileHandle.standardError.write(data)
}

func printUsage() {
  print(
    """
    Usage:
      nuticast-poc --peer <tailscale-hostname> --remote-port <port> [options]
      nuticast-poc --forward-remote --peer <tailscale-hostname> [options]
      nuticast-poc --discover [--timeout <seconds>]

    Options:
      --bonjour-name <name>  Local _remotepairing._tcp instance name
      --interface <name>     Interface to bind (default: en0)
      --forward-remote       Forward from this Mac's Tailscale IP to local Bonjour
      --profile <path>      JSON profile (default: ~/.config/nuticast-poc/device-profile.json)
      --watch-tunnels       Watch remotepairingd and add TCP/UDP tunnel relays
      --allow-lan           Allow clients other than this Mac's en0 address
      --help                Show this help

    The relay destination is always the explicitly selected online Tailscale
    peer's 100.64.0.0/10 IPv4 address. Bonjour data is never used as a
    destination host or port.
    """
  )
}

var runningApplication: (any ApplicationLifecycle)?
atexit {
  runningApplication?.stop()
}

do {
  let options = try CommandLineOptions.parse(Array(CommandLine.arguments.dropFirst()))
  if options.showHelp {
    printUsage()
    exit(EXIT_SUCCESS)
  }

  if options.discover {
    try runBonjourDiscovery(timeout: options.timeout)
    exit(EXIT_SUCCESS)
  }

  let application: any ApplicationLifecycle =
    options.forwardRemote
    ? RemoteForwarderApplication(options: options)
    : NuticastApplication(options: options)
  runningApplication = application
  let stopped = DispatchSemaphore(value: 0)
  let signals = SignalHandler {
    application.stop()
    stopped.signal()
  }

  try application.start()
  stopped.wait()
  signals.stop()
  application.stop()
} catch {
  runningApplication?.stop()
  writeError("Error: \(error.localizedDescription)")
  printUsage()
  exit(EXIT_FAILURE)
}
