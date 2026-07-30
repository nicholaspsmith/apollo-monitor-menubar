// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ApolloMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ApolloMonitor", targets: ["ApolloMonitor"]),
        .library(name: "ApolloMonitorCore", targets: ["ApolloMonitorCore"]),
    ],
    dependencies: [
        .package(path: "../StatusItemKit"),
        .package(path: "../HotkeyKit"),
    ],
    targets: [
        .target(name: "ApolloMonitorCore"),
        .executableTarget(
            name: "ApolloMonitor",
            dependencies: [
                "ApolloMonitorCore",
                .product(name: "StatusItemKit", package: "StatusItemKit"),
                .product(name: "HotkeyKit", package: "HotkeyKit"),
            ]
        ),
        .testTarget(name: "ApolloMonitorCoreTests", dependencies: ["ApolloMonitorCore"]),
    ]
)
