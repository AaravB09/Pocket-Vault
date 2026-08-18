import Foundation
import OSLog
import SwiftUI

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
