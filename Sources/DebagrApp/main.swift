import DebagrBridge
import DebagrCLI
import DebagrCore
import DebagrExperimental
import DebagrMCP
import Foundation
import os

private func sanitizedArguments(from raw: [String]) -> [String] {
  var filtered: [String] = []
  var skipNext = false
  for arg in raw.dropFirst() {
    if skipNext {
      skipNext = false
      continue
    }
    if arg.hasPrefix("-psn_") {
      continue
    }
    if arg == "-NSDocumentRevisionsDebugMode" || arg == "-AppleLanguages" || arg == "-AppleLocale" {
      skipNext = true
      continue
    }
    filtered.append(arg)
  }
  return filtered
}

private func runBlocking<T: Sendable>(_ operation: @Sendable @escaping () async -> T) -> T {
  let semaphore = DispatchSemaphore(value: 0)
  let box = OSAllocatedUnfairLock<T?>(initialState: nil)
  Task.detached {
    let result = await operation()
    box.withLock { $0 = result }
    semaphore.signal()
  }
  semaphore.wait()
  return box.withLock { $0! }
}

let args = sanitizedArguments(from: CommandLine.arguments)

if args.isEmpty || args == ["--gui"] {
  DebagrGUIApp.main()
} else if args.first == "mcp" {
  runBlocking {
    let supervisor = WirelessBridgeSupervisor()
    let coordinator = DeploymentCoordinator(bridgeEnsurer: supervisor)
    let registry = MCPToolRegistry(coordinator: coordinator)
    let server = MCPStdioServer(registry: registry)
    await server.run()
    await supervisor.stop(persistState: false)
  }
  Foundation.exit(0)
} else {
  let exitCode = runBlocking {
    let supervisor = WirelessBridgeSupervisor()
    let coordinator = DeploymentCoordinator(bridgeEnsurer: supervisor)
    let runner = CLIRunner(
      coordinator: coordinator,
      supervisor: supervisor,
      experimentalHandler: LiveExperimentalCLIHandler()
    )
    let code = await runner.run(arguments: args)
    await supervisor.stop(persistState: false)
    return code
  }
  Foundation.exit(exitCode)
}
