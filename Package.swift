// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Debagr",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "debagr",
            targets: ["Debagr"]
        )
    ],
    targets: [
        .executableTarget(
            name: "USBIPProbe",
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("IOUSBHost")]
        ),
        .executableTarget(
            name: "Debagr"
        ),
        .testTarget(
            name: "DebagrTests",
            dependencies: ["Debagr"]
        )
    ]
)
