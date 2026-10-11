import Darwin
import Foundation

enum CLIError: LocalizedError {
  case missingValue(String)
  case unknownOption(String)
  case missingPeer
  case missingRemotePort
  case missingDevice
  case deployOptionRequiresApp(String)
  case invalidPort(String)
  case invalidTimeout(String)
  case discoveryTimedOut
  case remotePortMismatch(discovered: UInt16, requested: UInt16)
  case invalidDirectDeviceOptions
  case conflictingCommands

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
    case .missingDevice:
      return "Provide --device <UDID> when deploying an app."
    case .deployOptionRequiresApp(let option):
      return "\(option) requires --deploy-app <path>."
    case .invalidPort(let value):
      return "Invalid port: \(value)."
    case .invalidTimeout(let value):
      return "Invalid timeout: \(value)."
    case .discoveryTimedOut:
      return "No physical iPhone or iPad was found by devicectl or Bonjour before the timeout."
    case .remotePortMismatch(let discovered, let requested):
      return "Captured RemotePairing port \(discovered), but --remote-port requested \(requested)."
    case .invalidDirectDeviceOptions:
      return
        "Use --capture-device-profile with --peer and --bonjour-host, or --direct-device with --peer and a captured --profile. These modes cannot be combined with deployment, discovery, menu-bar, or relay options."
    case .conflictingCommands:
      return
        "Select one command. --json supports --devices, --status, --diagnose, --configure, or --deploy-app."
    }
  }
}

struct CommandLineOptions {
  var peerName: String?
  var remotePort: UInt16?
  var bonjourName: String?
  var bonjourHost: String?
  var interfaceName: String
  var forwardRemote: Bool
  var profileURL: URL
  var watchTunnels: Bool
  var discover: Bool
  var menuBar: Bool
  var deployAppURL: URL?
  var deviceIdentifier: String?
  var launchAfterInstall: Bool
  var timeout: TimeInterval
  var allowLANClients: Bool
  var showHelp: Bool
  var captureDeviceProfile: Bool = false
  var directDevice: Bool = false
  var agentCommand: String?
  var json: Bool = false

  static func parse(_ arguments: [String]) throws -> CommandLineOptions {
    var peerName: String?
    var remotePort: UInt16?
    var bonjourName: String?
    var bonjourHost: String?
    var interfaceName = "auto"
    var forwardRemote = false
    var profileURL = ProfileStore.defaultStore.url
    var watchTunnels = false
    var discover = false
    var menuBar = false
    var deployAppURL: URL?
    var deviceIdentifier: String?
    var launchAfterInstall = false
    var timeout: TimeInterval = 5
    var allowLANClients = false
    var showHelp = false
    var captureDeviceProfile = false
    var directDevice = false
    var agentCommand: String?
    var json = false

    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "-h", "--help":
        showHelp = true
      case "--discover":
        discover = true
      case "--capture-device-profile":
        captureDeviceProfile = true
      case "--direct-device":
        directDevice = true
      case "--menu-bar":
        menuBar = true
      case "--devices", "--status", "--diagnose", "--configure":
        guard agentCommand == nil else { throw CLIError.conflictingCommands }
        agentCommand = String(argument.dropFirst(2))
      case "--json":
        json = true
      case "--deploy-app":
        deployAppURL = expandedURL(
          try requiredValue(for: argument, arguments: arguments, index: &index))
      case "--device":
        deviceIdentifier = try requiredValue(for: argument, arguments: arguments, index: &index)
      case "--launch":
        launchAfterInstall = true
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
      case "--bonjour-host":
        bonjourHost = try requiredValue(for: argument, arguments: arguments, index: &index)
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

    if captureDeviceProfile || directDevice {
      guard !(captureDeviceProfile && directDevice),
        peerName?.isEmpty == false,
        !captureDeviceProfile || bonjourHost?.isEmpty == false,
        !forwardRemote, !watchTunnels, !allowLANClients, !menuBar, !discover,
        deployAppURL == nil, deviceIdentifier == nil, !launchAfterInstall,
        remotePort == nil, bonjourName == nil, agentCommand == nil, !json
      else { throw CLIError.invalidDirectDeviceOptions }
    }

    if deployAppURL == nil {
      if deviceIdentifier != nil && agentCommand == nil {
        throw CLIError.deployOptionRequiresApp("--device")
      }
      if launchAfterInstall {
        throw CLIError.deployOptionRequiresApp("--launch")
      }
    } else if deviceIdentifier == nil {
      throw CLIError.missingDevice
    }

    if agentCommand != nil {
      guard deployAppURL == nil, !discover, !menuBar, !forwardRemote, !watchTunnels,
        !allowLANClients, remotePort == nil, bonjourName == nil, !launchAfterInstall
      else { throw CLIError.conflictingCommands }
      if agentCommand != "devices" && deviceIdentifier == nil { throw CLIError.missingDevice }
      if agentCommand == "devices" && deviceIdentifier != nil { throw CLIError.conflictingCommands }
      if agentCommand == "configure" && peerName == nil { throw CLIError.missingPeer }
      if agentCommand != "configure"
        && (peerName != nil || bonjourHost != nil || arguments.contains("--profile"))
      {
        throw CLIError.conflictingCommands
      }
    }
    if deployAppURL != nil {
      guard !discover, !menuBar, !forwardRemote, !watchTunnels, peerName == nil,
        bonjourName == nil, bonjourHost == nil, remotePort == nil, !allowLANClients
      else { throw CLIError.conflictingCommands }
    }
    if json && agentCommand == nil && deployAppURL == nil && !showHelp {
      throw CLIError.conflictingCommands
    }

    return CommandLineOptions(
      peerName: peerName,
      remotePort: remotePort,
      bonjourName: bonjourName,
      bonjourHost: bonjourHost,
      interfaceName: interfaceName,
      forwardRemote: forwardRemote,
      profileURL: profileURL,
      watchTunnels: watchTunnels,
      discover: discover,
      menuBar: menuBar,
      deployAppURL: deployAppURL,
      deviceIdentifier: deviceIdentifier,
      launchAfterInstall: launchAfterInstall,
      timeout: timeout,
      allowLANClients: allowLANClients,
      showHelp: showHelp,
      captureDeviceProfile: captureDeviceProfile,
      directDevice: directDevice,
      agentCommand: agentCommand,
      json: json
    )
  }

  private static func requiredValue(
    for option: String,
    arguments: [String],
    index: inout Int
  ) throws -> String {
    index += 1
    guard index < arguments.count, !arguments[index].isEmpty, !arguments[index].hasPrefix("--")
    else {
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

final class DebagrApplication: ApplicationLifecycle {
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
        bonjourTXT: matchingProfile?.bonjourTXT ?? [:],
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
        localIP: binding.ipv4Address,
        txt: profile.bonjourTXT
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
  private let queue = DispatchQueue(label: "debagr.signal-handler")
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

func runTargetDeviceDiscovery(timeout: TimeInterval) throws {
  let capture = BonjourCapture()
  let semaphore = DispatchSemaphore(value: 0)
  let result = LockedValue<[BonjourDevice]>([])
  let pairedMacNodeID = "local:\(ProcessInfo.processInfo.hostName)"
  let coreDevices = (try? CoreDeviceInventory.load(pairedMacNodeID: pairedMacNodeID)) ?? []
  var didStartCapture = false

  do {
    try capture.startZoneCaptureAll { devices in
      result.set(devices)
    }
    didStartCapture = true
  } catch  where coreDevices.isEmpty {
    throw error
  }

  if didStartCapture {
    // Let the capture window collect every complete PTR/SRV/TXT group. A
    // Bonjour browser can deliver different devices at different times, so
    // completing on the first callback would make multi-device discovery
    // nondeterministically incomplete.
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + timeout + 1)
    capture.stop()
  }

  var registry = TargetDeviceRegistry()
  for device in coreDevices {
    registry.merge(device)
  }
  for service in result.get() {
    registry.merge(
      TargetDevice(
        identity: .provisional(pairedMacNodeID: pairedMacNodeID, service: service),
        displayName: service.suggestedDisplayName,
        kind: .inferred(from: service),
        service: service,
        status: .visible
      )
    )
  }

  let devices = registry.orderedDevices
  guard !devices.isEmpty else {
    throw CLIError.discoveryTimedOut
  }

  print("Target Devices found: \(devices.count)")
  for device in devices {
    print("- \(device.kind.displayName) — \(device.displayName)")
    print("  Status: \(device.status.displayName)")
    print("  Identifier: \(device.identity.value.replacingOccurrences(of: "bonjour:", with: ""))")
    if let service = device.service {
      print("  SRV endpoint: \(service.hostName):\(service.port)")
      print("  TXT records captured: \(service.txt.count) (values intentionally not logged)")
    }
  }
}

func writeError(_ message: String) {
  guard let data = (message + "\n").data(using: .utf8) else { return }
  FileHandle.standardError.write(data)
}

func printUsage() {
  print(
    """
    Usage:
      debagr --devices --json
      debagr --status --device <UDID> --timeout 30 --json
      debagr --diagnose --device <UDID> --json
      debagr --configure --device <UDID> --peer <iPhone-hostname> --bonjour-host <local-host> [--json]
      debagr --capture-device-profile --peer <iPhone-hostname> --bonjour-host <local-host> --profile <path>
      debagr --direct-device --peer <iPhone-hostname> --profile <path>
      debagr --deploy-app <path> --device <UDID> [--launch] [--json]
      debagr --peer <tailscale-hostname> --remote-port <port> [options]
      debagr --forward-remote --peer <tailscale-hostname> [options]
      debagr --discover [--timeout <seconds>]
      debagr --menu-bar

    Options:
      --devices             List stable Apple device IDs and saved configuration; not a readiness check
      --status              Verify trusted connectivity and unlocked state, retrying until --timeout
      --diagnose            Same verified check, with recovery instructions on failure
      --configure           Save one remote device, capturing Bonjour or importing --profile
      --json                Emit one versioned JSON result on stdout; failures have nonzero exit codes
      --capture-device-profile Capture the local Target Device service before roaming
      --direct-device       Proxy the captured service and tunnel ports to the Target Device's Tailscale IP
      --deploy-app <path>   Install a signed device .app from this paired Mac
      --device <UDID>       Explicit paired Target Device for deployment
      --launch              Launch the app after a confirmed installation
      --bonjour-name <name>  Local _remotepairing._tcp instance name
      --bonjour-host <host>  Forward only the captured Bonjour host (remote mode)
      --interface <name>     Interface to bind (default: auto — active Wi-Fi or Ethernet)
      --forward-remote       Forward from this Mac's Tailscale IP to local Bonjour
      --profile <path>      JSON profile (default: ~/.config/debagr/device-profile.json)
      --watch-tunnels       Watch remotepairingd and add TCP/UDP tunnel relays
      --allow-lan           Allow clients other than this Mac's en0 address
      --menu-bar            Run the automatic multi-device menu-bar inventory
      --help                Show this help

    The relay destination is always the explicitly selected online Tailscale
    peer's 100.64.0.0/10 IPv4 address. Bonjour data is never used as a
    destination host or port.
    """
  )
}

var runningApplication: (any ApplicationLifecycle)?
let rawArguments = Array(CommandLine.arguments.dropFirst())
var operation = "arguments"
atexit {
  runningApplication?.stop()
}

do {
  let options = try CommandLineOptions.parse(rawArguments)
  operation = options.agentCommand ?? (options.deployAppURL != nil ? "deploy" : "command")
  if options.showHelp {
    printUsage()
    exit(EXIT_SUCCESS)
  }

  if options.agentCommand != nil {
    try AgentCLI.run(options)
    exit(EXIT_SUCCESS)
  }

  if options.captureDeviceProfile {
    try DirectDeviceApplication.captureProfile(options: options)
    exit(EXIT_SUCCESS)
  }

  if options.discover {
    try runTargetDeviceDiscovery(timeout: options.timeout)
    exit(EXIT_SUCCESS)
  }

  if let appURL = options.deployAppURL {
    guard let deviceIdentifier = options.deviceIdentifier else {
      throw CLIError.missingDevice
    }
    let result = try DeviceDeployer().deploy(
      appURL: appURL,
      deviceIdentifier: deviceIdentifier,
      launch: options.launchAfterInstall
    )
    do { try DeploymentReceipt.record(result, deviceIdentifier: deviceIdentifier) } catch {
      writeError("Deployment succeeded, but its local history could not be saved.")
    }
    if options.json {
      AgentCLI.emit(
        [
          "state": result.launched ? "installed_and_launched" : "installed",
          "deviceIdentifier": deviceIdentifier, "bundleIdentifier": result.bundleIdentifier,
          "installed": true, "launched": result.launched,
        ], operation: "deploy", options: options)
    } else {
      print(
        result.launched
          ? "Installed and launched \(result.bundleIdentifier)."
          : "Installed \(result.bundleIdentifier)."
      )
    }
    exit(EXIT_SUCCESS)
  }

  if !options.directDevice
    && (options.menuBar
      || (rawArguments.isEmpty && Bundle.main.bundleIdentifier == "com.debagr.app"))
  {
    runMenuBarApplication()
    exit(EXIT_SUCCESS)
  }

  let application: any ApplicationLifecycle
  if options.directDevice {
    application = DirectDeviceApplication(options: options)
  } else if options.forwardRemote {
    application = RemoteForwarderApplication(options: options)
  } else {
    application = DebagrApplication(options: options)
  }
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
  if rawArguments.contains("--json") {
    let failure = AgentCLI.failure(error, operation: operation)
    AgentCLI.writeJSON(failure.object)
    exit(failure.exitCode)
  }
  writeError("Error: \(error.localizedDescription)")
  if error is CLIError {
    printUsage()
  }
  exit(EXIT_FAILURE)
}
