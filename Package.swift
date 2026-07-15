// swift-tools-version: 6.0
import PackageDescription
import Foundation

let liveEngineDirectory = ProcessInfo.processInfo.environment["SWAN_ARES_ENGINE_DIR"]

let engineTarget: Target
if let liveEngineDirectory {
    engineTarget = .target(
        name: "CSwanEngine",
        path: "Sources/CSwanEngine",
        exclude: [
            "swan_engine.cpp",
            "swan_engine_ares.cpp",
            "swan_engine_stub.cpp",
            "swan_engine_backend.hpp",
        ],
        sources: ["bridge_anchor.c"],
        publicHeadersPath: "include",
        linkerSettings: [
            .unsafeFlags([
                "-L\(liveEngineDirectory)",
                "-lSwanAresEngine",
                "-Xlinker", "-rpath",
                "-Xlinker", liveEngineDirectory,
            ]),
        ]
    )
} else {
    engineTarget = .target(
        name: "CSwanEngine",
        path: "Sources/CSwanEngine",
        exclude: ["bridge_anchor.c"],
        publicHeadersPath: "include"
    )
}

let package = Package(
    name: "SwanSongDesktop",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "SwanSong", targets: ["SwanSongApp"]),
        .executable(name: "SwanSongChecks", targets: ["SwanSongChecks"]),
        .executable(name: "SwanSongDifferential", targets: ["SwanSongDifferential"]),
        .executable(name: "SwanSongProbe", targets: ["SwanSongProbe"]),
        .executable(name: "SwanSongSoak", targets: ["SwanSongSoak"]),
        .library(name: "SwanSongKit", targets: ["SwanSongKit"]),
    ],
    targets: [
        engineTarget,
        .target(
            name: "SwanSongKit",
            dependencies: ["CSwanEngine"]
        ),
        .executableTarget(
            name: "SwanSongApp",
            dependencies: ["SwanSongKit"],
            swiftSettings: [
                .define("SWAN_SONG_AUTOMATION", .when(configuration: .debug)),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFAudio"),
                .linkedFramework("GameController"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        .executableTarget(
            name: "SwanSongChecks",
            dependencies: ["SwanSongKit", "CSwanEngine"]
        ),
        .executableTarget(
            name: "SwanSongDifferential",
            dependencies: ["SwanSongKit"]
        ),
        .executableTarget(
            name: "SwanSongProbe",
            dependencies: ["SwanSongKit"]
        ),
        .executableTarget(
            name: "SwanSongSoak",
            dependencies: ["SwanSongKit"]
        ),
        .testTarget(
            name: "SwanSongAppSnapshotTests",
            dependencies: ["SwanSongApp", "SwanSongKit"],
            resources: [.copy("ui-perceptual-baselines.json")]
        ),
    ],
    cxxLanguageStandard: .cxx20
)
