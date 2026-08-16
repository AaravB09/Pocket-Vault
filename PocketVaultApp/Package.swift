// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "PocketVaultApp",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PocketVault", type: .dynamic, targets: ["PocketVault"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.9.5"),
        .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", from: "5.0.0"),
        .package(url: "https://github.com/plaid/plaid-link-ios.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "PocketVault", dependencies: [
            .product(name: "SkipUI", package: "skip-ui"),
            .product(name: "RevenueCat", package: "purchases-ios"),
            .product(name: "LinkKit", package: "plaid-link-ios")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "PocketVaultTests", dependencies: [
            "PocketVault",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
