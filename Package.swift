// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Mystat",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "MystatCore"),
        .target(name: "MystatUI", dependencies: ["MystatCore"]),
        .target(name: "MystatProbes", dependencies: ["MystatCore"]),
        .target(name: "MystatLive", dependencies: ["MystatCore", "MystatProbes"]),
        .executableTarget(name: "mystat", dependencies: ["MystatCore", "MystatUI", "MystatLive"]),
        .testTarget(name: "MystatCoreTests", dependencies: ["MystatCore"]),
        .testTarget(name: "MystatUITests", dependencies: ["MystatUI"]),
        .testTarget(name: "MystatLiveTests", dependencies: ["MystatLive"]),
        .testTarget(name: "MystatProbesTests", dependencies: ["MystatProbes"]),
    ]
)
