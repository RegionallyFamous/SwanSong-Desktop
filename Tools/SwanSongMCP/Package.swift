// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwanSongMCP",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwanSongMCP", targets: ["SwanSongMCP"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "SwanSongMCP",
            dependencies: [
                .product(name: "SwanSongKit", package: "SwanSong-Desktop"),
            ]
        ),
    ]
)
