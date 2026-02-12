// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CarrierWaveCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "CarrierWaveCore",
            targets: ["CarrierWaveCore"]
        ),
        .executable(
            name: "lofi-cli",
            targets: ["LoFiCLI"]
        ),
    ],
    targets: [
        .target(
            name: "CarrierWaveCore"
        ),
        .executableTarget(
            name: "LoFiCLI",
            dependencies: ["CarrierWaveCore"]
        ),
        .testTarget(
            name: "CarrierWaveCoreTests",
            dependencies: ["CarrierWaveCore"]
        ),
    ]
)
