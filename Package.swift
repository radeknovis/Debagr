// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Debagr",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "nuticast-poc",
            targets: ["NuticastPOC"]
        )
    ],
    targets: [
        .executableTarget(
            name: "NuticastPOC"
        ),
        .testTarget(
            name: "NuticastPOCTests",
            dependencies: ["NuticastPOC"]
        )
    ]
)
