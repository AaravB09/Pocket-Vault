import SwiftUI
#if !SKIP
import AuthenticationServices
import CryptoKit
#endif

/// "Continue with Apple" / "Continue with Google" for LoginView.
///
/// Apple: real native `SignInWithAppleButton` on iOS — required once an
/// app offers any third-party sign-in (App Store guideline 4.8), and
/// gives the Face ID sheet instead of a browser tab. There's no
/// equivalent native Apple API on Android, so Android falls back to the
/// same Supabase-hosted OAuth page Google uses everywhere — that only
/// works if you also add an Apple provider config in Supabase using an
/// Apple *Services ID* (a separate thing from your app's Bundle ID).
///
/// Google: Supabase's hosted OAuth page on both platforms, NOT the
/// separate GoogleSignIn SDK — avoids a Google Cloud OAuth client,
/// GoogleService-Info.plist, and a second URL scheme. Needs the Google
/// provider enabled in Supabase (Authentication → Providers) with a
/// Google OAuth client of your own from Google Cloud Console — that
/// part can't be done from code, only from those two dashboards.
struct SocialSignInButtons: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.openURL) var openURL

    #if !SKIP
    @State private var currentNonce: String?
    @State private var webAuthSession: ASWebAuthenticationSession?
    @State private var presentationProvider = WebAuthPresentationContextProvider()
    #endif

    var body: some View {
        VStack(spacing: 12) {
            #if !SKIP
            SignInWithAppleButton(.continue, onRequest: configureAppleRequest, onCompletion: handleAppleCompletion)
                .signInWithAppleButtonStyle(theme.isLight ? .black : .white)
                .frame(height: 50)
                .cornerRadius(Layout.controlRadius)
            #else
            SocialOAuthButton(title: "Continue with Apple") { startOAuth(provider: "apple") }
            #endif

            SocialOAuthButton(title: "Continue with Google") { startOAuth(provider: "google") }
        }
    }

    private func startOAuth(provider: String) {
        guard let url = authManager.oauthAuthorizeURL(provider: provider) else { return }
        #if !SKIP
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "pocketvault") { callbackURL, error in
            guard let callbackURL, error == nil else { return }
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
        openURL(url)
        #endif
    }

    #if !SKIP
    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = Self.sha256(nonce)
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce
        else { return }
        Task { await authManager.signInWithApple(identityToken: identityToken, rawNonce: nonce) }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &randomBytes)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
    #endif
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

/// Plain fallback button used for every OAuth-redirect provider (Google
/// on both platforms, Apple on Android). Deliberately text-only, no
/// brand glyph — SF Symbols like "apple.logo" aren't guaranteed to
/// render meaningfully through Skip's Android shim, and guessing wrong
/// there isn't worth it for a decorative icon.
private struct SocialOAuthButton: View {
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let action: () -> Void

    // No natural `isLoading` boundary here — `startOAuth` either hands off
    // to a system web-auth sheet or opens the external browser, and there's
    // no reliable callback to flip a spinner back off if the user just
    // cancels that sheet, so this only gets the other five states rather
    // than risking a spinner that can get stuck on.
    @State private var isPressed = false
    @State private var flash = false
    @FocusState private var isFocused: Bool

    // Explicit init — Skip's Kotlin transpile includes every stored
    // property (even `private` @State/@FocusState ones) in the generated
    // constructor, unlike Swift's own memberwise init which excludes
    // `private` properties. Without this, call sites' trailing closure
    // binds to whatever property ends up last in Kotlin instead of
    // `action`, producing a "Function0<Unit>, but 'Boolean' was expected"
    // build error (see the matching fix on the CTA buttons above).
    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: {
            guard isEnabled else { return }
            ctaHapticTick()
            action()
        }) {
            Text(title)
                .font(theme.font(15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(isEnabled ? theme.textPrimary : theme.textPrimary.opacity(0.4))
                #if !SKIP
                .background(.ultraThinMaterial)
                .opacity(isEnabled ? 1.0 : 0.6)
                .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius))
                #else
                .background(isEnabled ? (theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08)) : Color(white: 0.5).opacity(0.12))
                .cornerRadius(Layout.controlRadius)
                #endif
                .overlay( // one-shot tap flash
                    RoundedRectangle(cornerRadius: Layout.controlRadius)
                        .fill(theme.textPrimary)
                        .opacity(flash ? 0.1 : 0.0)
                        .allowsHitTesting(false)
                )
                .overlay(RoundedRectangle(cornerRadius: Layout.controlRadius).stroke(theme.cardStroke, lineWidth: 1))
                .overlay( // keyboard / Full Keyboard Access / Switch Control focus ring
                    RoundedRectangle(cornerRadius: Layout.controlRadius + 3.0)
                        .stroke(theme.accent, lineWidth: isFocused ? 3.0 : 0.0)
                        .padding(-3.0)
                )
                .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if isEnabled { isPressed = true } }
                .onEnded { _ in
                    guard isPressed else { return }
                    isPressed = false
                    guard isEnabled, !reduceMotion else { return }
                    flash = true
                    withAnimation(.easeOut(duration: 0.35)) { flash = false }
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }
}
