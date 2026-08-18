import Foundation
#if !SKIP
import UIKit
#endif
import Combine

/// Backs the in-app Feedback sheet. Same Supabase project and REST
/// request pattern as LeaderboardManager/SharedBudgetManager — see
/// supabase_feedback.sql for the one-time table setup this depends on:
///
///   create table feedback (
///     id uuid primary key default gen_random_uuid(),
///     user_id text,
///     display_name text,
///     message text not null,
///     app_version text,
///     build_number text,
///     ios_version text,
///     device_model text,
///     created_at timestamptz default now()
///   );
///   alter table feedback enable row level security;
///   create policy "anyone can insert feedback" on feedback
///     for insert with check (true);
@MainActor
final class FeedbackManager: ObservableObject {
    @Published var isSubmitting = false
    @Published var didSubmitSuccessfully = false
    @Published var errorMessage: String?

    private func request(path: String, method: String = "POST", body: Data?, extraHeaders: [String: String] = [:]) -> URLRequest {
        var req = URLRequest(url: SupabaseConfig.restURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        for (key, value) in extraHeaders { req.setValue(value, forHTTPHeaderField: key) }
        req.httpBody = body
        return req
    }

    func submit(message: String, userID: String?, displayName: String?) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        // UIDevice is UIKit-only, so it's not available under Skip —
        // Android just reports itself plainly instead.
        #if !SKIP
        let osVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        #else
        let osVersion = "Android"
        let deviceModel = "Android"
        #endif

        let payload: [String: Any?] = [
            "user_id": userID,
            "display_name": displayName,
            "message": trimmed,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            "ios_version": osVersion,
            "device_model": deviceModel
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 }) else {
            errorMessage = "Couldn't prepare that feedback. Try again."
            return
        }

        let req = request(path: "feedback", body: body, extraHeaders: ["Prefer": "return=minimal"])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "Couldn't send feedback right now. Try again shortly."
                return
            }
            _ = data
            didSubmitSuccessfully = true
        } catch {
            errorMessage = "Couldn't send feedback — check your connection."
        }
    }
}
