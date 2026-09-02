// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Slicky",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Slicky",
            path: "Sources/Slicky"
        )
    ]
)
