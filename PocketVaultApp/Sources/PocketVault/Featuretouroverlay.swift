import SwiftUI

/// Sentinel key (in the "tourOverlay" coordinate space frame dictionary)
/// for the MORE button's measured frame — kept separate from real
/// tabIndex values (0-7) so it can't collide with one.
let tourMoreButtonKey = -1000

struct TourStep: Identifiable {
    let id = UUID()
    let tabIndex: Int
    let title: String
    let message: String
    let icon: String
    // FIX: `icon` used to be handed straight to `Image(systemName:)` at
    // the call site below — not routed through `Image.platformSymbol`.
    // "cube.fill", "hammer.fill", "target", and "chart.pie.fill" are the
    // exact 4 icons MainTabView.swift already documents as outside
    // Skip's Android fallback table (see its LiquidTabButton call sites,
    // which substitute house.fill/wrench.fill/mappin.circle.fill/
    // list.bullet for these same 4 tabs) — so 4 of these 7 tour steps
    // were showing the "symbol not found" warning triangle instead of
    // the actual tab icon during a new user's first-run tour on Android.
    // Reusing MainTabView's exact substitutes for consistency.
    let androidIcon: String
}

/// A lightweight coach-mark tour: dims the screen, shows a card pointing at
/// one tab at a time, and actually switches `selectedTab` so the real
/// screen previews live behind the dimmed overlay as the user taps Next.
///
/// The bottom bar now has a permanent slot for every reachable tab — VAULT,
/// BUILD, GOALS, BUDGET, CALENDAR, and (unless the user is already Pro,
/// which drops it) PRO. `mainTabOrder` is those slots, in their actual
/// left-to-right order. `moreTabOrder` is legacy/empty now that there's no
/// MORE popover, kept only so older call sites still compile.
///
/// Ask AI lives in a floating bubble rather than a bottom-bar slot, so
/// its step is special-cased (see `askAITabIndex`) and always shown
/// regardless of the tab orders above.
struct FeatureTourOverlay: View {
    @EnvironmentObject var theme: ThemeManager
    @Binding var isPresented: Bool
    @Binding var selectedTab: Int
    let totalTabs: Int
    var mainTabOrder: [Int] = [0, 1, 3, 7, 2, 5]
    var moreTabOrder: [Int] = []

    /// Real, measured frames of the tab-bar buttons / Ask AI bubble, in
    /// the shared "tourOverlay" coordinate space, keyed by tabIndex (and
    /// `tourMoreButtonKey` for the MORE button). Supplied live by
    /// MainTabView via TourAnchorPreferenceKey, so the arrow always lands
    /// on the real element instead of a guessed position.
    var tourFrames: [Int: CGRect] = [:]

    @State private var stepIndex: Int = 0

    // Ask AI's `selectedTab` value — same one AskAIBubble uses in
    // MainTabView. It's never part of the tab bar since it isn't a
    // bottom-bar slot; the Ask AI step is special-cased below instead.
    private let askAITabIndex = 4

    private let steps: [TourStep] = [
        TourStep(
            tabIndex: 0,
            title: "Your Vault",
            message: "Track progress toward your goal and drop in deposits. Tap the icon top-left anytime to edit your profile.",
            icon: "cube.fill",
            androidIcon: "house.fill"
        ),
        TourStep(
            tabIndex: 1,
            title: "Build Studio",
            message: "Watch a 3D model of your goal assemble itself, piece by piece, as you save. Drag to spin it around.",
            icon: "hammer.fill",
            androidIcon: "wrench.fill"
        ),
        TourStep(
            tabIndex: 3,
            title: "Goals",
            message: "Change what you're saving for, your target amount, or your target date anytime.",
            icon: "target",
            androidIcon: "mappin.circle.fill"
        ),
        TourStep(
            tabIndex: 7,
            title: "Budget",
            message: "Track monthly spending by category and see when you're getting close to your limit.",
            icon: "chart.pie.fill",
            androidIcon: "list.bullet"
        ),
        TourStep(
            tabIndex: 2,
            title: "Calendar",
            message: "See your deposit streak, your best streak ever, and a forecasted completion date.",
            icon: "calendar",
            androidIcon: "calendar"
        ),
        TourStep(
            tabIndex: 5,
            title: "Go Pro",
            message: "Unlock your AI savings coach and more — upgrade anytime.",
            icon: "crown.fill",
            androidIcon: "crown.fill"
        ),
        TourStep(
            tabIndex: 4,
            title: "Ask AI",
            message: "Tap the sparkle bubble anytime to chat with your AI savings coach about pacing, trade-offs, or ways to hit your goal faster.",
            icon: "sparkles",
            androidIcon: "star.fill"
        )
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { advance() }

                if stepIndex < visibleSteps.count {
                    let step = visibleSteps[stepIndex]

                    // True target point — the real, measured center (Ask
                    // AI) or top-center (tab/MORE button) of the element
                    // this step points at. NOT clamped, since this is
                    // where the arrow tip must actually land.
                    let target = targetPoint(for: step, geo: geo)
                    let targetX = target.x
                    let targetY = target.y

                    // Card position IS clamped so it stays fully
                    // on-screen even when the target is near an edge.
                    let cardX = clampedX(arrowX: targetX, screenWidth: geo.size.width)
                    let cardY = cardCenterY(for: step, target: target)

                    let cardWidth: CGFloat = 260

                    ZStack {
                        VStack(spacing: 10) {
                            Image.platformSymbol(step.icon, android: step.androidIcon).font(theme.font(22, weight: Font.Weight.bold)).foregroundStyle(theme.accent)
                            Text(step.title)
                                .font(theme.font(15, weight: Font.Weight.semibold))
                                .foregroundStyle(HierarchicalShapeStyle.primary)
                            Text(step.message)
                                .font(theme.font(12, weight: Font.Weight.light))
                                .foregroundStyle(theme.textPrimary.opacity(0.7))
                                .multilineTextAlignment(TextAlignment.center)

                            HStack(spacing: 12) {
                                Button("Skip") { finish() }
                                    .font(theme.font(11)).foregroundStyle(HierarchicalShapeStyle.secondary) // was .tertiary
                                Spacer()
                                Text("\(stepIndex + 1)/\(visibleSteps.count)")
                                    .font(theme.font(11)).foregroundStyle(HierarchicalShapeStyle.secondary) // was .tertiary
                                Spacer()
                                Button(stepIndex == visibleSteps.count - 1 ? "Done" : "Next") { advance() }
                                    .font(theme.font(12, weight: Font.Weight.bold))
                                    .foregroundStyle(theme.onAccent)
                                    .padding(Edge.Set.horizontal, 18).padding(Edge.Set.vertical, 10)
                                    .background(theme.accent)
                                    .clipShape(Capsule())
                                    .shadow(color: theme.accent.opacity(0.4), radius: 8, y: 3)
                            }
                        }
                        .padding(18)
                        .frame(width: cardWidth)
                        // NOTE(skip): .ultraThinMaterial has no Android
                        // equivalent — was cascading into the .clipShape
                        // right below it.
                        .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.accent.opacity(0.4), lineWidth: 1))
                        .position(x: cardX, y: cardY)

                        // Arrow is positioned independently at the true
                        // target point, not relative to the card, so it
                        // always lands on the tab/bubble even when the
                        // card itself has been clamped away from it.
                        // Nudged off the icon itself (up for tab arrows,
                        // left for the Ask AI arrow) so the tip points at
                        // the icon instead of overlapping it.
                        if step.tabIndex == askAITabIndex {
                            Image.platformSymbol("arrowtriangle.right.fill", android: "chevron.right")
                                .font(theme.font(12))
                                .foregroundStyle(theme.accent)
                                .position(x: targetX - 28, y: targetY)
                        } else {
                            // FIX: was `Image(systemName: "arrowtriangle.down.fill")`
                            // directly — the sibling `arrowtriangle.right.fill`
                            // arrow just above is already routed through
                            // platformSymbol (-> "chevron.right"), implying
                            // arrowtriangle.*.fill isn't in Skip's Android
                            // fallback table either; this one was just missed.
                            Image.platformSymbol("arrowtriangle.down.fill", android: "chevron.down")
                                .font(theme.font(12))
                                .foregroundStyle(theme.accent)
                                .position(x: targetX, y: targetY - 14)
                        }
                    }
                }
            }
        }
        .onChange(of: stepIndex) { newValue in
            if newValue < visibleSteps.count { selectedTab = visibleSteps[newValue].tabIndex }
        }
        .onAppear {
            if !visibleSteps.isEmpty { selectedTab = visibleSteps[0].tabIndex }
        }
    }

    /// Only show steps for tabs actually reachable right now (e.g. Go Pro
    /// drops out of `moreTabOrder` once the user is Pro), plus the Ask AI
    /// step, which is always shown since the floating bubble is always
    /// present regardless of tab layout.
    private var visibleSteps: [TourStep] {
        steps.filter {
            $0.tabIndex == askAITabIndex
                || mainTabOrder.contains($0.tabIndex)
                || moreTabOrder.contains($0.tabIndex)
        }
    }

    private func clampedX(arrowX: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let cardHalfWidth: CGFloat = 138
        return min(max(arrowX, cardHalfWidth), screenWidth - cardHalfWidth)
    }

    /// Where the arrow tip should actually land — the real, measured
    /// center of the Ask AI bubble, or the real top-center of the tab /
    /// MORE button — independent of the card's own (possibly clamped)
    /// position. Pulled out of `body` as a plain function (rather than an
    /// inline `if/else` inside the ZStack) because a bare `if/else` that
    /// returns a value gets parsed by the @ViewBuilder as View-building
    /// content, which fails to compile since neither branch produces a
    /// View.
    ///
    /// Falls back to a rough on-screen guess only for the rare case this
    /// renders before MainTabView's frame-reporting preferences have
    /// propagated (they're normally already populated, since the tab bar
    /// is on screen well before the tour opens).
    private func targetPoint(for step: TourStep, geo: GeometryProxy) -> CGPoint {
        if let frame = tourFrames[step.tabIndex] {
            return step.tabIndex == askAITabIndex
                ? CGPoint(x: frame.midX, y: frame.midY)
                : CGPoint(x: frame.midX, y: frame.minY)
        }
        if step.tabIndex != askAITabIndex,
           !mainTabOrder.contains(step.tabIndex),
           let moreFrame = tourFrames[tourMoreButtonKey] {
            return CGPoint(x: moreFrame.midX, y: moreFrame.minY)
        }
        // Fallback: rough guess near the bottom bar / bubble corner.
        return step.tabIndex == askAITabIndex
            ? CGPoint(x: geo.size.width - 66, y: geo.size.height / 2 - 60)
            : CGPoint(x: geo.size.width / 2, y: geo.size.height - 90)
    }

    /// Vertical center for the coach-mark card, placed above the real
    /// target point so the arrow lands on the actual button/bubble
    /// instead of pointing at empty space.
    private func cardCenterY(for step: TourStep, target: CGPoint) -> CGFloat {
        if step.tabIndex == askAITabIndex {
            // Card sits above the bubble with room for the sideways
            // arrow's row plus a gap, so the two don't overlap.
            return target.y - 130
        } else {
            // Card sits above the tab bar row, with room for the card's
            // own height (~240pt) plus the downward arrow beneath it.
            return target.y - 120
        }
    }

    private func advance() {
        if stepIndex < visibleSteps.count - 1 {
            stepIndex += 1
        } else {
            finish()
        }
    }

    private func finish() {
        isPresented = false
    }
}
