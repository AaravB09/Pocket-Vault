import SwiftUI

/// Horizontal picker for switching between simultaneous goals, plus a
/// trailing "+" to start a new one. Sits at the top of the Vault tab.
struct GoalPickerBar: View {
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var goalStore: GoalStore
    var onAddGoal: () -> Void

    public var body: some View {
        ScrollView(Axis.Set.horizontal, showsIndicators: false) {
            HStack(spacing: 10.0) {
                ForEach(goalStore.goals) { goal in
                    let isActive = goal.id == goalStore.activeGoal?.id
                    let chipFillColor: Color = isActive
                        ? theme.accent
                        : (theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
                    let chipTextColor: Color = isActive ? theme.onAccent : theme.textSecondary

                    Button(action: {
                        #if !SKIP
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        goalStore.setActive(goal.id)
                    }) {
                        HStack(spacing: 6.0) {
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
                                .font(theme.font(11, weight: Font.Weight.light))
                            Text(goal.title)
                                .font(theme.font(12, weight: Font.Weight.semibold))
                            if goal.sharedGoalID != nil {
                                Image.platformSymbol("person.2.fill", android: "person.fill")
                                    .font(theme.font(9, weight: Font.Weight.semibold))
                                    .opacity(0.8)
                            }
                        }
                        .foregroundStyle(chipTextColor)
                        .padding(Edge.Set.horizontal, 14.0)
                        .padding(Edge.Set.vertical, 9.0)
                        // FIX (real root cause): the previous version passed
                        // `Capsule().fill(chipFillColor)` — a filled Shape
                        // *view* — directly as the `.background(...)`
                        // argument. That specific form doesn't come through
                        // on Skip/Android: the chip rendered near-white
                        // regardless of chipFillColor's value, even after
                        // extracting it to a `let`. Every place in this app
                        // that gets this right instead (MainTabView's
                        // LiquidTabButton tab highlight, SavingsTrendChart's
                        // range pill) uses a plain Color background plus a
                        // *separate* `.clipShape(Capsule())` — that's the
                        // pattern that actually renders on both platforms.
                        .background(chipFillColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onAddGoal) {
                    Image(systemName: "plus")
                        .font(theme.font(12, weight: Font.Weight.semibold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 34.0, height: 34.0)
                        // FIX: same Capsule().fill(...)-as-background issue
                        // as the chip above, here with Circle() instead —
                        // switched to background(color) + clipShape(Circle())
                        // for the same reason.
                        .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(theme.accent.opacity(0.4), lineWidth: 1.0))
                }
                .buttonStyle(.plain)
            }
            .padding(Edge.Set.horizontal, Layout.pageMargin)
        }
    }
}
