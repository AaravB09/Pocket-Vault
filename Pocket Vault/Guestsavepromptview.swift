import SwiftUI

/// Fires once, after onboarding + the feature tour, for guests only.
/// Loss-Aversion framed deliberately: the pain of losing what they've
/// already built (their goal, their streak) is a stronger motivator than
/// "sign up to unlock features" would be — and it's true, not manipulative,
/// since guest data really does only live on this device.
struct GuestSavePromptView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var goalStore: GoalStore

    @State private var showSignUp: Bool = false

    private var goalName: String { goalStore.activeGoal?.title ?? "your goal" }

    var body: some View {
        ZStack {
            VStack(spacing: 22) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(theme.font(34, weight: .light))
                    .foregroundStyle(theme.accent)
                    .padding(.top, 50)

                VStack(spacing: 8) {
                    Text("DON'T LOSE YOUR PROGRESS")
                        .font(theme.font(10, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(theme.accent)

                    Text("\(goalName) only lives on this device")
                        .font(theme.font(20, weight: .light))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                Text(streakManager.currentStreak > 0
                     ? "If you lose this device or delete the app, your \(streakManager.currentStreak)-day streak and everything you've built disappears with it. A free account keeps it safe."
                     : "If you lose this device or delete the app, everything you've built disappears with it. A free account keeps it safe.")
                    .font(theme.font(13, weight: .light))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                Button(action: { showSignUp = true }) {
                    Text("CREATE FREE ACCOUNT")
                        .font(theme.font(13, weight: .bold))
                        .tracking(2.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(theme.textPrimary)
                        .foregroundColor(theme.background)
                        .clipShape(Capsule())
                        .shadow(color: theme.textPrimary.opacity(0.25), radius: 16, y: 8)
                }
                .padding(.horizontal, 30)

                Button(action: { dismiss() }) {
                    Text("Not now")
                        .font(theme.font(12, weight: .light))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()
            }
        }
        .themedSurface(theme)
        .sheet(isPresented: $showSignUp) {
            LoginView()
        }
    }
}
