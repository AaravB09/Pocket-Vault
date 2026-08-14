import Foundation

/// The value has to match whatever `x-app-secret` your Supabase edge
/// function proxy expects — it's just a shared secret between this app and
/// your own edge function, not a third-party API key. Generate a random one
/// yourself, e.g. `openssl rand -hex 32`, and set the same value as an
/// environment variable/secret on your Supabase edge function so it can
/// check the header matches before calling out to your AI provider.
enum SecretsExample {
    static let appSharedSecret = "your-shared-secret-here"
}
