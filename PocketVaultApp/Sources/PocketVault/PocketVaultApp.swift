import Foundation
import OSLog
import SwiftUI
#if SKIP
import SkipRevenue
#endif

/// A logger for the PocketVault module.
let logger: Logger = Logger(subsystem: "com.sanjivanilabs.pocketvault", category: "PocketVault")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// Mirrors what `Pocket_VaultApp.swift`'s `WindowGroup` does on iOS — auth-gated between
/// `LoginView` and `MainTabView` — rather than loading `ContentView` directly: `ContentView`
/// is just one tab's content and requires bindings/a `GoalStore` that only `MainTabView` owns,
/// so it can't be constructed with no arguments the way this view previously tried to.
public struct PocketVaultRootView : View {
    @StateObject private var authManager = AuthManager()
    @StateObject private var themeManager = ThemeManager()

    // FIX (Appearance mode / dark-light toggle doing nothing on Android):
    // `ThemeManager.resolvedIsLight` — the flag every single color token
    // (`background`, `textPrimary`, `accent`, etc.) actually reads — only
    // ever got recomputed by the `.onAppear`/`.onChange` wiring inside
    // `Pocket_VaultApp.swift`. That entire file is the iOS app entry
    // point (`@main`, `WindowGroup`, ...), wrapped in `#if !SKIP` end to
    // end — none of it exists on Android at all. Android's own entry
    // point (this view, loaded from `PocketVaultAppDelegate`) never had
    // any equivalent, so `resolvedIsLight` sat at its hardcoded `false`
    // default for the lifetime of the app: tapping "Light" in Appearance
    // updated `appearanceMode` (that part persists fine, same
    // `ThemeManager` either platform), but nothing ever turned that into
    // an updated `resolvedIsLight`, so every screen kept rendering dark
    // regardless of the setting — the toggle looked completely dead.
    // Mirrors the same three call sites iOS already has: resolve once up
    // front, again whenever the system's own scheme changes, and again
    // whenever the user picks a different appearance mode.
    @Environment(\.colorScheme) private var systemColorScheme

    public init() {
    }

    public var body: some View {
        Group {
            if authManager.isAuthenticated || authManager.isGuest {
                MainTabView(namespace: authManager.storageNamespace)
                    .id(authManager.storageNamespace)
            } else {
                LoginView()
            }
        }
        .environmentObject(authManager)
        .environmentObject(themeManager)
        // nil (system mode) lets Android decide; .light/.dark force it —
        // same convention as the iOS entry point.
        .preferredColorScheme(themeManager.appearanceMode.colorScheme)
        .onAppear {
            if let forced = themeManager.appearanceMode.colorScheme {
                themeManager.updateResolvedScheme(forced)
            } else {
                themeManager.updateResolvedScheme(systemColorScheme)
            }
        }
        .onChange(of: systemColorScheme) { newValue in
            themeManager.updateResolvedScheme(newValue)
        }
        .onChange(of: themeManager.appearanceMode) { mode in
            if let forced = mode.colorScheme {
                themeManager.updateResolvedScheme(forced)
            } else {
                themeManager.updateResolvedScheme(systemColorScheme)
            }
        }
        .task {
            logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
        }
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
public final class PocketVaultAppDelegate : Sendable {
    public static let shared = PocketVaultAppDelegate()

    private init() {
    }

    public func onInit() {
        logger.debug("onInit")
        // Android equivalent of Pocket_VaultApp.swift's
        // `AppDelegate.applicationDidFinishLaunching`, which is where
        // `Purchases.configure()` runs on iOS. `onInit()` fires once at
        // Android app startup, before any SwiftUI view (and therefore
        // before EntitlementManager's own `init` calls `refresh()`) —
        // same "configure before anything touches .shared" requirement,
        // just on Android's own hook instead of UIKit's.
        //
        // TODO: replace with your actual RevenueCat Play Store API key
        // (starts with "goog_") from the RevenueCat dashboard — this is
        // NOT the same key as the iOS one in Pocket_VaultApp.swift.
        #if SKIP
        RevenueCatFuse.shared.configure(apiKey: "goog_RWJTYoQPXJfwsirdwKNCXArEiQn")
        #endif
    }

    public func onLaunch() {
        logger.debug("onLaunch")
    }

    public func onResume() {
        logger.debug("onResume")
    }

    public func onPause() {
        logger.debug("onPause")
    }

    public func onStop() {
        logger.debug("onStop")
    }

    public func onDestroy() {
        logger.debug("onDestroy")
    }

    public func onLowMemory() {
        logger.debug("onLowMemory")
    }
}
