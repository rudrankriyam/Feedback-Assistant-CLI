// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "xcfb",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "xcfb", targets: ["xcfb"])
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.7.0")
    ],
    targets: [
        .target(
            name: "XCFBCore",
            dependencies: [
                "XCFBNativeAutomation",
                .product(name: "BigInt", package: "BigInt"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Security")
            ]
        ),
        .target(name: "XCFBNativeAutomation"),
        .executableTarget(
            name: "xcfb",
            dependencies: ["XCFBCore"]
        ),
        .testTarget(
            name: "XCFBTests",
            dependencies: ["XCFBCore"]
        )
    ]
)
