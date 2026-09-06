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
        // PINNED to the exact versions resolved for the successful
        // 19:21 Sep 3 APK build (Package.resolved content; no version
        // in this set has changed since Aug 30 when Package.resolved
        // was first created). `from: "1.9.5"` / `from: "1.0.0"`
        // were floating ranges that could resolve to a newer skip
        // release and pull in a different transitive set on next
        // resolve; pinning makes the resolution deterministic.
        .package(url: "https://source.skip.tools/skip.git", from: "1.9.8"),
        .package(url: "https://source.skip.tools/skip-ui.git", from: "1.59.2"),
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", exact: "5.87.1"),
        .package(url: "https://github.com/plaid/plaid-link-ios-spm.git", exact: "7.1.0"),
        // Android side of Pro/Ask AI: the native `RevenueCat` package right
        // below is iOS-only (no Android build of its own — see the
        // `condition`-less-but-#if!SKIP-guarded usage in
        // EntitlementManager/Pocket_VaultApp). SkipRevenue is a separate,
        // Skip-aware wrapper around RevenueCat that DOES ship an Android
        // implementation, so it's what makes Purchases/paywall actually work
        // on that platform. See EntitlementManager.swift and
        // PaywallView.swift for where this gets used.
        .package(url: "https://source.skip.dev/skip-revenue.git", exact: "0.3.0")
    ],
    targets: [
        .target(name: "PocketVault", dependencies: [
                    .product(name: "SkipUI", package: "skip-ui"),
                    // These two SDKs are iOS-only (no Skip/skip.yml,
                    // no Android build of their own) — usage is already
                    // guarded with #if !SKIP throughout the app (see
                    // EntitlementManager, PlaidConnectionManager). But
                    // without this `condition`, Skip still tries to
                    // resolve/transpile them for the Android side of
                    // *this* target, which silently fails the whole
                    // PocketVault transpile step (no "Skip PocketVault"
                    // line in the build log) rather than erroring
                    // clearly — Gradle only surfaces it later as
                    // "Could not locate transpiled module for
                    // PocketVault". The condition tells Skip's plugin
                    // to drop them from the Android dependency graph
                    // entirely, same as it already does for any
                    // dependency lacking a Skip/skip.yml.
                    .product(name: "RevenueCat", package: "purchases-ios", condition: .when(platforms: [.iOS, .macOS])),
                    .product(name: "LinkKit", package: "plaid-link-ios-spm", condition: .when(platforms: [.iOS, .macOS])),
                    // Unlike RevenueCat/LinkKit above, SkipRevenue DOES ship
                    // a Skip/skip.yml and build for both platforms, so no
                    // `condition:` is needed — it's meant to be resolved on
                    // both iOS and Android.
                    .product(name: "SkipRevenue", package: "skip-revenue")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "PocketVaultTests", dependencies: [
                    "PocketVault",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )
