// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WorktreeBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "WorktreeBar",
            path: "WorktreeBar"
        )
    ]
)
