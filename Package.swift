// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LdmMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LdmMac",
            path: "Sources/LdmMac"
        )
    ]
)
