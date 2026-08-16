import Foundation
import Combine
#if !SKIP
import RevenueCat
#endif

struct SupabaseUser: Codable {
    let id: String
    let email: String?
}

private struct SupabaseAuthResponse: Codable {
    let access_token: String?
    let refresh_token: String?
    let user: SupabaseUser?
}

private struct SupabaseAuthError: Codable {
    let error: String?
    let error_description: String?
    let msg: String?
}

/// Simple email/password auth against Supabase's built-in Auth, plus a
/// guest mode. Guests get the full app immediately (Reciprocation +
/// IKEA Effect: let them build a real goal before asking for anything) —
/// their data lives locally exactly like an authenticated user's does
/// (GoalStore/StreakManager/LeaderboardManager are already local-only
/// regardless of auth state), so nothing about the guest experience is
/// degraded. The only risk a guest carries is losing that local data if
/// they lose the device — GuestSavePromptView surfaces that plainly,
/// later, once they've actually built something worth keeping.
///
/// STORAGE NAMESPACING ("incognito" guest mode):
/// Every local store (GoalStore, StreakManager, LeaderboardManager) keys
/// its UserDefaults entries by `storageNamespace` rather than a fixed
/// key. That's what stops a fresh "Continue as Guest" session from ever
/// loading a previously signed-in account's goals/streak/friend code —
/// each namespace is its own isolated bucket:
///   - Authenticated:  "user_<supabase user id>"
///   - Guest:          "guest_<random session id>", regenerated every
///                      time someone taps "Continue as Guest" fresh (a
///                      real incognito start), but kept stable across
///                      an app relaunch that happens *while still in*
///                      that same guest session so they don't lose
///                      progress just from backgrounding the app.
/// If a guest signs up or signs in mid-session, their in-progress guest
/// data is migrated onto the new account's namespace (see
/// `migrateNamespace`) instead of being silently orphaned. If a guest
/// signs out without converting, their guest namespace is wiped — true
/// incognito: nothing is left behind for the next guest session.
@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isGuest: Bool = false
    @Published var userEmail: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    /// Current storage namespace every local store should key its
    /// UserDefaults entries with. Views/managers read this once at
    /// creation time (see MainTabView, which is fully rebuilt via
    /// `.id(authManager.storageNamespace)` any time this value changes).
    @Published var storageNamespace: String = AuthManager.guestNamespace

    /// True while a Supabase password-recovery link is pending — the app
    /// should present a "choose a new password" screen instead of
    /// silently signing the link-tapper in.
    @Published var needsPasswordReset: Bool = false

    private let defaults = UserDefaults.standard
    private let userIDKey = "pv_authUserID"
    private let userEmailKey = "pv_authUserEmail"
    private let accessTokenKey = "pv_authAccessToken"
    private let guestKey = "pv_isGuest"
    private let guestSessionIDKey = "pv_guestSessionID"

    private var pendingRecoveryAccessToken: String?

    var userID: String? { defaults.string(forKey: userIDKey) }

    /// The signed-in user's Supabase session JWT. Send this — not the
    /// anon key — as the Authorization header for any Edge Function
    /// call that needs to know who the real caller is (bank sync,
    /// anything money-related). `nil` for guests, since guests have no
    /// real Supabase Auth session to verify server-side.
    var accessToken: String? { defaults.string(forKey: accessTokenKey) }

    static let guestNamespace = "guest_unset"

    static func namespace(for userID: String) -> String {
        "user_\(userID)"
    }

    init() {
        isGuest = defaults.bool(forKey: guestKey)

        if let storedID = defaults.string(forKey: userIDKey) {
            // Optimistically show the app immediately using the cached
            // session — avoids a login-screen flash on every launch —
            // then verify the token is still valid against Supabase in
            // the background. If the account was deleted or the token
            // expired, signOut() below reverts to the login screen.
            isAuthenticated = true
            userEmail = defaults.string(forKey: userEmailKey)
            storageNamespace = Self.namespace(for: storedID)
            Task {
                await identifyWithRevenueCat(userID: storedID)
                await validateStoredSession()
            }
        } else if isGuest {
            // Relaunching while still mid-guest-session (not a fresh tap
            // of "Continue as Guest") — keep the same namespace so their
            // in-progress goal/streak survives the relaunch.
            if let existingGuestID = defaults.string(forKey: guestSessionIDKey) {
                storageNamespace = existingGuestID
            } else {
                storageNamespace = beginNewGuestSession()
            }
        }
    }

    /// Lets someone use the full app without an account. Called from the
    /// "Continue as Guest" button on LoginView. Always starts a brand
    /// new, empty storage namespace — this is the fix for guest mode
    /// showing a previous account's data after sign-out.
    func continueAsGuest() {
        isGuest = true
        defaults.set(true, forKey: guestKey)
        storageNamespace = beginNewGuestSession()
    }

    private func beginNewGuestSession() -> String {
        let id = "guest_\(UUID().uuidString)"
        defaults.set(id, forKey: guestSessionIDKey)
        return id
    }

    /// Confirms the cached access token still corresponds to a real,
    /// active Supabase user. Calling GET /auth/v1/user with a stale,
    /// expired, or deleted-account token returns 401/403 — in that case
    /// we sign out locally so the login screen reappears instead of
    /// silently trusting UserDefaults forever.
    private func validateStoredSession() async {
        guard let token = defaults.string(forKey: accessTokenKey) else {
            await signOut()
            return
        }
        guard let url = URL(string: "\(SupabaseConfig.projectURL.absoluteString)/auth/v1/user") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                print("Stored session no longer valid, signing out:", String(data: data, encoding: .utf8) ?? "no body")
                await signOut()
                return
            }
            // Session still good — refresh the cached email in case it
            // changed, but leave isAuthenticated as-is (already true).
            if let user = try? JSONDecoder().decode(SupabaseUser.self, from: data) {
                defaults.set(user.email, forKey: userEmailKey)
                userEmail = user.email
            }
        } catch {
            // Network hiccup shouldn't sign the user out — only an
            // explicit rejection from Supabase should.
            print("Session validation network error (leaving session as-is):", error)
        }
    }

    func signUp(email: String, password: String) async {
        await performAuth(path: "signup", email: email, password: password)
    }

    func signIn(email: String, password: String) async {
        await performAuth(path: "token?grant_type=password", email: email, password: password)
    }

    /// Clears the local session AND rotates RevenueCat to a fresh
    /// anonymous identity. Call this from a "Sign Out" button, or from the
    /// DEBUG-only reset button in MainTabView while testing purchases.
    ///
    /// If we're leaving an un-converted guest session, its namespaced
    /// local data is wiped here — that's what makes guest mode behave
    /// like incognito: nothing survives past the session that made it,
    /// and the next "Continue as Guest" starts completely empty.
    func signOut() async {
        if isGuest, let guestID = defaults.string(forKey: guestSessionIDKey) {
            wipeNamespace(guestID)
            defaults.removeObject(forKey: guestSessionIDKey)
        }

        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: userEmailKey)
        defaults.removeObject(forKey: accessTokenKey)
        defaults.set(false, forKey: guestKey)
        isAuthenticated = false
        isGuest = false
        userEmail = nil
        errorMessage = nil
        storageNamespace = Self.guestNamespace
        _ = try? await Purchases.shared.logOut()
    }

    private func performAuth(path: String, email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(SupabaseConfig.projectURL.absoluteString)/auth/v1/\(path)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Couldn't reach the server."
                return
            }
            guard (200...299).contains(http.statusCode) else {
                print("Supabase auth error [\(http.statusCode)]:", String(data: data, encoding: .utf8) ?? "no body")
                let err = try? JSONDecoder().decode(SupabaseAuthError.self, from: data)
                let rawMessage = err?.error_description ?? err?.msg ?? err?.error ?? ""
                if rawMessage.localizedCaseInsensitiveContains("already registered")
                    || rawMessage.localizedCaseInsensitiveContains("already exists")
                    || rawMessage.localizedCaseInsensitiveContains("user_already_exists") {
                    errorMessage = "That email is already in use — try signing in instead."
                } else if !rawMessage.isEmpty {
                    errorMessage = rawMessage
                } else {
                    errorMessage = "That didn't work — check your email and password."
                }
                return
            }

            // Supabase's /auth/v1/signup returns two different JSON shapes
            // depending on whether "Confirm email" is enabled — see the
            // two branches below.
            if let auth = try? JSONDecoder().decode(SupabaseAuthResponse.self, from: data),
               let user = auth.user, let token = auth.access_token {
                completeSignIn(userID: user.id, email: user.email, accessToken: token)
                await identifyWithRevenueCat(userID: user.id)
                return
            }

            if (try? JSONDecoder().decode(SupabaseUser.self, from: data)) != nil {
                // Account created, awaiting email confirmation. Not an
                // error — leave errorMessage nil and isAuthenticated
                // false; LoginView shows its own "check your email" card
                // for exactly this combination after a signUp call.
                return
            }

            errorMessage = "Something went wrong. Try again."
        } catch {
            errorMessage = "Something went wrong. Try again."
        }
    }

    /// Handles the `pocketvault://...#access_token=...&refresh_token=...`
    /// link Supabase opens after a user taps the email confirmation or password reset link.
    func handleAuthCallback(url: URL) async {
        guard let fragment = url.fragment else { return }
        var fragmentComponents = URLComponents()
        fragmentComponents.query = fragment
        let items = fragmentComponents.queryItems ?? []

        guard let accessToken = items.first(where: { $0.name == "access_token" })?.value else {
            errorMessage = "That confirmation link looks invalid or expired."
            return
        }

        let type = items.first(where: { $0.name == "type" })?.value

        isLoading = true
        defer { isLoading = false }

        guard let userURL = URL(string: "\(SupabaseConfig.projectURL.absoluteString)/auth/v1/user") else { return }
        var req = URLRequest(url: userURL)
        req.httpMethod = "GET"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "That confirmation link looks invalid or expired."
                return
            }
            let user = try JSONDecoder().decode(SupabaseUser.self, from: data)

            if type == "recovery" {
                // This is a password-reset link, NOT a sign-in link — the
                // access token proves ownership of the account, but we
                // still route the person through an explicit "choose a
                // new password" screen rather than logging them straight
                // in with whatever their old (possibly compromised or
                // forgotten) password was.
                pendingRecoveryAccessToken = accessToken
                userEmail = user.email
                needsPasswordReset = true
                return
            }

            completeSignIn(userID: user.id, email: user.email, accessToken: accessToken)
            errorMessage = nil
            await identifyWithRevenueCat(userID: user.id)
        } catch {
            errorMessage = "Couldn't confirm your account. Try signing in instead."
        }
    }

    func sendPasswordReset(email: String) async throws {
        guard let url = URL(string: "\(SupabaseConfig.projectURL.absoluteString)/auth/v1/recover") else {
            throw NSError(domain: "AuthManager", code: 3)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "AuthManager", code: 4, userInfo: [NSLocalizedDescriptionKey: raw])
        }
    }

    /// Actually sets the new password using the recovery access token
    /// captured in `handleAuthCallback`, then signs the person in (the
    /// recovery token is itself a valid session, so there's no reason to
    /// make them type their brand-new password a second time on a
    /// separate sign-in screen).
    func completePasswordReset(newPassword: String) async throws {
        guard let token = pendingRecoveryAccessToken else {
            throw NSError(domain: "AuthManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "That reset link has expired — request a new one."])
        }
        guard let url = URL(string: "\(SupabaseConfig.projectURL.absoluteString)/auth/v1/user") else {
            throw NSError(domain: "AuthManager", code: 6)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["password": newPassword])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "AuthManager", code: 7, userInfo: [NSLocalizedDescriptionKey: raw])
        }

        let user = try? JSONDecoder().decode(SupabaseUser.self, from: data)
        pendingRecoveryAccessToken = nil
        needsPasswordReset = false

        if let user {
            completeSignIn(userID: user.id, email: user.email, accessToken: token)
            await identifyWithRevenueCat(userID: user.id)
        }
    }

    /// Shared finish-line for every path that ends in a valid session
    /// (sign up, sign in, email confirmation, password reset). Handles
    /// persisting the session AND migrating any in-progress guest data
    /// onto the newly-authenticated namespace so nothing built during a
    /// guest session gets silently lost by converting to a real account.
    private func completeSignIn(userID: String, email: String?, accessToken: String) {
        let newNamespace = Self.namespace(for: userID)

        if isGuest, let guestID = defaults.string(forKey: guestSessionIDKey) {
            migrateNamespace(from: guestID, to: newNamespace)
            defaults.removeObject(forKey: guestSessionIDKey)
        }

        defaults.set(userID, forKey: userIDKey)
        defaults.set(email, forKey: userEmailKey)
        defaults.set(accessToken, forKey: accessTokenKey)
        defaults.set(false, forKey: guestKey)

        userEmail = email
        isAuthenticated = true
        isGuest = false
        storageNamespace = newNamespace
    }

    /// Moves every UserDefaults entry prefixed "<oldNamespace>_" over to
    /// "<newNamespace>_", preserving whatever a guest built (goals,
    /// streak, friend code, profile photo) instead of orphaning it under
    /// a namespace nothing will read again.
    private func migrateNamespace(from oldNamespace: String, to newNamespace: String) {
        guard oldNamespace != newNamespace else { return }
        let oldPrefix = oldNamespace + "_"
        let newPrefix = newNamespace + "_"
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(oldPrefix) {
            let suffix = String(key.dropFirst(oldPrefix.count))
            defaults.set(value, forKey: newPrefix + suffix)
            defaults.removeObject(forKey: key)
        }
    }

    /// Deletes every UserDefaults entry under a namespace outright —
    /// used when leaving an un-converted guest session so the next
    /// "Continue as Guest" truly starts from nothing.
    private func wipeNamespace(_ namespace: String) {
        let prefix = namespace + "_"
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func identifyWithRevenueCat(userID: String) async {
        _ = try? await Purchases.shared.logIn(userID)
    }
}
