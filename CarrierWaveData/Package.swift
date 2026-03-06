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
    ],
    targets: [
        .target(
            name: "CarrierWaveData",
            dependencies: [
                .product(name: "CarrierWaveCore", package: "CarrierWaveCore"),
            ]
        ),
        .testTarget(
            name: "CarrierWaveDataTests",
            dependencies: ["CarrierWaveData"]
        ),
    ]
)
