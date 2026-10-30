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
        // Shared test helpers (locale support).
        .target(name: "MystatTestSupport", dependencies: ["MystatCore"], path: "Tests/Support"),
        .testTarget(name: "MystatCoreTests", dependencies: ["MystatCore", "MystatTestSupport"]),
        .testTarget(name: "MystatUITests", dependencies: ["MystatUI", "MystatTestSupport"]),
        .testTarget(name: "MystatLiveTests", dependencies: ["MystatLive", "MystatTestSupport"]),
        .testTarget(name: "MystatProbesTests", dependencies: ["MystatProbes", "MystatTestSupport"]),
    ]
)
