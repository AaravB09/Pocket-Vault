import SwiftUI

/// Shown in place of a feature's content when a guest hits something that
/// requires a real account — Friends/Leaderboard and Shared Budget, both
/// of which need a verifiable server-side identity (auth.uid()) for their
/// Row Level Security policies to mean anything. A guest's local random
/// ID can't be cryptographically checked by Postgres, so rather than
/// silently trusting a self-declared ID (the bug this replaces), guests
/// are stopped here with a clear explanation and a one-tap path to a free
/// account — same visual language as the Pro paywall lock, since this is
/// the same "you need X to continue" pattern, just for account status
/// instead of subscription status.
struct AccountRequiredGateView: View {
    @EnvironmentObject var theme: ThemeManager
    let featureName: String
    let message: String

    @State private var showSignUp: Bool = false

    init(featureName: String, message: String? = nil) {
        self.featureName = featureName
        self.message = message ?? "Sign in with a free account to use \(featureName) — it needs a verified identity so the data stays private between you and the people you choose."
    }

    var body: some View {
        ZStack {
            VStack(spacing: 22.0) {
                Spacer()

                ZStack {
                    Circle().fill(theme.accent.opacity(0.12)).frame(width: 76.0, height: 76.0)
                    Image(systemName: "lock.fill")
                        .font(theme.font(26.0, weight: Font.Weight.light))
                        .foregroundStyle(theme.accent)
                }

                VStack(spacing: 8.0) {
                    SectionLabel("Account required")

                    Text(featureName)
                        .font(theme.font(20.0, weight: Font.Weight.light))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(TextAlignment.center)
                }

                Text(message)
                    .font(theme.font(13.0, weight: Font.Weight.light))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(TextAlignment.center)
                    .padding(Edge.Set.horizontal, Layout.pageMargin)

                PrimaryCTAButton(accent: theme.accent, onAccent: theme.onAccent, action: { showSignUp = true }) {
                    Text("Create free account")
                }
                .padding(Edge.Set.horizontal, Layout.pageMargin)
                .padding(Edge.Set.top, 6.0)

                Spacer()
                Spacer()
            }
        }
        .themedSurface(ignoresSafeArea: true)
        .sheet(isPresented: $showSignUp) {
            LoginView(hideGuestOption: true)
        }
    }
}
