import SwiftUI

/// Reports the real, on-screen frame of a tab-bar button or the Ask AI
/// bubble (in the shared "tourOverlay" coordinate space) so
/// `FeatureTourOverlay` can point its arrow at the actual element instead
/// of guessing its position from hardcoded screen-height math.
struct TourAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
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

    // Real, measured frames of the tab-bar buttons / Ask AI bubble, keyed
    // by the same tabIndex values FeatureTourOverlay's steps use (and
    // `tourMoreButtonKey` for the MORE button). Populated live via
    // TourAnchorPreferenceKey so the tour's arrow always lands on the
    // actual button, even if paddings/sizes change later.
    @State private var tourFrames: [Int: CGRect] = [:]

    /// Attaches an invisible frame reporter to a view so its on-screen
    /// rect (in the "tourOverlay" coordinate space) gets merged into
    /// `tourFrames` under `key`.
    private func tourAnchorReporter(key: Int) -> some View {
        GeometryReader { g in
            Color.clear
                .preference(key: TourAnchorPreferenceKey.self, value: [key: g.frame(in: .named("tourOverlay"))])
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
            get: { goalStore.activeGoal?.currentSavings ?? 0 },
            set: { newValue in goalStore.mutateActive { $0.currentSavings = newValue } }
        )
    }

    private var targetGoalBinding: Binding<Double> {
        Binding(
            get: { goalStore.activeGoal?.targetAmount ?? 1200 },
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
                        targetGoal: goalStore.activeGoal?.targetAmount ?? 0,
                        currentSavings: goalStore.activeGoal?.currentSavings ?? 0,
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
                            targetAmount: goalStore.activeGoal?.targetAmount ?? 0,
                            currentSavings: goalStore.activeGoal?.currentSavings ?? 0,
                            goalTargetDate: goalStore.activeGoal?.targetDate ?? Date(),
                            chatMessages: $chatMessages,
                            selectedTab: $selectedTab
                        )
                    } else {
                        CustomPaywallView(
                            goalTitle: goalStore.activeGoal?.title ?? "",
                            targetGoal: goalStore.activeGoal?.targetAmount ?? 0,
                            currentSavings: goalStore.activeGoal?.currentSavings ?? 0,
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
                    Color.clear.onAppear {
                        if fixedBottomSafeInset == 0 {
                            fixedBottomSafeInset = g.safeAreaInsets.bottom
                        }
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
                LiquidTabButton(icon: "cube.fill", label: "Vault", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                .background(tourAnchorReporter(key: 0))

                LiquidTabButton(icon: "hammer.fill", label: "Build", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                .background(tourAnchorReporter(key: 1))

                LiquidTabButton(icon: "target", label: "Goals", isSelected: selectedTab == 3) {
                    selectedTab = 3
                }
                .background(tourAnchorReporter(key: 3))

                LiquidTabButton(icon: "chart.pie.fill", label: "Budget", isSelected: selectedTab == 7) {
                    selectedTab = 7
                }
                .background(tourAnchorReporter(key: 7))

                if hasActiveSharedBudget {
                    LiquidTabButton(icon: "person.2.fill", label: "Shared", isSelected: selectedTab == 8) {
                        selectedTab = 8
                    }
                    .background(tourAnchorReporter(key: 8))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: hasActiveSharedBudget)
            .background(
                BlurView(style: themeManager.isLight ? .systemUltraThinMaterialLight : .systemUltraThinMaterialDark)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(themeManager.cardStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
            .padding(.horizontal, Layout.pageMargin)
            .padding(.bottom, fixedBottomSafeInset + 2)
            .ignoresSafeArea(.container, edges: .bottom)

            AskAIBubble(selectedTab: $selectedTab, isPro: entitlementManager.isPro, extraBottomInset: fixedBottomSafeInset)
                .ignoresSafeArea(.container, edges: .bottom)

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
                .onChange(of: showFeatureTour) { _, isShowing in
                    if !isShowing {
                        hasSeenFeatureTour = true
                        selectedTab = 0
                    }
                }
            }
        }
        .coordinateSpace(name: "tourOverlay")
        .onPreferenceChange(TourAnchorPreferenceKey.self) { tourFrames = $0 }
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
                    .transition(.move(edge: .top).combined(with: .opacity))
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
        .onChange(of: streakManager.currentStreak) { _, newValue in
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
                                .preference(key: TourAnchorPreferenceKey.self, value: [4: g.frame(in: .named("tourOverlay"))])
                        }
                    )
                    .padding(.trailing, Layout.pageMargin)
                    .padding(.bottom, 142 + extraBottomInset)
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            tapCount += 1
            selectedTab = 4
        }) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(themeManager.font(16, weight: .semibold))
                if showsLabel {
                    Text("Ask AI")
                        .font(themeManager.font(14, weight: .semibold))
                }
            }
            .foregroundStyle(themeManager.onAccent)
            .padding(.vertical, 13)
            .padding(.horizontal, showsLabel ? 16 : 13)
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
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(themeManager.font(17, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? themeManager.onAccent : themeManager.textSecondary)

                if isSelected {
                    Text(label)
                        .font(themeManager.font(13, weight: .semibold))
                        .foregroundStyle(themeManager.onAccent)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, isSelected ? 14 : 12)
            .frame(minWidth: 44)
            .background(isSelected ? themeManager.accent : Color.clear)
            .clipShape(Capsule())
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Blur View Helper
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
