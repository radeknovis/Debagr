// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Debagr",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "DebagrCore", targets: ["DebagrCore"]),
    .library(name: "DebagrBridge", targets: ["DebagrBridge"]),
    .library(name: "DebagrCLI", targets: ["DebagrCLI"]),
    .library(name: "DebagrMCP", targets: ["DebagrMCP"]),
    .library(name: "DebagrExperimental", targets: ["DebagrExperimental"]),
    .executable(name: "Debagr", targets: ["DebagrApp"]),
  ],
  targets: [
    .target(
      name: "DebagrCore",
      dependencies: []
    ),
    .target(
      name: "DebagrBridge",
      dependencies: ["DebagrCore"]
    ),
    .target(
      name: "DebagrCLI",
      dependencies: ["DebagrCore", "DebagrBridge"]
    ),
    .target(
      name: "DebagrMCP",
      dependencies: ["DebagrCore", "DebagrBridge"]
    ),
    .target(
      name: "DebagrExperimental",
      dependencies: ["DebagrCore", "DebagrBridge", "DebagrCLI"]
    ),
    .executableTarget(
      name: "DebagrApp",
      dependencies: [
        "DebagrCore",
        "DebagrBridge",
        "DebagrCLI",
        "DebagrMCP",
        "DebagrExperimental",
      ]
    ),
    .testTarget(
      name: "DebagrCoreTests",
      dependencies: ["DebagrCore"]
    ),
    .testTarget(
      name: "DebagrBridgeTests",
      dependencies: ["DebagrBridge", "DebagrCore"]
    ),
    .testTarget(
      name: "DebagrCLIMCPTests",
      dependencies: ["DebagrCLI", "DebagrMCP", "DebagrBridge", "DebagrCore"]
    ),
    .testTarget(
      name: "DebagrExperimentalTests",
      dependencies: ["DebagrExperimental", "DebagrCLI", "DebagrBridge", "DebagrCore"]
    ),
  ]
)
