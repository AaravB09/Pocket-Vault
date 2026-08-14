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
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        goalStore.setActive(goal.id)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: (GoalKind(rawValue: goal.kindRaw) ?? .custom).displayIcon)
                                .font(theme.font(11, weight: .light))
                            Text(goal.title.uppercased())
                                .font(theme.font(10, weight: .bold))
                                .tracking(1.5)
                            if goal.sharedGoalID != nil {
                                Image(systemName: "person.2.fill")
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
            .padding(.horizontal, 24)
        }
    }
}
