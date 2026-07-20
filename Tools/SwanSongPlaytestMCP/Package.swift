// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwanSongPlaytestMCP",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwanSongPlaytestMCP", targets: ["SwanSongPlaytestMCP"]),
    ],
    dependencies: [
        // Keep the dependency identity stable in renamed clones and Git
        // worktrees; SwiftPM otherwise derives it from the checkout folder.
        .package(name: "SwanSong-Desktop", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "SwanSongPlaytestMCP",
            dependencies: [
                .product(name: "SwanSongKit", package: "SwanSong-Desktop"),
            ]
        ),
    ]
)
