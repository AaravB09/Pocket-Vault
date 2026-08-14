import SwiftUI
import RevenueCat

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct PocketVaultApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var authManager = AuthManager()
    @StateObject private var themeManager = ThemeManager()

    // Reads the ACTUAL resolved scheme from the environment (this is
    // what updates live if appearanceMode == .system and the user
    // flips iOS Settings > Display while the app is open).
    @Environment(\.colorScheme) private var systemColorScheme

    init() {
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .error
        #endif
        Purchases.configure(withAPIKey: "test_yMItdpRXbuqTbRusbGjdppPXrPJ")
    }

    var body: some Scene {
        WindowGroup {
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
            // nil (system mode) lets iOS decide; .light/.dark force it.
            .preferredColorScheme(themeManager.appearanceMode.colorScheme)
            .onAppear {
                if let forced = themeManager.appearanceMode.colorScheme {
                    themeManager.updateResolvedScheme(forced)
                } else {
                    themeManager.updateResolvedScheme(systemColorScheme)
                }
                applyWindowAppearanceOverride(themeManager.appearanceMode)
            }
            .onChange(of: systemColorScheme) { _, newValue in
                themeManager.updateResolvedScheme(newValue)
            }
            .onChange(of: themeManager.appearanceMode) { _, mode in
                if let forced = mode.colorScheme {
                    themeManager.updateResolvedScheme(forced)
                } else {
                    themeManager.updateResolvedScheme(systemColorScheme)
                }
                applyWindowAppearanceOverride(mode)
            }
            .onChange(of: authManager.isAuthenticated) { _, _ in
                // Logging in swaps LoginView for MainTabView in place —
                // the outer Group's .onAppear doesn't refire for that,
                // so without this the window can silently drift back to
                // the system style right as the main app appears.
                applyWindowAppearanceOverride(themeManager.appearanceMode)
            }
            .onChange(of: authManager.isGuest) { _, _ in
                applyWindowAppearanceOverride(themeManager.appearanceMode)
            }
            .onOpenURL { url in
                guard url.scheme == "pocketvault" else { return }
                Task { await authManager.handleAuthCallback(url: url) }
            }
            .fullScreenCover(isPresented: $authManager.needsPasswordReset) {
                NewPasswordView()
                    .environmentObject(authManager)
            }
        }
    }

    /// `.preferredColorScheme` sets SwiftUI's environment color scheme,
    /// which text/system-color APIs read correctly — but `.ultraThinMaterial`
    /// and other UIKit-backed blur effects read `UITraitCollection.
    /// userInterfaceStyle` from the window instead, and that doesn't
    /// reliably follow `.preferredColorScheme` into `.sheet`/
    /// `.fullScreenCover` presentations (each gets its own UIKit
    /// presentation controller). Without this, forcing Light mode while
    /// the simulator/device is set to Dark leaves every card's material
    /// rendering as a dark, grayish blur while the text around it is
    /// styled light — exactly the mismatch that makes sheets look grimy.
    /// Setting the override directly on the window fixes materials in
    /// every sheet at once, no matter how many `.sheet` call sites exist.
    private func applyWindowAppearanceOverride(_ mode: AppAppearanceMode) {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let style: UIUserInterfaceStyle
        switch mode {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        scene.windows.forEach { $0.overrideUserInterfaceStyle = style }
    }
}
