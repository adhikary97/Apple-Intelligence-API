// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppleIntelligenceChat",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AppleIntelligenceChat",
            targets: ["AppleIntelligenceChat"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "AppleIntelligenceChat",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Sources/AppleIntelligenceChat"
        ),
    ]
)

