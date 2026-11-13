// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CarrierWaveData",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "CarrierWaveData",
            targets: ["CarrierWaveData"]
        ),
    ],
    dependencies: [
        .package(path: "../CarrierWaveCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "CarrierWaveData",
            dependencies: [
                .product(name: "CarrierWaveCore", package: "CarrierWaveCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [
                .copy("Resources/RadioCommands"),
                .copy("Resources/macro-opcodes"),
                .copy("Resources/band-plans"),
                .copy("Resources/macro-step-schema.json"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "CarrierWaveDataTests",
            dependencies: ["CarrierWaveData"],
            resources: [
                .process("Macros/Fixtures"),
            ]
        ),
    ]
)
