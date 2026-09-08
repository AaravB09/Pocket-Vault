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
/// The bottom bar has a permanent dock slot for VAULT, BUILD, GOALS, and
/// BUDGET only. `mainTabOrder` also lists CALENDAR and PRO (unless the user
/// is already Pro, which drops it) since those steps still belong in the
/// tour — they just don't point at a dock slot; see
/// `headerAnchoredTabIndices`. `moreTabOrder` is legacy/empty now that
/// there's no MORE popover, kept only so older call sites still compile.
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

    // Calendar and Go Pro no longer have their own bottom-bar dock slot
    // (see MainTabView.tabBarView's comment) — they're reached through
    // the calendar icon and the "Pro" pill in the Vault tab's header
    // (ContentView), which only exist while `selectedTab == 0`. Switching
    // `selectedTab` to 2 or 5 for these steps — the way every real
    // dock-slot step does — would unmount the exact button the arrow is
    // supposed to land on, so these two are special-cased the same way
    // Ask AI already is: the tab is kept on Vault, and the arrow points
    // up into the header button instead of down into a dock slot.
    private let headerAnchoredTabIndices: Set<Int> = [2, 5]

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

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { advance() }

                if stepIndex < visibleSteps.count {
                    let step = visibleSteps[stepIndex]

                    if let target = targetRect(for: step, geo: geo) {
                        let targetPoint = targetPoint(from: target, for: step)
                        let cardWidth: CGFloat = min(280.0, max(240.0, geo.size.width - 32.0))
                        let cardHeight: CGFloat = 230.0
                        let gap: CGFloat = 22.0

                        let placeCardAbove = shouldPlaceCardAbove(step: step, target: target, screenHeight: geo.size.height)
                        let proposedCardY: CGFloat = placeCardAbove
                            ? targetPoint.y - (cardHeight / 2.0) - gap
                            : targetPoint.y + (cardHeight / 2.0) + gap
                        let cardY = min(max(proposedCardY, cardHeight / 2.0 + 12.0), geo.size.height - cardHeight / 2.0 - 12.0)
                        let cardX = min(max(targetPoint.x, cardWidth / 2.0 + 12.0), geo.size.width - cardWidth / 2.0 - 12.0)

                        VStack(spacing: 10.0) {
                            Image.platformSymbol(step.icon, android: step.androidIcon)
                                .font(theme.font(22, weight: Font.Weight.bold))
                                .foregroundStyle(theme.accent)

                            Text(step.title)
                                .font(theme.font(15, weight: Font.Weight.semibold))
                                #if !SKIP
                                .foregroundStyle(HierarchicalShapeStyle.primary)
                                #else
                                .foregroundStyle(Color.primary)
                                #endif

                            Text(step.message)
                                .font(theme.font(12, weight: Font.Weight.light))
                                .foregroundStyle(theme.textPrimary.opacity(0.7))
                                .multilineTextAlignment(TextAlignment.center)

                            HStack(spacing: 12.0) {
                                Button("Skip") { finish() }
                                    .font(theme.font(11))
                                    #if !SKIP
                                    .foregroundStyle(HierarchicalShapeStyle.secondary)
                                    #else
                                    .foregroundStyle(Color.secondary)
                                    #endif

                                Spacer()

                                Text("\(stepIndex + 1)/\(visibleSteps.count)")
                                    .font(theme.font(11))
                                    #if !SKIP
                                    .foregroundStyle(HierarchicalShapeStyle.secondary)
                                    #else
                                    .foregroundStyle(Color.secondary)
                                    #endif

                                Spacer()

                                Button(stepIndex == visibleSteps.count - 1 ? "Done" : "Next") { advance() }
                                    .font(theme.font(12, weight: Font.Weight.bold))
                                    .foregroundStyle(theme.onAccent)
                                    .padding(Edge.Set.horizontal, 18.0)
                                    .padding(Edge.Set.vertical, 10.0)
                                    .background(theme.accent)
                                    .clipShape(Capsule())
                                    .shadow(color: theme.accent.opacity(0.4), radius: 8, y: 3)
                            }
                        }
                        .padding(18.0)
                        .frame(width: cardWidth, height: cardHeight)
                        .background(theme.isLight ? Color.white.opacity(0.94) : Color.black.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 18.0))
                        .position(x: cardX, y: cardY)

                        TourArrow(
                            step: step,
                            target: targetPoint,
                            cardCenter: CGPoint(x: cardX, y: cardY),
                            placeCardAbove: placeCardAbove,
                            accent: theme.accent
                        )
                    }
                }
            }
        }
        .onChange(of: stepIndex) { newValue in
            if newValue < visibleSteps.count {
                selectedTab = tabToShow(for: visibleSteps[newValue])
            }
        }
        .onAppear {
            if !visibleSteps.isEmpty {
                selectedTab = tabToShow(for: visibleSteps[0])
            }
        }
    }

    private struct TourArrow: View {
        let step: TourStep
        let target: CGPoint
        let cardCenter: CGPoint
        let placeCardAbove: Bool
        let accent: Color

        var body: some View {
            let dx = target.x - cardCenter.x
            let dy = target.y - cardCenter.y
            let angle = atan2(dy, dx)

            Image.platformSymbol("arrowtriangle.right.fill", android: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
                .rotationEffect(Angle(radians: Double(angle)))
                .position(x: midpointX, y: midpointY)
        }

        private var midpointX: CGFloat {
            cardCenter.x + (target.x - cardCenter.x) * 0.62
        }

        private var midpointY: CGFloat {
            cardCenter.y + (target.y - cardCenter.y) * 0.62
        }
    }

    private func targetRect(for step: TourStep, geo: GeometryProxy) -> CGRect? {
        guard let frame = tourFrames[step.tabIndex] else { return nil }

        let overlayFrame: CGRect
        #if !SKIP
        overlayFrame = geo.frame(in: .global)
        #else
        overlayFrame = geo.frame(in: NamedCoordinateSpace.named("global"))
        #endif

        return frame.offsetBy(dx: -overlayFrame.minX, dy: -overlayFrame.minY)
    }

    private func targetPoint(from target: CGRect, for step: TourStep) -> CGPoint {
        if step.tabIndex == askAITabIndex {
            return CGPoint(x: target.midX, y: target.midY)
        }
        if headerAnchoredTabIndices.contains(step.tabIndex) {
            return CGPoint(x: target.midX, y: target.midY)
        }
        return CGPoint(x: target.midX, y: target.midY)
    }

    private func shouldPlaceCardAbove(step: TourStep, target: CGRect, screenHeight: CGFloat) -> Bool {
        if headerAnchoredTabIndices.contains(step.tabIndex) {
            return false
        }
        if step.tabIndex == askAITabIndex {
            return target.midY > screenHeight * 0.42
        }
        return target.midY > screenHeight * 0.35
    }

    /// The tab that must actually be on screen for `step`'s target button
    /// to exist and be measurable. For every real dock-slot step this is
    /// just the step's own `tabIndex`. Calendar and Go Pro are the
    /// exception — their buttons live in the Vault tab's header, not a
    /// dock slot, so switching `selectedTab` to 2 or 5 would unmount them
    /// instead of revealing them; those two stay pinned to Vault (0).
    private func tabToShow(for step: TourStep) -> Int {
        headerAnchoredTabIndices.contains(step.tabIndex) ? 0 : step.tabIndex
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
    /// Returns the exact target in this overlay's local coordinate space.
    /// MainTabView reports anchors in global coordinates on both platforms.
    /// We subtract this overlay's own global origin before positioning the
    /// arrow, so safe-area insets and nested layout containers cannot shift it.
    private func targetPoint(for step: TourStep, geo: GeometryProxy) -> CGPoint? {
        let overlayGlobalFrame: CGRect
        #if !SKIP
        overlayGlobalFrame = geo.frame(in: .global)
        #else
        overlayGlobalFrame = geo.frame(in: NamedCoordinateSpace.named("global"))
        #endif

        let frame: CGRect? = {
            if let direct = tourFrames[step.tabIndex] {
                return direct
            }
            if step.tabIndex != askAITabIndex,
               !mainTabOrder.contains(step.tabIndex),
               !headerAnchoredTabIndices.contains(step.tabIndex) {
                return tourFrames[tourMoreButtonKey]
            }
            return nil
        }()

        guard let frame else { return nil }

        let globalTarget: CGPoint
        if step.tabIndex == askAITabIndex {
            globalTarget = CGPoint(x: frame.midX, y: frame.midY)
        } else if headerAnchoredTabIndices.contains(step.tabIndex) {
            globalTarget = CGPoint(x: frame.midX, y: frame.maxY)
        } else {
            globalTarget = CGPoint(x: frame.midX, y: frame.minY)
        }

        return CGPoint(
            x: globalTarget.x - overlayGlobalFrame.minX,
            y: globalTarget.y - overlayGlobalFrame.minY
        )
    }

    /// Vertical center for the coach-mark card, placed above the real
    /// target point so the arrow lands on the actual button/bubble
    /// instead of pointing at empty space.
    private func cardCenterY(for step: TourStep, target: CGPoint) -> CGFloat {
        if step.tabIndex == askAITabIndex {
            // Card sits above the bubble with room for the sideways
            // arrow's row plus a gap, so the two don't overlap.
            return target.y - 130
        } else if headerAnchoredTabIndices.contains(step.tabIndex) {
            // Card sits BELOW the header button, mirroring the tab-bar
            // case, since these buttons are near the top of the screen —
            // placing the card above them (like a dock-slot step) would
            // push it off the top edge.
            return target.y + 120
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