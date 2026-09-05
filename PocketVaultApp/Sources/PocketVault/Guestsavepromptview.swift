import SwiftUI

/// Fires once, after onboarding + the feature tour, for guests only.
/// Loss-Aversion framed deliberately: the pain of losing what they've
/// already built (their goal, their streak) is a stronger motivator than
/// "sign up to unlock features" would be — and it's true, not manipulative,
/// since guest data really does only live on this device.
public struct GuestSavePromptView: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var goalStore: GoalStore

    @State private var showSignUp: Bool = false

    private var goalName: String { goalStore.activeGoal?.title ?? "your goal" }

    public var body: some View {
        ZStack {
            VStack(spacing: 22) {
                Image.platformSymbol("exclamationmark.icloud.fill", android: "exclamationmark.triangle.fill")
                    .font(theme.font(34, weight: Font.Weight.light))
                    .foregroundStyle(theme.accent)
                    .padding(Edge.Set.top, 50)

                VStack(spacing: 8) {
                    SectionLabel("Don't lose your progress")

                    Text("\(goalName) only lives on this device")
                        .font(theme.font(20, weight: Font.Weight.light))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(TextAlignment.center)
                        .padding(Edge.Set.horizontal, Layout.pageMargin)
                }

                Text(streakManager.currentStreak > 0
                     ? "If you lose this device or delete the app, your \(streakManager.currentStreak)-day streak and everything you've built disappears with it. A free account keeps it safe."
                     : "If you lose this device or delete the app, everything you've built disappears with it. A free account keeps it safe.")
                    .font(theme.font(13, weight: Font.Weight.light))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(TextAlignment.center)
                    .padding(Edge.Set.horizontal, Layout.pageMargin)

// Refactored to use VaultButton for consistent cross-platform button styling
                VaultButton("Create free account", variant: .primary) {
                    showSignUp = true
                }
                .padding(Edge.Set.horizontal, Layout.pageMargin)

                // Tertiary text button for secondary action
                VaultButton("Not now", variant: .tertiary) {
                    dismiss()
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
