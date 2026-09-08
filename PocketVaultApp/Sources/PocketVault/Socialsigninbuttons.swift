import SwiftUI
#if !SKIP
import AuthenticationServices
#endif

/// "Continue with Google" for LoginView.
///
/// Google: Supabase's hosted OAuth page on both platforms, NOT the
/// separate GoogleSignIn SDK — avoids a Google Cloud OAuth client,
/// GoogleService-Info.plist, and a second URL scheme. Needs the Google
/// provider enabled in Supabase (Authentication → Providers) with a
/// Google OAuth client of your own from Google Cloud Console — that
/// part can't be done from code, only from those two dashboards.
struct SocialSignInButtons: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.openURL) var openURL: OpenURLAction

    #if !SKIP
    @State private var webAuthSession: ASWebAuthenticationSession?
    @State private var presentationProvider = WebAuthPresentationContextProvider()
    #endif

    public var body: some View {
        VStack(spacing: 12.0) {
            VaultButton("Continue with Google", variant: .social) {
                print("[SocialSignInButtons] 'Continue with Google' tapped — calling action()")
                ctaHapticTick()
                startOAuth(provider: "google")
            }
        }
    }

    private func startOAuth(provider: String) {
        print("[SocialSignInButtons] startOAuth tapped — provider=\(provider)")
        guard let url = authManager.oauthAuthorizeURL(provider: provider) else {
            print("[SocialSignInButtons] ERROR: oauthAuthorizeURL returned nil for provider=\(provider) (SupabaseConfig.projectURL = \(SupabaseConfig.projectURL.absoluteString))")
            return
        }
        print("[SocialSignInButtons] OAuth URL constructed: \(url.absoluteString)")
        #if !SKIP
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "pocketvault") { callbackURL, error in
            if let error {
                print("[SocialSignInButtons] ASWebAuthenticationSession error for provider=\(provider): \(error.localizedDescription)")
                return
            }
            guard let callbackURL else {
                print("[SocialSignInButtons] ASWebAuthenticationSession returned nil callback URL for provider=\(provider)")
                return
            }
            print("[SocialSignInButtons] ASWebAuthenticationSession callback received for provider=\(provider): \(callbackURL.absoluteString)")
            Task { await authManager.handleAuthCallback(url: callbackURL) }
        }
        session.presentationContextProvider = presentationProvider
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        session.start()
        #else
        // Android: no equivalent to ASWebAuthenticationSession here, so this
        // opens the system browser directly. onOpenURL (Pocket_VaultApp.swift)
        // catches the "pocketvault://auth-callback#access_token=..." redirect
        // the same way it already does for magic links.
        print("[SocialSignInButtons] Android: calling openURL(url) for provider=" + provider)
        openURL(url)
        #endif
    }

}

#if !SKIP
/// ASWebAuthenticationSession needs a window to anchor its sheet to —
/// this just hands back the app's current key window.
private final class WebAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#endif