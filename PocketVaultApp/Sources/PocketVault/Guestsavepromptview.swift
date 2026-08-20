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
                Image.platformSymbol("exclamationmark.icloud.fill", android: "exclamationmark.triangle.fill")
                    .font(theme.font(34, weight: .light))
                    .foregroundStyle(theme.accent)
                    .padding(.top, 50)

                VStack(spacing: 8) {
                    SectionLabel("Don't lose your progress")

                    Text("\(goalName) only lives on this device")
                        .font(theme.font(20, weight: .light))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Layout.pageMargin)
                }

                Text(streakManager.currentStreak > 0
                     ? "If you lose this device or delete the app, your \(streakManager.currentStreak)-day streak and everything you've built disappears with it. A free account keeps it safe."
                     : "If you lose this device or delete the app, everything you've built disappears with it. A free account keeps it safe.")
                    .font(theme.font(13, weight: .light))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Layout.pageMargin)

                // FIX: `.buttonStyle(.primaryCTA(theme))` referenced a
                // custom ButtonStyle static member that no longer exists —
                // same leftover migration gap as every other screen (see
                // PrimaryCTAButton's doc comment in ThemeManager.swift).
                // Use the wrapper directly instead of a Button + buttonStyle
                // pair.
                PrimaryCTAButton(accent: theme.accent, onAccent: theme.onAccent, action: { showSignUp = true }) {
                    Text("Create free account")
                }
                .padding(.horizontal, Layout.pageMargin)

                Button(action: { dismiss() }) {
                    Text("Not now")
                        .font(theme.font(12, weight: .light))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()
            }
        }
        // FIX: Replaced `theme` with `ignoresSafeArea: true` to resolve the compiler error
        .themedSurface(ignoresSafeArea: true)
        .sheet(isPresented: $showSignUp) {
            LoginView()
        }
    }
}
