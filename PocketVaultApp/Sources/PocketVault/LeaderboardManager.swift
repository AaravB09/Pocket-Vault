import Foundation
import Combine

/// One row from the `profiles` table.
struct LeaderboardEntry: Identifiable, Codable, Equatable {
    var id: String
    var display_name: String
    var friend_code: String
    var current_streak: Int
    var longest_streak: Int
}

// NOTE(skip): these two used to be decoded as raw `[String: String]`
// dictionaries. Skip's `JSONDecoder` shim only reliably resolves
// `decode(_:)` against a concrete `Codable` type — asking it to decode
// into a bare `Dictionary` left the element type unresolved on the
// Kotlin side, which cascaded into a pile of unrelated-looking errors
// downstream (ambiguous overloads on the `$0[...]` subscript, "cannot
// infer type for 'it'", and even a `MatchGroup`/`String` mismatch on
// the `matches` variable below — none of that is really about regex,
// it's fallout from the unresolved decode). Small dedicated structs,
// same as `LeaderboardEntry` above, decode cleanly on both platforms.

/// Shape of one row returned by the `lookup_friend_by_code` RPC.
private struct FriendLookupResult: Codable {
    let id: String
}

/// Shape of one row from a `friendships` select limited to `friend_id`.
private struct FriendshipRow: Codable {
    let friend_id: String
}

/// Backs the Friends tab. Talks directly to Supabase's REST API; see
/// SupabaseConfig.swift and supabase_schema.sql for the one-time setup
/// this depends on.
///
/// Note: identity here (`myUserID`) predates AuthManager and is a random
/// UUID stored locally — SharedBudgetView prefers `authManager.userID`
/// when available and falls back to this, so both identity sources stay
/// compatible without needing to migrate this class.
@MainActor
final class LeaderboardManager: ObservableObject {
    @Published var friends: [LeaderboardEntry] = []
    @Published var myEntry: LeaderboardEntry?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard
    private let userIDKey: String
    private let friendCodeKey: String
    private let displayNameKey: String

    let myUserID: String
    let myFriendCode: String

    var myDisplayName: String {
        get { defaults.string(forKey: displayNameKey) ?? "Saver" }
        set { defaults.set(newValue, forKey: displayNameKey) }
    }

    private var isConfigured: Bool {
        !SupabaseConfig.anonKey.contains("PASTE_YOUR")
    }

    /// `namespace` isolates one account's (or one guest session's) social
    /// identity — user id, friend code, display name — from every other.
    /// See AuthManager.storageNamespace. Without this, a guest session
    /// would inherit whatever friend code/display name the previously
    /// signed-in account had, and vice versa.
    init(namespace: String) {
        userIDKey = "\(namespace)_pv_userID"
        friendCodeKey = "\(namespace)_pv_friendCode"
        displayNameKey = "\(namespace)_pv_displayName"

        if let existing = defaults.string(forKey: userIDKey) {
            myUserID = existing
        } else {
            let newID = UUID().uuidString
            defaults.set(newID, forKey: userIDKey)
            myUserID = newID
        }

        if let existingCode = defaults.string(forKey: friendCodeKey) {
            myFriendCode = existingCode
        } else {
            let code = Self.generateFriendCode()
            defaults.set(code, forKey: friendCodeKey)
            myFriendCode = code
        }
    }

    private static func generateFriendCode() -> String {
        // Excludes visually ambiguous characters (0/O, 1/I).
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in letters.randomElement()! })
    }

    /// `accessToken` is the signed-in user's real Supabase session JWT
    /// (AuthManager.accessToken) — NOT the anon key. Every method below
    /// requires one and fails fast without it, rather than silently
    /// falling back to the anon key: a request with only the anon key
    /// looks anonymous to Postgres, so auth.uid()-based RLS policies
    /// would see no caller identity at all. Friends & Leaderboard is
    /// gated behind a real account in the UI (AccountRequiredGateView)
    /// specifically so every call site here always has a token to pass.
    private func request(path: String, method: String = "GET", accessToken: String, queryItems: [URLQueryItem] = [], body: Data? = nil, extraHeaders: [String: String] = [:]) -> URLRequest {
        var components = URLComponents(url: SupabaseConfig.restURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        for (key, value) in extraHeaders { req.setValue(value, forHTTPHeaderField: key) }
        req.httpBody = body
        return req
    }

    /// Push my current streak up to Supabase. Cheap, best-effort — call it
    /// whenever StreakManager's streak changes and once on launch.
    ///
    /// `identityID` is the id this profile row is keyed by server-side —
    /// pass `authManager.userID` (falls back to `myUserID` defensively,
    /// though guests never reach this call site anymore). It must match
    /// `accessToken`'s auth.uid() or the `profiles upsert own` RLS
    /// policy rejects the write.
    func syncMyStreak(currentStreak: Int, longestStreak: Int, identityID: String, accessToken: String?) async {
        guard isConfigured, let accessToken else { return }

        let payload: [String: Any] = [
            "id": identityID,
            "display_name": myDisplayName,
            "friend_code": myFriendCode,
            "current_streak": currentStreak,
            "longest_streak": longestStreak
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let req = request(path: "profiles", method: "POST", accessToken: accessToken, body: body, extraHeaders: [
            "Prefer": "resolution=merge-duplicates,return=minimal"
        ])
        _ = try? await URLSession.shared.data(for: req)
        // Best-effort: a failed sync here shouldn't interrupt the app — the
        // next streak change (or the next time Friends is opened) retries.
    }

    /// Look up a friend by their 6-character code and add them. The
    /// lookup goes through the `lookup_friend_by_code` RPC (a
    /// security-definer function) instead of a raw `profiles` select —
    /// that function returns only id + friend_code for the match,
    /// rather than exposing every column of a stranger's profile row
    /// via a broad SELECT policy.
    func addFriend(code: String, identityID: String, accessToken: String?) async {
        guard isConfigured else {
            errorMessage = "Friends isn't set up yet — add your Supabase anon key in SupabaseConfig.swift."
            return
        }
        guard let accessToken else {
            errorMessage = "Sign in to add friends."
            return
        }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let lookupBody = try? JSONSerialization.data(withJSONObject: ["p_code": trimmed]) else { return }
            let lookupReq = request(path: "rpc/lookup_friend_by_code", method: "POST", accessToken: accessToken, body: lookupBody)
            let (data, response) = try await URLSession.shared.data(for: lookupReq)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "Couldn't look up that code."
                return
            }
            let matches = try JSONDecoder().decode([FriendLookupResult].self, from: data)
            guard let friendID = matches.first?.id else {
                errorMessage = "No one has that code."
                return
            }
            if friendID == identityID {
                errorMessage = "That's your own code."
                return
            }

            let friendshipPayload: [String: Any] = ["user_id": identityID, "friend_id": friendID]
            guard let body = try? JSONSerialization.data(withJSONObject: friendshipPayload) else { return }
            let addReq = request(path: "friendships", method: "POST", accessToken: accessToken, body: body, extraHeaders: [
                "Prefer": "resolution=merge-duplicates,return=minimal"
            ])
            let (_, addResponse) = try await URLSession.shared.data(for: addReq)
            guard let addHTTP = addResponse as? HTTPURLResponse, (200...299).contains(addHTTP.statusCode) else {
                errorMessage = "Couldn't add that friend."
                return
            }
            await fetchLeaderboard(identityID: identityID, accessToken: accessToken)
        } catch {
            errorMessage = "Something went wrong adding that friend."
        }
    }

    /// Fetch my profile + all friends' profiles, sorted by current streak.
    func fetchLeaderboard(identityID: String, accessToken: String?) async {
        guard isConfigured else {
            errorMessage = "Friends isn't set up yet — add your Supabase anon key in SupabaseConfig.swift."
            return
        }
        guard let accessToken else {
            errorMessage = "Sign in to see your leaderboard."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let friendIDsReq = request(path: "friendships", accessToken: accessToken, queryItems: [
                URLQueryItem(name: "user_id", value: "eq.\(identityID)"),
                URLQueryItem(name: "select", value: "friend_id")
            ])
            let (friendData, _) = try await URLSession.shared.data(for: friendIDsReq)
            let friendRows = (try? JSONDecoder().decode([FriendshipRow].self, from: friendData)) ?? []
            let friendIDs = friendRows.map { $0.friend_id }

            let quotedIDs = ([identityID] + friendIDs).map { "\"\($0)\"" }.joined(separator: ",")
            let profilesReq = request(path: "profiles", accessToken: accessToken, queryItems: [
                URLQueryItem(name: "id", value: "in.(\(quotedIDs))"),
                URLQueryItem(name: "order", value: "current_streak.desc")
            ])
            let (data, response) = try await URLSession.shared.data(for: profilesReq)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "Couldn't load the leaderboard."
                return
            }
            let entries = try JSONDecoder().decode([LeaderboardEntry].self, from: data)
            friends = entries.filter { $0.id != identityID }
            myEntry = entries.first { $0.id == identityID }
        } catch {
            errorMessage = "Couldn't load the leaderboard."
        }
    }
}
