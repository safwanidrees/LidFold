// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LidFold",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LidFold", targets: ["LidFold"]),
    ],
    targets: [
        // Pure geometry, curve and state-machine logic. No AppKit, no
        // Metal — this is what the unit tests exercise directly.
        .target(
            name: "LidFoldModel",
            path: "Sources/LidFoldModel",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Reads the hinge angle from the built-in lid angle sensor over HID.
        .target(
            name: "LidFoldSensor",
            path: "Sources/LidFoldSensor",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The Metal shader that draws the fold on a captured still.
        .target(
            name: "LidFoldRender",
            dependencies: ["LidFoldModel"],
            path: "Sources/LidFoldRender",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The menu bar app, in MVVM layers: Model (persisted settings),
        // View (menu bar, windows), ViewModel (observable state and
        // commands the views bind to), and Services (sensor, capture,
        // system integration) underneath.
        .executableTarget(
            name: "LidFold",
            dependencies: ["LidFoldModel", "LidFoldSensor", "LidFoldRender"],
            path: "Sources/LidFold",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LidFoldModelTests",
            dependencies: ["LidFoldModel"],
            path: "Tests/LidFoldModelTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
