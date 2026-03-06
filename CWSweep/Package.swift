// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CWSweep",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../CarrierWaveCore"),
        .package(path: "../CarrierWaveData"),
    ],
    targets: [
        .executableTarget(
            name: "CWSweep",
            dependencies: [
                .product(name: "CarrierWaveCore", package: "CarrierWaveCore"),
                .product(name: "CarrierWaveData", package: "CarrierWaveData"),
            ],
            path: "CWSweep",
            resources: [
                .copy("Resources/ContestTemplates"),
            ]
        ),
        .testTarget(
            name: "CWSweepTests",
            dependencies: ["CWSweep"],
            path: "CWSweepTests"
        ),
    ]
)
