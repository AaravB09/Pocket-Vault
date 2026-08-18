import SwiftUI

// This whole file is the iOS app entry point (App/Scene/WindowGroup/@main).
// None of that is implemented by Skip — Android's entry point comes from
// PocketVaultRootView in PocketVaultApp.swift instead — so the entire
// declaration below is invisible to the Skip/Android build.
#if !SKIP
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
            .onChange(of: systemColorScheme) { newValue in
                themeManager.updateResolvedScheme(newValue)
            }
            .onChange(of: themeManager.appearanceMode) { mode in
                if let forced = mode.colorScheme {
                    themeManager.updateResolvedScheme(forced)
                } else {
                    themeManager.updateResolvedScheme(systemColorScheme)
                }
                applyWindowAppearanceOverride(mode)
            }
            .onChange(of: authManager.isAuthenticated) { _ in
                applyWindowAppearanceOverride(themeManager.appearanceMode)
            }
            .onChange(of: authManager.isGuest) { _ in
                applyWindowAppearanceOverride(themeManager.appearanceMode)
            }
            .onOpenURL { url in
                Task { await authManager.handleAuthCallback(url: url) }
            }
            .fullScreenCover(isPresented: $authManager.needsPasswordReset) {
                NewPasswordView()
                    .environmentObject(authManager)
            }
        }
    }

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
#endif
