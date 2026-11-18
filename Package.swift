// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "doppio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "island-bridge", targets: ["island-bridge"]),
        .executable(name: "cc-agy", targets: ["cc-agy"]),
        .executable(name: "Doppio", targets: ["Doppio"]),
    ],
    targets: [
        .target(name: "IslandCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "island-bridge", dependencies: ["IslandCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "cc-agy", dependencies: ["IslandCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Doppio",
            dependencies: ["IslandCore"],
            path: "App",
            resources: [.copy("Resources/VT323-Regular.ttf")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
