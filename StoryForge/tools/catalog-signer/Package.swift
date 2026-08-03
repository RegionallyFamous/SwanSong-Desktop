// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwanSongCatalogSigner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "catalog-signer", targets: ["CatalogSigner"]),
    ],
    targets: [
        .executableTarget(name: "CatalogSigner"),
    ]
)
