import Foundation

/// Config for the Friends/Leaderboard backend. This talks to Supabase's
/// auto-generated REST API (PostgREST) directly over HTTPS, so there's no
/// SDK dependency to add — just fill in the two values below.
///
/// SETUP:
/// 1. Run supabase_schema.sql once in your Supabase project's SQL editor
///    (Dashboard → SQL Editor → New query → paste → Run).
/// 2. Go to Project Settings → API and copy your Project URL and anon
///    public key into the constants below.
enum SupabaseConfig {
    // Same project the AI coach proxy (SavingsCoachService) already uses.
    static let projectURL = URL(string: "https://hbbyrgmckacgbqqtteaq.supabase.co")!

    // Project Settings → API → "anon" "public" key. This is safe to ship
    // client-side by design (like a Stripe publishable key) — it's
    // constrained entirely by the Row Level Security policies in
    // supabase_schema.sql, not a secret.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhiYnlyZ21ja2FjZ2JxcXR0ZWFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4MTY3MDgsImV4cCI6MjEwMTM5MjcwOH0.FiOfcdHMFfFhDRP7LVpxYn3Cy3KIbGtPiaKkNDEDuug"

    static var restURL: URL { projectURL.appendingPathComponent("rest/v1") }
}
