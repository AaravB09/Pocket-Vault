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

    private let totalTabs = 8

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

            // MARK: - Liquid Glass Floating Bottom Bar
            // Every primary destination gets its own permanent slot now —
            // no MORE popover in the way. Friends/invite moved into
            // ProfileView instead of living behind a tab.
            HStack(spacing: 0) {
                LiquidTabButton(icon: "cube.fill", label: "VAULT", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                .background(tourAnchorReporter(key: 0))

                LiquidTabButton(icon: "hammer.fill", label: "BUILD", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                .background(tourAnchorReporter(key: 1))

                LiquidTabButton(icon: "target", label: "GOALS", isSelected: selectedTab == 3) {
                    selectedTab = 3
                }
                .background(tourAnchorReporter(key: 3))

                LiquidTabButton(icon: "chart.pie.fill", label: "BUDGET", isSelected: selectedTab == 7) {
                    selectedTab = 7
                }
                .background(tourAnchorReporter(key: 7))

                LiquidTabButton(icon: "calendar", label: "CALENDAR", isSelected: selectedTab == 2) {
                    selectedTab = 2
                }
                .background(tourAnchorReporter(key: 2))

                LiquidTabButton(icon: "crown.fill", label: "PRO", isSelected: selectedTab == 5) {
                    selectedTab = 5
                }
                .background(tourAnchorReporter(key: 5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    BlurView(style: themeManager.isLight ? .systemUltraThinMaterialLight : .systemUltraThinMaterialDark)

                    LinearGradient(
                        colors: [
                            themeManager.textPrimary.opacity(0.18),
                            themeManager.textPrimary.opacity(0.02),
                            themeManager.accent.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                themeManager.textPrimary.opacity(0.35),
                                themeManager.accent.opacity(0.4),
                                themeManager.textPrimary.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.5), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 14)
            .padding(.bottom, 2)

            AskAIBubble(selectedTab: $selectedTab, isPro: entitlementManager.isPro)

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

// MARK: - Floating Ask AI Bubble
struct AskAIBubble: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedTab: Int
    let isPro: Bool

    /// Position sits at its usual bottom-trailing spot by default; a
    /// drag adds an offset on top of that for the rest of this session.
    /// Not persisted to disk on purpose — always starting back at the
    /// default corner on relaunch means a bubble dragged into an odd
    /// spot can never get stuck somewhere unreachable.
    @State private var dragOffset: CGSize = .zero
    @GestureState private var liveDrag: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let baseX = geo.size.width - 40
            let baseY = geo.size.height / 2 - 60

            bubble
                // Reports the bubble's own true rendered frame (52x52,
                // wherever it currently sits) — not AskAIBubble's
                // full-screen GeometryReader frame — so the tour's arrow
                // lands on the actual circle. Attached here, before
                // .position() below, so it moves along with the bubble.
                .background(
                    GeometryReader { g in
                        Color.clear
                            .preference(key: TourAnchorPreferenceKey.self, value: [4: g.frame(in: .named("tourOverlay"))])
                    }
                )
                .position(
                    x: baseX + dragOffset.width + liveDrag.width,
                    y: baseY + dragOffset.height + liveDrag.height
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .updating($liveDrag) { value, state, _ in
                            state = value.translation
                            if !isDragging {
                                isDragging = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                        .onEnded { value in
                            let finalX = baseX + dragOffset.width + value.translation.width
                            let finalY = baseY + dragOffset.height + value.translation.height
                            // Keep it fully on-screen and clear of the
                            // status bar / floating tab bar.
                            var clampedX = min(max(finalX, 36), geo.size.width - 36)
                            let clampedY = min(max(finalY, 90), geo.size.height - 150)

                            // A bubble resting mid-screen blocks whatever's
                            // behind it, so anywhere near the middle snaps
                            // out to whichever edge it's closer to instead
                            // — same "always docks to a side" behavior as
                            // iOS's AssistiveTouch bubble.
                            let centerX = geo.size.width / 2
                            let centerDeadZone = geo.size.width * 0.34
                            if abs(clampedX - centerX) < centerDeadZone {
                                clampedX = finalX < centerX ? 36 : geo.size.width - 36
                            }

                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                dragOffset = CGSize(width: clampedX - baseX, height: clampedY - baseY)
                            }
                            isDragging = false
                        }
                )
        }
        .allowsHitTesting(true)
    }

    private var bubble: some View {
        Button(action: {
            guard !isDragging else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedTab = 4
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 52, height: 52)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [themeManager.accent.opacity(0.35), .clear],
                            center: .center, startRadius: 2, endRadius: 28
                        )
                    )
                    .frame(width: 52, height: 52)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [themeManager.accent.opacity(0.9), themeManager.textPrimary.opacity(0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: "sparkles")
                    .font(themeManager.font(17, weight: .semibold))
                    .foregroundStyle(selectedTab == 4 ? themeManager.accent : themeManager.textPrimary.opacity(0.85))

                if !isPro {
                    Image(systemName: "lock.fill")
                        .font(themeManager.font(8, weight: .bold))
                        .foregroundStyle(themeManager.onAccent)
                        .padding(4)
                        .background(themeManager.accent)
                        .clipShape(Circle())
                        .offset(x: 18, y: -18)
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            .scaleEffect(isDragging ? 1.1 : 1.0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
    }
}

// MARK: - Liquid Glass Tab Button
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
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(themeManager.font(15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? themeManager.accent : themeManager.textSecondary)

                Text(label)
                    .font(themeManager.font(8, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(isSelected ? themeManager.textPrimary : themeManager.textSecondary)
            }
            .frame(minWidth: 58)
        }
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
