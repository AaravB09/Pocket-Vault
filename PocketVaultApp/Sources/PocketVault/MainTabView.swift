import SwiftUI

/// Reports the real, on-screen frame of a tab-bar button or the Ask AI
/// bubble (in the shared "tourOverlay" coordinate space) so
/// `FeatureTourOverlay` can point its arrow at the actual element instead
/// of guessing its position from hardcoded screen-height math.
public struct TourAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        for (key, rect) in nextValue() {
            value[key] = rect
        }
    }
}

public struct MainTabView: View {
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

    // Used on Android only now (see the `#if SKIP` background capture
    // further down) — RealityView doesn't exist there, so there's
    // nothing perturbing this value on that platform.
    @State private var fixedBottomSafeInset: CGFloat = 0

    // FIX (Android: Deposit button — and anything else at the bottom of
    // a tab — rendering underneath the floating tab bar): on iOS,
    // `.safeAreaInset(edge: .bottom)` (see `body`) both positions the
    // bar AND shrinks `mainTabContent`'s available height to make room
    // for it, so every tab's own `GeometryReader`-measured height
    // already excludes the bar. Android's tab bar was never switched to
    // `.safeAreaInset` (see the note on `tabBarView` above and on
    // `body` below) — it's a plain ZStack sibling, floated on top of
    // `mainTabContent` with hand-computed bottom padding. That keeps
    // the bar itself positioned correctly, but `mainTabContent` was
    // never told to reserve room for it, so any tab whose content
    // stretches to fill its full measured height (e.g. ContentView's
    // Deposit button, pinned to the bottom of a screen-height
    // `ScrollView`) ends up rendering directly behind the bar instead
    // of above it — exactly what showed up as "Deposit funds" text
    // peeking out from underneath the Vault/Build/Goals dock.
    //
    // Fix: measure the bar's real on-screen height once (same one-time
    // "settle after first layout" treatment `fixedBottomSafeInset`
    // above already gets) and pad `mainTabContent`'s bottom by that
    // much on Android, so its content has the same effective ceiling
    // iOS gets for free from `.safeAreaInset`. Seeded to a sane
    // estimate of the bar's actual intrinsic height (17pt icon + 10pt
    // vertical padding on the button, + 10pt vertical padding on the
    // bar itself, doubled) rather than 0, so there's no first-frame
    // flash of content sitting behind the bar before the real
    // measurement lands.
    @State private var androidTabBarHeight: CGFloat = 64

    // ROOT CAUSE (found after four failed attempts, all of which tried
    // to fix or freeze the *value* the bar's position was computed
    // from): the bug was never in what `safeAreaInsets.bottom` reports.
    // It's that the tab bar was being placed with `.position()`, driven
    // by hand-rolled math against `UIScreen.main.bounds` — a value that
    // lives OUTSIDE SwiftUI's layout system entirely. `.position()`
    // places a view relative to its *parent's own laid-out frame*, not
    // the physical screen, so that math is only ever correct by
    // coincidence, for whatever frame the parent ZStack happens to have
    // at that moment. BuildStudioView's RealityView measurably changes
    // that frame while mounted (RealityKit's rendering surface resizes
    // the enclosing layout pass, not just what it reports), so the
    // coincidence broke specifically on that tab.
    //
    // The actual fix is to stop computing a position by hand at all.
    // `.safeAreaInset(edge: .bottom)` (below, on the switched content)
    // hands bottom placement back to SwiftUI's own layout engine — the
    // same mechanism system tab bars use — so the bar's position is
    // always derived from whatever the real current layout is, on
    // whichever tab, with no absolute coordinates or device sniffing
    // involved.


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
                .preference(key: TourAnchorPreferenceKey.self, value: [key: g.frame(in: CoordinateSpace.global)])
                #endif
        }
    }

    @State private var onboardingDraftTitle: String = ""
    @State private var onboardingDraftKindRaw: String = GoalKind.flight.rawValue
    @State private var onboardingDraftTarget: Double = 1200
    @State private var onboardingDraftSavings: Double = 0
    @State private var onboardingDraftDate: Date = Calendar.current.date(byAdding: Calendar.Component.month, value: 3, to: Date()) ?? Date()
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
            get: { goalStore.activeGoal?.targetDate ?? Calendar.current.date(byAdding: Calendar.Component.month, value: 3, to: Date())! },
            set: { newValue in goalStore.mutateActive { $0.targetDate = newValue } }
        )
    }

    private var customVoxelBlueprintBinding: Binding<String?> {
        Binding(
            get: { goalStore.activeGoal?.customVoxelBlueprintJSON },
            set: { newValue in goalStore.mutateActive { $0.customVoxelBlueprintJSON = newValue } }
        )
    }

    @ViewBuilder
    private var mainTabContent: some View {
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
            .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
            // FIX (Android "butter smooth" ask): each tab is still a
            // completely separate view under this `switch` — that's not
            // changing in this pass, since rewriting the whole tab system
            // to preserve view identity across tabs is a much bigger,
            // riskier change (this app already has a long list of
            // Skip-transpiler-specific workarounds elsewhere, so a
            // structural rewrite like that needs its own careful pass,
            // not a drive-by edit). What's cheap and safe here is
            // softening the hard cut between tabs into a real crossfade,
            // so the swap itself doesn't read as an abrupt jump-cut even
            // though the underlying view is still being rebuilt.
            #if !SKIP
            .id(selectedTab)
            .transition(AnyTransition.opacity)
            .animation(Animation.easeInOut(duration: 0.18), value: selectedTab)
            #endif
    }

    // MARK: - Floating Bottom Bar
    // Trimmed to the destinations people actually reach for constantly
    // (Vault, Build, Goals, Budget [+ Shared, only while it's actually
    // active]). Pro and Calendar move to Profile / the Vault header — a
    // permanent dock slot should be reserved for things used every
    // session, not an upsell or a once-in-a-while lookup. Labels now
    // only appear under the selected icon, so the resting state is
    // quiet icons — not six all-caps words fighting for attention at
    // once.
    //
    // Positioned via `.safeAreaInset(edge: .bottom)` on iOS (applied in
    // `body`) instead of any manual coordinate math — see the note by
    // `fixedBottomSafeInset` above for why. Android keeps its original,
    // never-buggy placement.
    private var tabBarView: some View {
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
                    .transition(AnyTransition.scale.combined(with: AnyTransition.opacity))
                }
            }
            .padding(Edge.Set.horizontal, 12)
            .padding(Edge.Set.vertical, 10)
            .animation(Animation.spring(response: 0.4, dampingFraction: 0.75), value: hasActiveSharedBudget)
            .background(tabBarBlurBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(themeManager.cardStroke, lineWidth: 1)
            )
            // PERF (Android): this dock is mounted on every tab and never
            // unmounts, so its `.shadow` gets re-evaluated on every
            // recomposition of the switched content behind it (tab
            // switches, list scrolling, sheet presentation, etc.).
            // SwiftUI's `.shadow` is a real-time blur pass under Skip, not
            // a cheap hardware elevation like a native Android shadow, so
            // a radius-16 shadow sitting there permanently was a steady,
            // avoidable cost on every screen instead of an occasional one.
            // A smaller radius keeps the same "floating dock" look at a
            // fraction of the blur cost; iOS keeps the original.
            #if !SKIP
            .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
            #else
            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
            #endif
            .padding(Edge.Set.horizontal, Layout.pageMargin)
    }

    public var body: some View {
        ZStack(alignment: Alignment.bottom) {
            #if !SKIP
            // The tab bar is handed to `.safeAreaInset` rather than kept
            // as a `.position()`-ed sibling — SwiftUI computes its
            // placement from the CURRENT real layout on every pass, on
            // every tab, so there's nothing left for RealityView's
            // mount/unmount to desync. The Ask AI bubble rides along as
            // an overlay on the content BEHIND that inset, aligned to
            // its bottom-trailing corner, so it naturally sits right
            // above wherever the bar actually is instead of at another
            // independently-computed absolute point.
            mainTabContent
                .overlay(alignment: Alignment.bottomTrailing) {
                    // Only float here on tabs other than Vault — Vault
                    // already has its own inline AskAIButton docked
                    // under the savings chart (see ContentView), so
                    // showing this floating bubble there too stacked
                    // two "Ask AI" buttons on top of each other and
                    // made the whole bottom area look wrong.
                    if selectedTab != 0 {
                        AskAIBubble(selectedTab: $selectedTab, isPro: entitlementManager.isPro)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    // FIX (white strip under the floating tab bar): the pill
                    // returned by `tabBarView` only sizes itself to its own
                    // content (icons + padding) — it never claimed the
                    // narrow strip of true safe area *below* it, down to the
                    // home-indicator edge. `.safeAreaInset` reserves that
                    // whole region for whatever's handed to it, but doesn't
                    // paint it: with nothing else drawn there, that gap fell
                    // through to the plain white UIWindow background behind
                    // everything, instead of the app's dark theme. Every
                    // other screen never showed this because they each call
                    // `.themedSurface()`, which paints `theme.background`
                    // — but that's on `mainTabContent`, and this inset area
                    // sits below/behind that view, not inside it.
                    // Fixed by giving this inset its own full-width,
                    // safe-area-ignoring themed background sitting behind
                    // the pill, so the strip beneath it now reads as the
                    // same dark surface as the rest of the app instead of a
                    // leftover system-default white rectangle.
                    tabBarView
                        .frame(maxWidth: CGFloat.infinity)
                        .background(themeManager.background.ignoresSafeArea(edges: Edge.Set.bottom))
                }
            #else
            // RealityView (and therefore this whole class of bug) is
            // iOS-only — see `BuildStudioView`, gated `#if !SKIP`.
            // Android never saw this jump, so its original, simpler
            // positioning is untouched.
            //
            // FIX (Deposit button underneath the tab bar): bottom-pad by
            // the bar's real measured height (see `androidTabBarHeight`
            // above) so content has the same clearance iOS gets for
            // free from `.safeAreaInset`.
            mainTabContent
                .padding(Edge.Set.bottom, androidTabBarHeight)
                .background(
                    GeometryReader { g in
                        Color.clear
                            .onAppear {
                                if fixedBottomSafeInset == 0.0 {
                                    fixedBottomSafeInset = g.safeAreaInsets.bottom
                                }
                            }
                    }
                )

            tabBarView
                .background(
                    GeometryReader { g in
                        Color.clear
                            .onAppear { androidTabBarHeight = g.size.height }
                            .onChange(of: hasActiveSharedBudget) { _, _ in
                                // The bar gains/loses the "Shared" button
                                // depending on this, which can't change
                                // its height (all buttons share one
                                // fixed vertical padding) but re-measure
                                // anyway rather than assume that.
                                androidTabBarHeight = g.size.height
                            }
                    }
                )
                .padding(Edge.Set.bottom, fixedBottomSafeInset + 2.0)
                .ignoresSafeArea(SwiftUI.Scene.container, edges: Edge.Set.bottom)

            if selectedTab != 0 {
                AskAIBubble(selectedTab: $selectedTab, isPro: entitlementManager.isPro, extraBottomInset: fixedBottomSafeInset)
            }
            #endif

            if showFeatureTour {
                FeatureTourOverlay(
                    isPresented: $showFeatureTour,
                    selectedTab: $selectedTab,
                    totalTabs: totalTabs,
                    mainTabOrder: entitlementManager.isPro ? [0, 1, 3, 7, 2] : [0, 1, 3, 7, 2, 5],
                    moreTabOrder: [],
                    tourFrames: tourFrames
                )
                .transition(AnyTransition.opacity)
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
        .onPreferenceChange(TourAnchorPreferenceKey.self) { newFrames in
            tourFrames = newFrames
        }
        .environmentObject(streakManager)
        .environmentObject(entitlementManager)
        .environmentObject(leaderboardManager)
        .environmentObject(sharedBudgetManager)
        .environmentObject(budgetManager)
        .environmentObject(privacyManager)
        .environmentObject(goalStore)
        .environmentObject(networkMonitor)
        .overlay(alignment: Alignment.top) {
            if !networkMonitor.isOnline {
                OfflineBanner()
                    .padding(Edge.Set.top, 54)
                    // Added explicit Edge type for Skip compiler
                    .transition(AnyTransition.move(edge: Edge.top).combined(with: AnyTransition.opacity))
            }
        }
        .animation(Animation.spring(response: 0.35, dampingFraction: 0.8), value: networkMonitor.isOnline)
        .onAppear {
            // `fixedBottomSafeInset` no longer needs seeding here on iOS
            // — `.safeAreaInset` (see `body`) reads the real layout
            // directly, nothing left to freeze.
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
public struct AskAIBubble: View {
    @Binding var selectedTab: Int
    let isPro: Bool
    // Only consulted on Android now — see `body`'s `#else` branch below
    // and the note by `MainTabView.fixedBottomSafeInset`.
    var extraBottomInset: CGFloat = 0

    public var body: some View {
        #if !SKIP
        // Placed via `.overlay(alignment: Alignment.bottomTrailing)` by the
        // caller (`MainTabView.body`), so it just needs its own margin
        // from that corner — no absolute screen math or frozen-size
        // capture needed anymore.
        AskAIButton(selectedTab: $selectedTab, isPro: isPro)
            .background(
                GeometryReader { g in
                    Color.clear
                        .preference(key: TourAnchorPreferenceKey.self, value: [4: g.frame(in: .named("tourOverlay"))])
                }
            )
            .padding(Edge.Set.trailing, Layout.pageMargin)
            .padding(Edge.Set.bottom, 12)
            .allowsHitTesting(true)
        #else
        // RealityView (and therefore this whole class of bug) is
        // iOS-only. Android never saw this jump, so its original,
        // simpler positioning is untouched.
        VStack {
            Spacer()
            HStack {
                Spacer()
                AskAIButton(selectedTab: $selectedTab, isPro: isPro)
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .preference(key: TourAnchorPreferenceKey.self, value: [4: g.frame(in: CoordinateSpace.global)])
                        }
                    )
                    .padding(Edge.Set.trailing, Layout.pageMargin)
                    .padding(Edge.Set.bottom, 142.0 + extraBottomInset)
            }
        }
        .ignoresSafeArea(SwiftUI.Scene.container, edges: Edge.Set.bottom)
        .allowsHitTesting(true)
        #endif
    }
}

/// The "Ask AI" pill button itself — sparkle icon, label (until the user's
/// tapped it enough times to know what it does), and a lock badge while
/// not Pro. Used two places: floating, via `AskAIBubble`, on every tab
/// except Vault; and docked inline under the savings chart on the Vault
/// tab (see ContentView), where a fixed floating bubble would always
/// overlap either the chart or the Deposit button.
public struct AskAIButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedTab: Int
    let isPro: Bool

    @AppStorage("pv_askAIBubbleTapCount") private var tapCount: Int = 0
    private var showsLabel: Bool { tapCount < 3 }

    public var body: some View {
        Button(action: {
            #if !SKIP
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            tapCount += 1
            selectedTab = 4
        }) {
            HStack(spacing: 8) {
                Image.platformSymbol("sparkles", android: "star.fill")
                    .font(themeManager.font(16, weight: Font.Weight.semibold))
                if showsLabel {
                    Text("Ask AI")
                        .font(themeManager.font(14, weight: Font.Weight.semibold))
                }
            }
            .foregroundStyle(themeManager.onAccent)
            .padding(Edge.Set.vertical, 13)
            .padding(Edge.Set.horizontal, showsLabel ? 16.0 : 13.0)
            .background(themeManager.accent)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(themeManager.onAccent.opacity(0.14), lineWidth: 1)
            )
            .overlay(alignment: Alignment.topTrailing) {
                if !isPro {
                    Image(systemName: "lock.fill")
                        .font(themeManager.font(8, weight: Font.Weight.bold))
                        .foregroundStyle(themeManager.accent)
                        .padding(4)
                        .background(themeManager.onAccent)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
            // PERF (Android): same reasoning as the tab bar dock's shadow
            // above — this bubble floats over almost every tab and never
            // unmounts, so a radius-10 blur shadow here is paid on every
            // recomposition, not just once. Smaller radius on Android,
            // iOS unchanged.
            #if !SKIP
            .shadow(color: Color.black.opacity(0.22), radius: 10, y: 5)
            #else
            .shadow(color: Color.black.opacity(0.22), radius: 4, y: 2)
            #endif
        }
        .animation(Animation.spring(response: 0.3, dampingFraction: 0.75), value: showsLabel)
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
public struct LiquidTabButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    // None of "cube.fill", "hammer.fill", "target", "chart.pie.fill", or
    // "person.2.fill" are in Skip's Android fallback table — see
    // PlatformSymbol.swift — so each tab supplies its own stand-in.
    let androidIcon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    public var body: some View {
        Button(action: {
            #if !SKIP
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        }) {
            HStack(spacing: 6) {
                Image.platformSymbol(icon, android: androidIcon)
                    .font(themeManager.font(17, weight: isSelected ? Font.Weight.semibold : Font.Weight.regular))
                    .foregroundStyle(isSelected ? themeManager.onAccent : themeManager.textSecondary)

                if isSelected {
                    Text(label)
                        .font(themeManager.font(13, weight: Font.Weight.semibold))
                        .foregroundStyle(themeManager.onAccent)
                        .fixedSize()
                        // Added explicit UnitPoint type for Skip compiler
                        #if !SKIP
                        .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.9, anchor: UnitPoint.leading)))
                        #else
                        .transition(AnyTransition.opacity)
                        #endif
                }
            }
            .padding(Edge.Set.vertical, 10)
            .padding(Edge.Set.horizontal, isSelected ? 14.0 : 12.0)
            .frame(minWidth: 44)
            .background(isSelected ? themeManager.accent : Color.clear)
            .clipShape(Capsule())
            .animation(Animation.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
        }
        .frame(maxWidth: CGFloat.infinity)
    }
}

// MARK: - Blur View Helper
//
// UIViewRepresentable bridges to a real UIKit view, which Skip can't
// transpile — the rest of the app already uses SwiftUI's own Material
// (.ultraThinMaterial etc.) everywhere else for this same frosted-glass
// look, so Android just uses that directly instead of this UIKit bridge.
#if !SKIP
public struct BlurView: UIViewRepresentable {
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
