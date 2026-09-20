// swift-tools-version:5.9
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

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
