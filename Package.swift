// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeNein",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ClaudeNein", targets: ["ClaudeNein"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "ClaudeNein",
            path: "ClaudeNein",
            exclude: ["Info.plist", "ClaudeNein.entitlements"],
            resources: [
                .process("Assets.xcassets"),
                .process("Model.xcdatamodeld")
            ]
        ),
        .testTarget(
            name: "ClaudeNeinTests",
            dependencies: [
                "ClaudeNein",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "ClaudeNeinTests",
            resources: [
                .copy("TestData")
            ]
        )
    ]
)
