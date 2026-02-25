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
            name: "CFT8",
            path: "Sources/CFT8",
            publicHeadersPath: "include",
            cSettings: [
                .define("HAVE_STPCPY"),
                .headerSearchPath("."),
            ]
        ),
        .target(
            name: "CarrierWaveCore",
            dependencies: ["CFT8"]
        ),
        .executableTarget(
            name: "LoFiCLI",
            dependencies: ["CarrierWaveCore"]
        ),
        .testTarget(
            name: "CarrierWaveCoreTests",
            dependencies: ["CarrierWaveCore"],
            resources: [
                .copy("Resources/ft8-samples"),
            ]
        ),
    ]
)
