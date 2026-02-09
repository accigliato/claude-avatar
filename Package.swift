// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeAvatar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeAvatar",
            path: "Sources/ClaudeAvatar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
