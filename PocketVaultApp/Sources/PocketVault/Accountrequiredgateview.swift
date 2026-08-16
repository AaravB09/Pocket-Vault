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
            VStack(spacing: 22) {
                Spacer()

                ZStack {
                    Circle().fill(theme.accent.opacity(0.12)).frame(width: 76, height: 76)
                    Image(systemName: "lock.fill")
                        .font(theme.font(26, weight: .light))
                        .foregroundStyle(theme.accent)
                }

                VStack(spacing: 8) {
                    SectionLabel("Account required")

                    Text(featureName)
                        .font(theme.font(20, weight: .light))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                }

                Text(message)
                    .font(theme.font(13, weight: .light))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Layout.pageMargin)

                Button(action: { showSignUp = true }) {
                    Text("Create free account")
                }
                .buttonStyle(.primaryCTA(theme))
                .padding(.horizontal, Layout.pageMargin)
                .padding(.top, 6)

                Spacer()
                Spacer()
            }
        }
        .themedSurface(theme)
        .sheet(isPresented: $showSignUp) {
            LoginView(hideGuestOption: true)
        }
    }
}
