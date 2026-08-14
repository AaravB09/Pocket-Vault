import Foundation
import Combine
import LinkKit // Add via SPM: https://github.com/plaid/plaid-link-ios-spm.git

/// Drives the "Connect Bank" flow in the Budget tab: fetches a Link
/// token from your Supabase proxy, launches Plaid Link's own hosted UI
/// for the user to pick their bank and log in (Pocket Vault never sees
/// their bank credentials), exchanges the resulting public token for a
/// permanent connection, then syncs new transactions into BudgetManager.
///
/// Every Edge Function call below sends the signed-in user's real
/// Supabase session token (AuthManager.accessToken) as the Authorization
/// header. The functions verify that token server-side and derive the
/// user's identity from it — they do NOT trust a client-supplied
/// user_id, since the anon key is public and anyone could put whatever
/// id they want in a request body. Guests have no real session, so
/// every method here requires a non-nil accessToken and fails fast
/// with a clear message if one isn't available, rather than silently
/// no-op'ing or (worse) letting a guest's local-only ID reach the
/// backend as if it meant something.
///
/// Same Supabase project + request shape as SavingsCoachService — see
/// supabase_plaid_setup.md for the three Edge Functions this calls, and
/// supabase_plaid_setup.sql for the RLS policies protecting the tables
/// they read/write.
@MainActor
final class PlaidConnectionManager: ObservableObject {
    @Published var isConnecting = false
    @Published var isSyncing = false
    @Published var isConnected = false
    @Published var errorMessage: String?

    private static let functionsBase = SupabaseConfig.projectURL.appendingPathComponent("functions/v1")

    private func request(function: String, body: [String: Any], accessToken: String) throws -> URLRequest {
        var req = URLRequest(url: Self.functionsBase.appendingPathComponent(function))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Step 1: get a Link token, then hand it to Plaid's LinkKit to
    /// present the hosted bank-picker UI. Call this from a button action.
    func startConnection(accessToken: String?, presenting: (LinkTokenConfiguration) -> Void) async {
        guard let accessToken else {
            errorMessage = "Sign in to connect a bank."
            return
        }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            let req = try request(function: "plaid-link-token", body: [:], accessToken: accessToken)
            let (data, response) = try await URLSession.shared.data(for: req)

            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                print("plaid-link-token failed:", (response as? HTTPURLResponse)?.statusCode ?? -1,
                      String(data: data, encoding: .utf8) ?? "<no body>")
                errorMessage = "Couldn't start the bank connection. Try again."
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let linkToken = json["link_token"] as? String else {
                print("plaid-link-token bad body:", String(data: data, encoding: .utf8) ?? "<no body>")
                errorMessage = "Couldn't start the bank connection. Try again."
                return
            }

            let config = LinkTokenConfiguration(
                token: linkToken,
                onSuccess: { success in
                    Task { await self.exchangePublicToken(success.publicToken, accessToken: accessToken) }
                },
                onExit: { exit in
                    if let error = exit.error {
                        // v7 update: use .errorMessage or .displayMessage
                        Task { @MainActor in self.errorMessage = error.errorMessage }
                    }
                },
                onEvent: nil, // v7 update: explicitly required to pass nil
                onLoad: nil   // v7 update: explicitly required to pass nil
            )

            presenting(config)
        } catch {
            errorMessage = "Couldn't start the bank connection. Try again."
        }
    }

    /// Step 2: exchange Plaid's short-lived public token for a permanent
    /// access token, stored server-side only (never sent to this device).
    private func exchangePublicToken(_ publicToken: String, accessToken: String) async {
        do {
            let req = try request(function: "plaid-exchange-token", body: ["public_token": publicToken], accessToken: accessToken)
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "Bank connected, but saving it failed. Try again."
                return
            }
            isConnected = true
            await syncTransactions(accessToken: accessToken, into: nil)
        } catch {
            errorMessage = "Bank connected, but saving it failed. Try again."
        }
    }

    /// Step 3: pull newly-added transactions and hand them to
    /// BudgetManager, which dedupes by plaidTransactionID. Call this on
    /// Budget tab appear + pull-to-refresh, same pattern as
    /// LeaderboardManager.fetchLeaderboard().
    func syncTransactions(accessToken: String?, into budgetManager: BudgetManager?) async {
        guard let accessToken else { return } // guests: nothing to sync, no session to check with
        isSyncing = true
        defer { isSyncing = false }

        do {
            let req = try request(function: "plaid-sync-transactions", body: [:], accessToken: accessToken)
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "Couldn't sync transactions."
                return
            }
            await fetchStoredTransactions(accessToken: accessToken, into: budgetManager)
        } catch {
            errorMessage = "Couldn't sync transactions."
        }
    }

    /// Reads the already-synced rows back from Supabase (the sync step
    /// above just imports Plaid -> your table; this pulls your table ->
    /// the app) and merges them into BudgetManager's log. Sends the
    /// user's own session token as Authorization (not the anon key) so
    /// the plaid_transactions RLS policy (user_id = auth.uid()) actually
    /// scopes this to their own rows — the anon key alone has no
    /// identity for RLS to check against.
    private func fetchStoredTransactions(accessToken: String, into budgetManager: BudgetManager?) async {
        guard let budgetManager else { return }
        var components = URLComponents(url: SupabaseConfig.restURL.appendingPathComponent("plaid_transactions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "order", value: "date.desc"),
            URLQueryItem(name: "limit", value: "200")
        ]
        var req = URLRequest(url: components.url!)
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey") // required by PostgREST, identifies the project
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") // identifies the user, for RLS

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([PlaidTransactionRow].self, from: data) else { return }

        budgetManager.mergeImportedTransactions(rows)
    }
}

struct PlaidTransactionRow: Codable {
    let plaid_transaction_id: String
    let amount: Double
    let merchant_name: String?
    let category: String?
    let date: String
}
