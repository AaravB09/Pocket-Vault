import Foundation
import Combine

/// One row from the `shared_goals` table — the "contract" two people share
/// for a single goal: what it's called, the target, and who's on it.
struct SharedGoalRecord: Codable, Equatable {
    var id: String
    var goal_title: String
    var target_amount: Double
    var owner_id: String
    var owner_name: String
    var partner_id: String?
    var partner_name: String?
    var share_code: String
}

/// One row from `shared_deposits` — a single tagged contribution.
struct SharedDepositRecord: Identifiable, Codable, Equatable {
    var id: String
    var shared_goal_id: String
    var contributor_id: String
    var contributor_name: String
    var amount: Double
    var created_at: String
}

/// Backs the "Shared Budget" feature: two people contributing to the same
/// goal, each deposit tagged with who made it. Same Supabase project and
/// request pattern as LeaderboardManager — see supabase_shared_budget.sql
/// for the one-time table setup this depends on.
///
/// Deposits are the source of truth for the combined total (not a single
/// "currentSavings" number), so either person can deposit from their own
/// device and both sides stay correct once they refresh.
@MainActor
final class SharedBudgetManager: ObservableObject {
    @Published var share: SharedGoalRecord?
    @Published var deposits: [SharedDepositRecord] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    var totalContributed: Double {
        deposits.reduce(0) { $0 + $1.amount }
    }

    func contributed(by contributorID: String) -> Double {
        deposits.filter { $0.contributor_id == contributorID }.reduce(0) { $0 + $1.amount }
    }

    private static func generateShareCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in letters.randomElement()! })
    }

    /// `accessToken` is the signed-in user's real Supabase session JWT
    /// (AuthManager.accessToken) — NOT the anon key. Every method below
    /// requires one and fails fast: Shared Budget is gated behind a real
    /// account in the UI (AccountRequiredGateView), so every call site
    /// always has a token, and the RLS policies on shared_goals/
    /// shared_deposits check auth.uid() directly against
    /// owner_id/partner_id/contributor_id.
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

    /// Starts sharing an existing local goal. Generates the code the owner
    /// sends to their partner.
    func createShare(goalTitle: String, targetAmount: Double, ownerID: String, ownerName: String, accessToken: String?) async -> SharedGoalRecord? {
        guard let accessToken else {
            errorMessage = "Sign in to share a goal."
            return nil
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "goal_title": goalTitle,
            "target_amount": targetAmount,
            "owner_id": ownerID,
            "owner_name": ownerName,
            "share_code": Self.generateShareCode()
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        let req = request(path: "shared_goals", method: "POST", accessToken: accessToken, body: body, extraHeaders: ["Prefer": "return=representation"])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "Couldn't create the shared budget."
                return nil
            }
            let record = try JSONDecoder().decode([SharedGoalRecord].self, from: data).first
            share = record
            return record
        } catch {
            errorMessage = "Couldn't create the shared budget."
            return nil
        }
    }

    /// Looks up a shared budget by its code and joins it via the
    /// `join_shared_goal` RPC. The partner id is no longer sent from the
    /// client at all — the security-definer function derives "who's
    /// joining" from the caller's own token (auth.uid()) server-side,
    /// instead of trusting a client-supplied partnerID that anyone with
    /// the anon key could have set to whatever they wanted. Returns the
    /// record so the caller can create a matching local goal for them.
    func joinShare(code: String, partnerName: String, accessToken: String?) async -> SharedGoalRecord? {
        guard let accessToken else {
            errorMessage = "Sign in to join a shared budget."
            return nil
        }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let payload: [String: Any] = ["p_share_code": trimmed, "p_partner_name": partnerName]
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            let req = request(path: "rpc/join_shared_goal", method: "POST", accessToken: accessToken, body: body, extraHeaders: ["Prefer": "return=representation"])
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                // The RPC raises a specific message (own code / already has
                // a partner / no such code) — surface it when we can.
                if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = body["message"] as? String {
                    errorMessage = message
                } else {
                    errorMessage = "Couldn't join that shared budget."
                }
                return nil
            }
            guard let record = try JSONDecoder().decode([SharedGoalRecord].self, from: data).first else {
                errorMessage = "Couldn't join that shared budget."
                return nil
            }
            share = record
            return record
        } catch {
            errorMessage = "Couldn't join that shared budget."
            return nil
        }
    }

    /// Refreshes the share record and its full deposit history — call on
    /// appear and pull-to-refresh, same pattern as LeaderboardManager.
    func loadShare(id: String, accessToken: String?) async {
        guard let accessToken else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let shareReq = request(path: "shared_goals", accessToken: accessToken, queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")])
            let (shareData, shareResponse) = try await URLSession.shared.data(for: shareReq)
            guard let http = shareResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "Couldn't load the shared budget."
                return
            }
            share = try JSONDecoder().decode([SharedGoalRecord].self, from: shareData).first

            let depositsReq = request(path: "shared_deposits", accessToken: accessToken, queryItems: [
                URLQueryItem(name: "shared_goal_id", value: "eq.\(id)"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ])
            let (depositData, depositResponse) = try await URLSession.shared.data(for: depositsReq)
            guard let depositHTTP = depositResponse as? HTTPURLResponse, (200...299).contains(depositHTTP.statusCode) else {
                errorMessage = "Couldn't load contributions."
                return
            }
            deposits = try JSONDecoder().decode([SharedDepositRecord].self, from: depositData)
        } catch {
            errorMessage = "Couldn't load the shared budget."
        }
    }

    /// Tags a deposit with who made it, then re-syncs so the combined
    /// total reflects both contributors. Returns the new combined total
    /// so the caller can true up the local goal's currentSavings —
    /// authoritative from the server rather than a local increment, since
    /// the partner's deposits also count.
    ///
    /// Unlike the old version, this now actually checks the response
    /// instead of discarding it with `try?` — a failed insert (RLS
    /// rejection, network error, bad payload) used to fail completely
    /// silently: the UI would just re-load the same old total and look
    /// like nothing happened, with zero indication of why. Now a failure
    /// populates `errorMessage` with the real reason, same as every other
    /// method in this file.
    @discardableResult
    func addDeposit(sharedGoalID: String, contributorID: String, contributorName: String, amount: Double, accessToken: String?) async -> Double? {
        guard let accessToken else {
            errorMessage = "Sign in to add a deposit."
            return nil
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let payload: [String: Any] = [
            "shared_goal_id": sharedGoalID,
            "contributor_id": contributorID,
            "contributor_name": contributorName,
            "amount": amount
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            errorMessage = "Couldn't add that deposit."
            return nil
        }
        let req = request(path: "shared_deposits", method: "POST", accessToken: accessToken, body: body, extraHeaders: ["Prefer": "return=representation"])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = body["message"] as? String {
                    errorMessage = message
                } else {
                    errorMessage = "Couldn't add that deposit."
                }
                return nil
            }
        } catch {
            errorMessage = "Couldn't add that deposit."
            return nil
        }

        await loadShare(id: sharedGoalID, accessToken: accessToken)
        return totalContributed
    }

    /// Leaves a shared budget via the `leave_shared_goal` RPC — mirrors
    /// `join_shared_goal`. shared_goals has no authenticated UPDATE/
    /// DELETE policy (see supabase.sql), so this can't be done with a
    /// plain PATCH/DELETE; the security-definer function derives "am I
    /// the owner or the partner" from the caller's own token
    /// server-side instead of trusting a client-supplied flag.
    @discardableResult
    func leaveShare(sharedGoalID: String, accessToken: String?) async -> Bool {
        guard let accessToken else {
            errorMessage = "Sign in to leave a shared budget."
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let payload: [String: Any] = ["p_shared_goal_id": sharedGoalID]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            errorMessage = "Couldn't leave the shared budget."
            return false
        }
        let req = request(path: "rpc/leave_shared_goal", method: "POST", accessToken: accessToken, body: body, extraHeaders: ["Prefer": "return=representation"])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = body["message"] as? String {
                    errorMessage = message
                } else {
                    errorMessage = "Couldn't leave the shared budget."
                }
                return false
            }
        } catch {
            errorMessage = "Couldn't leave the shared budget."
            return false
        }

        share = nil
        deposits = []
        return true
    }
}
