// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "washi",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "washi",
            path: "Sources/washi"
        )
    ]
)
