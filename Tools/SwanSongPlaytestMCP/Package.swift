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
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk.git",
            exact: "0.12.1"
        ),
    ],
    targets: [
        .executableTarget(
            name: "SwanSongPlaytestMCP",
            dependencies: [
                .product(name: "SwanSongKit", package: "SwanSong-Desktop"),
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
    ]
)
