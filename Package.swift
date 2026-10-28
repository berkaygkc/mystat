// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Mystat",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "MystatCore"),
        .target(name: "MystatUI", dependencies: ["MystatCore"]),
        .executableTarget(name: "mystat", dependencies: ["MystatCore", "MystatUI"]),
        .testTarget(name: "MystatCoreTests", dependencies: ["MystatCore"]),
        .testTarget(name: "MystatUITests", dependencies: ["MystatUI"]),
    ]
)
