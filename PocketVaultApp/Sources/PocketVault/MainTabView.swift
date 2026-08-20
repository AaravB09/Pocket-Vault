import SwiftUI

/// Reports the real, on-screen frame of a tab-bar button or the Ask AI
/// bubble (in the shared "tourOverlay" coordinate space) so
/// `FeatureTourOverlay` can point its arrow at the actual element instead
/// of guessing its position from hardcoded screen-height math.
struct TourAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        for (key, rect) in nextValue() {
            value[key] = rect
        }
    }
}

struct MainTabView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("hasSeenFeatureTour") private var hasSeenFeatureTour: Bool = false

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authManager: AuthManager

    let namespace: String

    @StateObject private var goalStore: GoalStore
    @State private var chatMessages: [ChatMessage] = []

    @StateObject private var streakManager: StreakManager
    @StateObject private var entitlementManager = EntitlementManager()
    @StateObject private var leaderboardManager: LeaderboardManager
    @StateObject private var sharedBudgetManager = SharedBudgetManager()
    @StateObject private var budgetManager: BudgetManager
    @StateObject private var privacyManager = PrivacyManager()
    @StateObject private var networkMonitor = NetworkMonitor()

    init(namespace: String) {
        self.namespace = namespace
        _goalStore = StateObject(wrappedValue: GoalStore(namespace: namespace))
        _streakManager = StateObject(wrappedValue: StreakManager(namespace: namespace))
        _leaderboardManager = StateObject(wrappedValue: LeaderboardManager(namespace: namespace))
        _budgetManager = StateObject(wrappedValue: BudgetManager(namespace: namespace))
    }

    @State private var showOnboarding: Bool = false
    @State private var showFeatureTour: Bool = false
    @State private var selectedTab: Int = 0

    // Captured once, from the very first layout pass, and never updated
    // again. BuildStudioView's RealityView (case 1) mounts a RealityKit
    // scene into this same view hierarchy, and RealityKit is known to
    // briefly report a different `safeAreaInsets.bottom` for the whole
    // screen while it's mounted vs. unmounted — which, if the tab bar's
    // position were computed from the *live* safe area, would make the
    // floating bottom bar visibly jump every time you switch to/from the
    // Build tab. Freezing the inset here at launch (before any tab but
    // Vault has ever been shown) means the bar's position no longer reacts
    // to that fluctuation at all, on any tab.
    @State private var fixedBottomSafeInset: CGFloat = 0

    // Ground-truth version of the above, captured directly from UIKit's
    // `safeAreaInsetsDidChange()` via `SafeAreaProbe` rather than
    // SwiftUI's `GeometryReader` propagation. Debug logging confirmed
    // RealityView drives the real inset to 0 while BuildStudioView is
    // mounted and restores it on unmount — this is the value the tab
    // bar and Ask AI bubble now anchor to instead of relying on
    // `.ignoresSafeArea`, which re-resolves against that live 0/normal
    // swing on every layout pass regardless of what we freeze elsewhere.
    @State private var uikitFrozenBottomInset: CGFloat? = nil

    // Updated on every real UIKit safe-area change (not frozen) — used
    // only to compute how far the bar/bubble need to be nudged back to
    // cancel out RealityView's live perturbation, via
    // `bottomInsetCompensation` below.
    @State private var uikitLiveBottomInset: CGFloat = 0

    // How far to push the tab bar / Ask AI bubble back toward their
    // correct resting position. `.ignoresSafeArea(.container, edges:
    // .bottom)` re-adds however much bottom inset is CURRENTLY being
    // reserved — that's live by construction, which is why freezing the
    // padding input alone (fixedBottomSafeInset) never fixed the jump.
    // This compensates by offsetting in the opposite direction whenever
    // the live value drifts from the frozen resting value.
    //
    // 2x, not 1x: `.ignoresSafeArea` re-adds the live inset gap in BOTH
    // the `.padding(.bottom, ...)` layer's resolved position AND the
    // clipping/placement pass that follows it, so a single (frozen -
    // live) delta only ever cancels half the drift. CONFIRMED via
    // [TAB-DEBUG]: raw uncompensated jump measured at ~30.67pt, 1x
    // compensation only clawed back ~15.33pt, leaving the bar resting
    // 15.33pt short. Doubling lands it back on the true resting position.
    private var bottomInsetCompensation: CGFloat {
        ((uikitFrozenBottomInset ?? fixedBottomSafeInset) - uikitLiveBottomInset) * 2
    }

    // Real, measured frames of the tab-bar buttons / Ask AI bubble, keyed
    // by the same tabIndex values FeatureTourOverlay's steps use (and
    // `tourMoreButtonKey` for the MORE button). Populated live via
    // TourAnchorPreferenceKey so the tour's arrow always lands on the
    // actual button, even if paddings/sizes change later.
    @State private var tourFrames: [Int: CGRect] = [:]

    /// Attaches an invisible frame reporter to a view so its on-screen
    /// rect (in the "tourOverlay" coordinate space) gets merged into
    /// `tourFrames` under `key`.
    /// Tab bar's frosted-glass background — real `UIVisualEffectView` on
    /// iOS (via `BlurView`, unavailable under Skip), SwiftUI's own
    /// Material (already used everywhere else in the app) on Android.
    @ViewBuilder
    private var tabBarBlurBackground: some View {
        #if !SKIP
        BlurView(style: themeManager.isLight ? .systemUltraThinMaterialLight : .systemUltraThinMaterialDark)
        #else
        // NOTE(skip): a bare `Color` value returned directly as this
        // @ViewBuilder's result doesn't transpile cleanly — Skip's Compose
        // codegen expects the last statement to be an actual composable
        // invocation, not a plain expression, so it infers `Color` where
        // it wanted `ComposeResult`. Wrapping in `Group { }` forces a
        // proper composable call on both platforms; `Group` renders
        // invisibly either way, so the output is unchanged.
        Group {
            themeManager.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35)
        }
        #endif
    }

    private func tourAnchorReporter(key: Int) -> some View {
        GeometryReader { g in
            Color.clear
                #if !SKIP
                .preference(key: TourAnchorPreferenceKey.self, value: [key: g.frame(in: .named("tourOverlay"))])
                #else
                .preference(key: TourAnchorPreferenceKey.self, value: [key: g.frame(in: .global)])
                #endif
        }
    }

    @State private var onboardingDraftTitle: String = ""
    @State private var onboardingDraftKindRaw: String = GoalKind.flight.rawValue
    @State private var onboardingDraftTarget: Double = 1200
    @State private var onboardingDraftSavings: Double = 0
    @State private var onboardingDraftDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var onboardingDraftVoxelBlueprintJSON: String? = nil

    private let totalTabs = 9

    /// Shows the Shared Budget tab once both people are actually in it —
    /// before that it's a low-frequency setup flow that belongs in
    /// Profile → Friends & Streaks, not permanent real estate in the
    /// bottom bar.
    private var hasActiveSharedBudget: Bool {
        sharedBudgetManager.share?.partner_id != nil
    }

    private var needsOnboarding: Bool {
        !hasCompletedOnboarding || goalStore.goals.isEmpty
    }

    private var goalTitleBinding: Binding<String> {
        Binding(
            get: { goalStore.activeGoal?.title ?? "" },
            set: { newValue in goalStore.mutateActive { $0.title = newValue } }
        )
    }

    private var goalKindRawBinding: Binding<String> {
        Binding(
            get: { goalStore.activeGoal?.kindRaw ?? GoalKind.flight.rawValue },
            set: { newValue in goalStore.mutateActive { $0.kindRaw = newValue } }
        )
    }

    private var currentSavingsBinding: Binding<Double> {
        Binding(
            // NOTE(skip): `?? 0` left the Elvis operator's two branches as
            // Double and Int, which Kotlin can't unify — it infers the
            // intersection type `Number & Comparable<CapturedType(*)>`
            // instead of `Double`, so the closure's return type no longer
            // matches `Binding<Double>`. Explicit `.0` fixes it.
            get: { goalStore.activeGoal?.currentSavings ?? 0.0 },
            set: { newValue in goalStore.mutateActive { $0.currentSavings = newValue } }
        )
    }

    private var targetGoalBinding: Binding<Double> {
        Binding(
            // NOTE(skip): same Elvis-operator type-unification issue as
            // currentSavingsBinding above.
            get: { goalStore.activeGoal?.targetAmount ?? 1200.0 },
            set: { newValue in goalStore.mutateActive { $0.targetAmount = newValue } }
        )
    }

    private var targetDateBinding: Binding<Date> {
        Binding(
            get: { goalStore.activeGoal?.targetDate ?? Calendar.current.date(byAdding: .month, value: 3, to: Date())! },
            set: { newValue in goalStore.mutateActive { $0.targetDate = newValue } }
        )
    }

    private var customVoxelBlueprintBinding: Binding<String?> {
        Binding(
            get: { goalStore.activeGoal?.customVoxelBlueprintJSON },
            set: { newValue in goalStore.mutateActive { $0.customVoxelBlueprintJSON = newValue } }
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            #if !SKIP
            SafeAreaProbe { liveInset in
                uikitLiveBottomInset = liveInset
                // Guard against two things: (1) only ever freeze this
                // once, like the old fixedBottomSafeInset capture did,
                // and (2) don't let a RealityView-driven 0 be the value
                // we freeze — 0 is the known-bad transient this whole
                // probe exists to detect, never the correct resting
                // inset.
                if uikitFrozenBottomInset == nil && liveInset > 0 {
                    uikitFrozenBottomInset = liveInset
                }
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            #endif
            Group {
                switch selectedTab {
                case 0:
                    ContentView(
                        goalTitle: goalTitleBinding,
                        goalKindRaw: goalKindRawBinding,
                        currentSavings: currentSavingsBinding,
                        targetGoal: targetGoalBinding,
                        selectedTab: $selectedTab,
                        chatMessages: $chatMessages,
                        goalStore: goalStore
                    )
                case 1:
                    BuildStudioView(
                        goalTitle: goalTitleBinding,
                        goalKindRaw: goalKindRawBinding,
                        currentSavings: currentSavingsBinding,
                        targetGoal: targetGoalBinding,
                        customVoxelBlueprint: customVoxelBlueprintBinding
                    )
                case 2:
                    CalendarView(
                        currentSavings: currentSavingsBinding,
                        targetGoal: targetGoalBinding,
                        goalTitle: goalTitleBinding
                    )
                case 3:
                    SetupGoalView(
                        goalTitle: goalTitleBinding,
                        goalKindRaw: goalKindRawBinding,
                        targetGoal: targetGoalBinding,
                        currentSavings: currentSavingsBinding,
                        targetDate: targetDateBinding,
                        customVoxelBlueprint: customVoxelBlueprintBinding
                    )
                case 4:
                    AIChatView(
                        selectedTab: $selectedTab,
                        messages: $chatMessages,
                        goalTitle: goalStore.activeGoal?.title ?? "",
                        // NOTE(skip): bare `?? 0` here left the two Elvis
                        // branches as Double/Int, which Kotlin can't unify
                        // into the Double the parameter expects — same
                        // fix as currentSavingsBinding/targetGoalBinding
                        // above.
                        targetGoal: goalStore.activeGoal?.targetAmount ?? 0.0,
                        currentSavings: goalStore.activeGoal?.currentSavings ?? 0.0,
                        targetDate: goalStore.activeGoal?.targetDate ?? Date()
                    )
                case 6:
                    LeaderboardView(goalStore: goalStore)
                case 7:
                    BudgetTrackerView()
                case 8:
                    SharedBudgetView(goalStore: goalStore, selectedTab: $selectedTab)
                default:
                    if entitlementManager.isPro {
                        SavingsCoachView(
                            goalTitle: goalStore.activeGoal?.title ?? "",
                            // NOTE(skip): same `?? 0` -> `?? 0.0` fix as above.
                            targetAmount: goalStore.activeGoal?.targetAmount ?? 0.0,
                            currentSavings: goalStore.activeGoal?.currentSavings ?? 0.0,
                            goalTargetDate: goalStore.activeGoal?.targetDate ?? Date(),
                            chatMessages: $chatMessages,
                            selectedTab: $selectedTab
                        )
                    } else {
                        CustomPaywallView(
                            goalTitle: goalStore.activeGoal?.title ?? "",
                            targetGoal: goalStore.activeGoal?.targetAmount ?? 0.0,
                            currentSavings: goalStore.activeGoal?.currentSavings ?? 0.0,
                            chatMessages: $chatMessages,
                            selectedTab: $selectedTab
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                // Reads the screen's true, ambient bottom safe-area inset
                // exactly once, from this (non-safe-area-ignoring) layer —
                // always while the Vault tab (selectedTab's initial value)
                // is showing, i.e. before BuildStudioView's RealityView has
                // ever mounted. See `fixedBottomSafeInset`.
                GeometryReader { g in
                    Color.clear
                        .onAppear {
                            // FIX: bare Int literal `0` compared against a
                            // CGFloat doesn't transpile cleanly through Skip's
                            // Kotlin codegen (Skip treats it as `Int`, not
                            // `Double`, producing "Operator '==' cannot be
                            // applied to 'Double' and 'Int'"). Swift infers the
                            // right type from context; Skip needs it spelled
                            // out.
                            if fixedBottomSafeInset == 0.0 {
                                fixedBottomSafeInset = g.safeAreaInsets.bottom
                            }
                        }
                        // TEMP DEBUG — this GeometryReader keeps re-evaluating
                        // on every layout pass regardless of the onAppear
                        // guard above. Logging the RAW live value here (not
                        // the frozen one) on every change tells us exactly
                        // what RealityView is doing to the ambient safe area
                        // in real time, independent of our own state.
                        .onChange(of: g.safeAreaInsets.bottom) { liveValue in
                            print("[TAB-DEBUG] LIVE g.safeAreaInsets.bottom -> \(liveValue) (frozen=\(fixedBottomSafeInset), selectedTab=\(selectedTab))")
                        }
                }
            )

            // MARK: - Floating Bottom Bar
            // Trimmed to the destinations people actually reach for
            // constantly (Vault, Build, Goals, Budget [+ Shared, only
            // while it's actually active]). Pro and Calendar move to
            // Profile / the Vault header — a permanent dock slot should
            // be reserved for things used every session, not an upsell
            // or a once-in-a-while lookup. Labels now only appear under
            // the selected icon, so the resting state is quiet icons —
            // not six all-caps words fighting for attention at once.
            HStack(spacing: 4) {
                LiquidTabButton(icon: "cube.fill", androidIcon: "house.fill", label: "Vault", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                .background(tourAnchorReporter(key: 0))

                LiquidTabButton(icon: "hammer.fill", androidIcon: "wrench.fill", label: "Build", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                .background(tourAnchorReporter(key: 1))

                LiquidTabButton(icon: "target", androidIcon: "mappin.circle.fill", label: "Goals", isSelected: selectedTab == 3) {
                    selectedTab = 3
                }
                .background(tourAnchorReporter(key: 3))

                LiquidTabButton(icon: "chart.pie.fill", androidIcon: "list.bullet", label: "Budget", isSelected: selectedTab == 7) {
                    selectedTab = 7
                }
                .background(tourAnchorReporter(key: 7))

                if hasActiveSharedBudget {
                    LiquidTabButton(icon: "person.2.fill", androidIcon: "person.fill", label: "Shared", isSelected: selectedTab == 8) {
                        selectedTab = 8
                    }
                    .background(tourAnchorReporter(key: 8))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: hasActiveSharedBudget)
            .background(tabBarBlurBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(themeManager.cardStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
            .padding(.horizontal, Layout.pageMargin)
            // NOTE(skip): bare `+ 2` mixed CGFloat with an Int literal,
            // which Kotlin's codegen doesn't unify implicitly the way
            // Swift does. Explicit `.0` fixes it.
            .padding(.bottom, fixedBottomSafeInset + 2.0)
            .ignoresSafeArea(.container, edges: .bottom)
            // Cancels the live swing `.ignoresSafeArea` re-introduces
            // whenever RealityView perturbs the real UIKit inset — see
            // `bottomInsetCompensation`. Positive when the live inset has
            // dropped below the frozen resting value (RealityView
            // mounted), pushing the bar back down by exactly that much;
            // zero once the live and frozen values match again (Vault).
            //
            // REVERTED from a `.position()`-based pinning attempt — that
            // approach caused an infinite update loop (a `GeometryReader`
            // `.onChange` writing to the same state it was measuring,
            // which re-triggers itself on every sub-pixel float
            // difference) and produced a white screen. Confirmed-working
            // version below; still has the residual "hop" on Build-tab
            // switches, smoothed by the `.animation` line beneath it.
            .offset(y: bottomInsetCompensation)
            .animation(.easeOut(duration: 0.2), value: uikitLiveBottomInset)

            // Only float here on tabs other than Vault — Vault already
            // has its own inline AskAIButton docked under the savings
            // chart (see ContentView), so showing this floating bubble
            // there too stacked two "Ask AI" buttons on top of each
            // other and made the whole bottom area look wrong.
            if selectedTab != 0 {
                AskAIBubble(selectedTab: $selectedTab, isPro: entitlementManager.isPro, extraBottomInset: fixedBottomSafeInset)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .offset(y: bottomInsetCompensation)
                    .animation(.easeOut(duration: 0.2), value: uikitLiveBottomInset)
            }

            if showFeatureTour {
                FeatureTourOverlay(
                    isPresented: $showFeatureTour,
                    selectedTab: $selectedTab,
                    totalTabs: totalTabs,
                    mainTabOrder: entitlementManager.isPro ? [0, 1, 3, 7, 2] : [0, 1, 3, 7, 2, 5],
                    moreTabOrder: [],
                    tourFrames: tourFrames
                )
                .transition(.opacity)
                .zIndex(10)
                .onChange(of: showFeatureTour) { isShowing in
                    if !isShowing {
                        hasSeenFeatureTour = true
                        selectedTab = 0
                    }
                }
            }
        }
        #if !SKIP
        .coordinateSpace(.named("tourOverlay"))
        #endif
        .onChange(of: uikitLiveBottomInset) { newValue in
            print("[TAB-DEBUG] uikitLiveBottomInset -> \(newValue), frozen=\(String(describing: uikitFrozenBottomInset)), compensation=\(bottomInsetCompensation) (selectedTab=\(selectedTab))")
        }
        .onPreferenceChange(TourAnchorPreferenceKey.self) { newFrames in
            // TEMP DEBUG — remove once the tab-bar shift is isolated.
            // Now logs BOTH changes and first-ever appearances (e.g. key 4,
            // the Ask AI bubble, which only exists in the tree once
            // selectedTab != 0 — its first reading was previously
            // swallowed because there was no old value to diff against).
            for (key, newRect) in newFrames {
                if let oldRect = tourFrames[key] {
                    if oldRect != newRect {
                        print("[TAB-DEBUG] key \(key) frame CHANGED: \(oldRect) -> \(newRect) (selectedTab=\(selectedTab))")
                    }
                } else {
                    print("[TAB-DEBUG] key \(key) frame FIRST SEEN: \(newRect) (selectedTab=\(selectedTab))")
                }
            }
            tourFrames = newFrames
        }
        // TEMP DEBUG — confirms whether fixedBottomSafeInset genuinely
        // stays frozen after its first capture, or is silently changing
        // on tab switch despite the `== 0.0` guard.
        .onChange(of: fixedBottomSafeInset) { newValue in
            print("[TAB-DEBUG] fixedBottomSafeInset changed -> \(newValue) (selectedTab=\(selectedTab))")
        }
        .onChange(of: selectedTab) { newValue in
            print("[TAB-DEBUG] selectedTab -> \(newValue), fixedBottomSafeInset=\(fixedBottomSafeInset), hasActiveSharedBudget=\(hasActiveSharedBudget)")
        }
        .environmentObject(streakManager)
        .environmentObject(entitlementManager)
        .environmentObject(leaderboardManager)
        .environmentObject(sharedBudgetManager)
        .environmentObject(budgetManager)
        .environmentObject(privacyManager)
        .environmentObject(goalStore)
        .environmentObject(networkMonitor)
        .overlay(alignment: .top) {
            if !networkMonitor.isOnline {
                OfflineBanner()
                    .padding(.top, 54)
                    // Added explicit Edge type for Skip compiler
                    .transition(.move(edge: Edge.top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: networkMonitor.isOnline)
        .onAppear {
            showOnboarding = needsOnboarding
            Task {
                await leaderboardManager.syncMyStreak(
                    currentStreak: streakManager.currentStreak,
                    longestStreak: streakManager.longestStreak,
                    identityID: authManager.userID ?? leaderboardManager.myUserID,
                    accessToken: authManager.accessToken
                )
            }
            // Loaded here (not just when SharedBudgetView itself is
            // opened) so the SHARED tab can show up on launch for
            // someone whose partner already joined last session.
            if let sharedID = goalStore.activeGoal?.sharedGoalID {
                Task {
                    await sharedBudgetManager.loadShare(id: sharedID, accessToken: authManager.accessToken)
                }
            }
        }
        .onChange(of: streakManager.currentStreak) { newValue in
            Task {
                await leaderboardManager.syncMyStreak(
                    currentStreak: newValue,
                    longestStreak: streakManager.longestStreak,
                    identityID: authManager.userID ?? leaderboardManager.myUserID,
                    accessToken: authManager.accessToken
                )
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            SetupGoalView(
                goalTitle: $onboardingDraftTitle,
                goalKindRaw: $onboardingDraftKindRaw,
                targetGoal: $onboardingDraftTarget,
                currentSavings: $onboardingDraftSavings,
                targetDate: $onboardingDraftDate,
                customVoxelBlueprint: $onboardingDraftVoxelBlueprintJSON,
                isOnboarding: true,
                onSave: {
                    goalStore.addGoal(
                        title: onboardingDraftTitle,
                        kindRaw: onboardingDraftKindRaw,
                        targetAmount: onboardingDraftTarget,
                        targetDate: onboardingDraftDate,
                        customVoxelBlueprintJSON: onboardingDraftVoxelBlueprintJSON
                    )
                }
            )
            .onDisappear {
                hasCompletedOnboarding = true
                if !hasSeenFeatureTour {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showFeatureTour = true
                    }
                }
            }
            .interactiveDismissDisabled(true)
        }
    }
}

// MARK: - Ask AI Bubble
//
// Previously floated at mid-screen height, draggable to anywhere on
// screen — a spot with no clear reason to be there, that also happened
// to sit on top of whatever content was underneath it. It now docks in
// one fixed, predictable spot: bottom-trailing, just above the tab bar,
// inside comfortable right-thumb reach — the same place iOS users
// already expect a persistent floating action to live. A label is shown
// alongside it (collapsing to icon-only after the first few sessions)
// so it's clear what tapping it actually does, instead of a bare glyph
// asking to be decoded.
struct AskAIBubble: View {
    @Binding var selectedTab: Int
    let isPro: Bool
    // Fixed, one-time-captured bottom safe-area inset from MainTabView —
    // see `MainTabView.fixedBottomSafeInset`. Added on top of this view's
    // own ignoresSafeArea() so the bubble's height above the tab bar stays
    // put regardless of which tab (and whatever safe-area quirks its
    // content might briefly introduce) is currently showing.
    var extraBottomInset: CGFloat = 0

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                AskAIButton(selectedTab: $selectedTab, isPro: isPro)
                    .background(
                        GeometryReader { g in
                            Color.clear
                                #if !SKIP
                                .preference(key: TourAnchorPreferenceKey.self, value: [4: g.frame(in: .named("tourOverlay"))])
                                #else
                                .preference(key: TourAnchorPreferenceKey.self, value: [4: g.frame(in: .global)])
                                #endif
                        }
                    )
                    .padding(.trailing, Layout.pageMargin)
                    // NOTE(skip): same bare-Int-plus-CGFloat issue as the
                    // tab bar's bottom padding above.
                    .padding(.bottom, 142.0 + extraBottomInset)
            }
        }
        .allowsHitTesting(true)
    }
}

/// The "Ask AI" pill button itself — sparkle icon, label (until the user's
/// tapped it enough times to know what it does), and a lock badge while
/// not Pro. Used two places: floating, via `AskAIBubble`, on every tab
/// except Vault; and docked inline under the savings chart on the Vault
/// tab (see ContentView), where a fixed floating bubble would always
/// overlap either the chart or the Deposit button.
struct AskAIButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedTab: Int
    let isPro: Bool

    @AppStorage("pv_askAIBubbleTapCount") private var tapCount: Int = 0
    private var showsLabel: Bool { tapCount < 3 }

    var body: some View {
        Button(action: {
            #if !SKIP
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            tapCount += 1
            selectedTab = 4
        }) {
            HStack(spacing: 8) {
                Image.platformSymbol("sparkles", android: "star.fill")
                    .font(themeManager.font(16, weight: .semibold))
                if showsLabel {
                    Text("Ask AI")
                        .font(themeManager.font(14, weight: .semibold))
                }
            }
            .foregroundStyle(themeManager.onAccent)
            .padding(.vertical, 13)
            .padding(.horizontal, showsLabel ? 16.0 : 13.0)
            .background(themeManager.accent)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(themeManager.onAccent.opacity(0.14), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if !isPro {
                    Image(systemName: "lock.fill")
                        .font(themeManager.font(8, weight: .bold))
                        .foregroundStyle(themeManager.accent)
                        .padding(4)
                        .background(themeManager.onAccent)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
            .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: showsLabel)
    }
}

// MARK: - Tab Button
//
// Icons alone carry each destination once they're distinct, well-chosen
// glyphs (cube, hammer, target, pie chart) — a caption under every icon,
// all the time, is redundant weight on every single one of them at
// once. The label now only appears under the selected tab, the way
// several first-party iOS apps do it: it still confirms where you are,
// without every other icon needing its own all-caps caption fighting
// for attention.
struct LiquidTabButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    // None of "cube.fill", "hammer.fill", "target", "chart.pie.fill", or
    // "person.2.fill" are in Skip's Android fallback table — see
    // PlatformSymbol.swift — so each tab supplies its own stand-in.
    let androidIcon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            #if !SKIP
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        }) {
            HStack(spacing: 6) {
                Image.platformSymbol(icon, android: androidIcon)
                    .font(themeManager.font(17, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? themeManager.onAccent : themeManager.textSecondary)

                if isSelected {
                    Text(label)
                        .font(themeManager.font(13, weight: .semibold))
                        .foregroundStyle(themeManager.onAccent)
                        .fixedSize()
                        // Added explicit UnitPoint type for Skip compiler
                        #if !SKIP
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: UnitPoint.leading)))
                        #else
                        .transition(.opacity)
                        #endif
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, isSelected ? 14.0 : 12.0)
            .frame(minWidth: 44)
            .background(isSelected ? themeManager.accent : Color.clear)
            .clipShape(Capsule())
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
        }
        .frame(maxWidth: .infinity)
    }
}

#if !SKIP
// Reports the real, UIKit-level bottom safe-area inset directly from
// `safeAreaInsetsDidChange()` — ground truth, unaffected by whatever
// RealityView does to SwiftUI's own (indirect) safe-area propagation.
// CONFIRMED via [TAB-DEBUG] logging: RealityView genuinely drives this
// value to 0 while BuildStudioView is mounted, and restores it (~15.3pt
// on this device) when it unmounts — that live swing, not a SwiftUI
// artifact, is what was moving the tab bar. `onInsetChange` fires on
// every real change; callers should capture the FIRST reported value
// once and ignore later ones, so the frozen number reflects the
// correct resting inset rather than RealityView's transient 0.
final class SafeAreaProbeUIView: UIView {
    var onInsetChange: ((CGFloat) -> Void)?
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onInsetChange?(safeAreaInsets.bottom)
    }
}

struct SafeAreaProbe: UIViewRepresentable {
    var onInsetChange: (CGFloat) -> Void
    func makeUIView(context: Context) -> SafeAreaProbeUIView {
        let v = SafeAreaProbeUIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.onInsetChange = onInsetChange
        return v
    }
    func updateUIView(_ uiView: SafeAreaProbeUIView, context: Context) {
        uiView.onInsetChange = onInsetChange
    }
}
#endif

// MARK: - Blur View Helper
//
// UIViewRepresentable bridges to a real UIKit view, which Skip can't
// transpile — the rest of the app already uses SwiftUI's own Material
// (.ultraThinMaterial etc.) everywhere else for this same frosted-glass
// look, so Android just uses that directly instead of this UIKit bridge.
#if !SKIP
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        // TEMP DEBUG — if this prints more than once per app launch, the
        // blur view is being torn down and rebuilt (e.g. on tab switch),
        // which can itself read as a one-frame position/size jump
        // independent of any padding math.
        print("[TAB-DEBUG] BlurView.makeUIView called (new instance)")
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
#endif
