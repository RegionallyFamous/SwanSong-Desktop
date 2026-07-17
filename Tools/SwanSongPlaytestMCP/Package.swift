// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwanSongPlaytestMCP",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwanSongPlaytestMCP", targets: ["SwanSongPlaytestMCP"]),
    ],
    dependencies: [
        .package(path: "../.."),
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
