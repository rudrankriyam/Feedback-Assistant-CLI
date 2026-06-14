// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RelatoKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RelatoKit", targets: ["RelatoKit"]),
        .executable(name: "relato", targets: ["relato"])
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.7.0")
    ],
    targets: [
        .target(
            name: "RelatoKit",
            dependencies: [
                "RelatoNativeAutomation",
                .product(name: "BigInt", package: "BigInt"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Security")
            ]
        ),
        .target(name: "RelatoNativeAutomation"),
        .executableTarget(
            name: "relato",
            dependencies: ["RelatoKit"]
        ),
        .testTarget(
            name: "RelatoKitTests",
            dependencies: ["RelatoKit"]
        )
    ]
)
