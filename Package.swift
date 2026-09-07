// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HZLAPaste",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HZLAPaste",
            path: "Sources/HZLAPaste",
            exclude: ["Info.plist", "AppIcon.icns"]
        )
    ]
)
