import SwiftUI

/// Horizontal picker for switching between simultaneous goals, plus a
/// trailing "+" to start a new one. Sits at the top of the Vault tab.
struct GoalPickerBar: View {
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var goalStore: GoalStore
    var onAddGoal: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(goalStore.goals) { goal in
                    let isActive = goal.id == goalStore.activeGoal?.id

                    Button(action: {
                        #if !SKIP
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        goalStore.setActive(goal.id)
                    }) {
                        HStack(spacing: 6) {
                            // FIX: was `Image(systemName: ....displayIcon)`
                            // directly — see the note on
                            // GoalKind.androidDisplayIcon in
                            // Goalbuildmodels.swift. Bypassing
                            // platformSymbol() here meant a car, gaming
                            // rig, emergency fund, or custom goal chip
                            // rendered the "symbol not found" warning
                            // triangle on Android instead of its icon.
                            let kind = GoalKind(rawValue: goal.kindRaw) ?? .custom
                            Image.platformSymbol(kind.displayIcon, android: kind.androidDisplayIcon)
                                .font(theme.font(11, weight: .light))
                            Text(goal.title)
                                .font(theme.font(12, weight: .semibold))
                            if goal.sharedGoalID != nil {
                                Image.platformSymbol("person.2.fill", android: "person.fill")
                                    .font(theme.font(9, weight: .semibold))
                                    .opacity(0.8)
                            }
                        }
                        .foregroundStyle(isActive ? theme.onAccent : theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(isActive ? theme.accent : (theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06)))
                        )
                        .overlay(
                            Capsule().stroke(isActive ? Color.clear : theme.cardStroke, lineWidth: 1)
                        )
                    }
                }

                Button(action: onAddGoal) {
                    Image(systemName: "plus")
                        .font(theme.font(12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06)))
                        .overlay(Circle().stroke(theme.accent.opacity(0.4), lineWidth: 1))
                }
            }
            .padding(.horizontal, Layout.pageMargin)
        }
    }
}
