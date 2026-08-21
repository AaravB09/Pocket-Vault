import SwiftUI
#if !SKIP
import RealityKit
#endif

struct ContentView: View {
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    @EnvironmentObject var entitlementManager: EntitlementManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var privacy: PrivacyManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var sharedBudgetManager: SharedBudgetManager

    @Binding var goalTitle: String
    @Binding var goalKindRaw: String
    @Binding var currentSavings: Double
    @Binding var targetGoal: Double
    @Binding var selectedTab: Int
    @Binding var chatMessages: [ChatMessage]
    @ObservedObject var goalStore: GoalStore

    // Keyed by the current account/guest identity — see ProfileView,
    // which owns the canonical write path for this same key.
    @State private var profileImageData: Data?
    private var profileImageKey: String { "pv_profileImage_\(leaderboardManager.myUserID)" }

    @State private var showSetupGoalSheet: Bool = false
    @State private var showPaywall: Bool = false
    @State private var showDepositSheet: Bool = false
    @State private var showBurst: Bool = false
    @State private var showProfile: Bool = false
    @State private var targetDate: Date = Date()

    @State private var showAddGoalSheet: Bool = false
    @State private var newGoalTitle: String = ""
    @State private var newGoalKindRaw: String = GoalKind.flight.rawValue
    @State private var newGoalTarget: Double = 1200.0
    @State private var newGoalSavings: Double = 0.0
    @State private var newGoalDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var newGoalVoxelBlueprintJSON: String? = nil

    // Because the background ignores the safe area (see .themedSurface
    // below), the header VStack needs its own top padding to clear the
    // status bar/notch/Dynamic Island. Read the real inset here instead
    // of hardcoding a number, so this adapts per device automatically.
    @State private var topSafeAreaInset: CGFloat = 0

    private var goalKind: GoalKind { GoalKind(rawValue: goalKindRaw) ?? .flight }

    // Same identity resolution as SharedBudgetView/LeaderboardView — real
    // account id when signed in, falls back to the local guest id.
    private var myID: String { authManager.userID ?? leaderboardManager.myUserID }

    // FIX: nested `min(max(...))` over Doubles is the same generic-
    // overload pattern that's broken every other file in this project
    // (AmountScrubPicker, BudgetTrackerView, BuildStudioView,
    // CalendarView) — Skip's Kotlin codegen can't resolve the overload.
    // Clamp with plain comparisons instead.
    var progress: Double {
        let safeTarget = targetGoal > 1.0 ? targetGoal : 1.0
        let raw = currentSavings / safeTarget
        if raw < 0.0 { return 0.0 }
        if raw > 1.0 { return 1.0 }
        return raw
    }

    private var displayProgress: Double {
        currentSavings > 0.0 ? progress : 0.05
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = leaderboardManager.myDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "User" : name

        switch hour {
        case 0..<12:
            return "Good Morning, \(displayName)"
        case 12..<17:
            return "Good Afternoon, \(displayName)"
        default:
            return "Good Evening, \(displayName)"
        }
    }

    var body: some View {
        ZStack {
            // Soft Studio Ambient Lighting Accent
            // FIX: every other tab's root view fills the space the
            // outer `.safeAreaInset` tab bar measures against (see
            // MainTabView's `mainTabContent`, which forces
            // `.frame(maxWidth: .infinity, maxHeight: .infinity)` on
            // the switch as a whole — but that only guarantees the
            // *switch container* fills the screen, not that each
            // individual case's own root view does). This ZStack was
            // the one case sizing itself to its content instead of
            // being told to fill, which changed what `safeAreaInset`
            // had to lay the tab bar out against specifically on this
            // tab, and pushed the bar down. Explicit fill here matches
            // every sibling tab view and keeps the bar's position
            // identical across tabs.
            RadialGradient(
                colors: [theme.textPrimary.opacity(0.1), .clear],
                center: .center, startRadius: 10, endRadius: 280
            )
            .offset(y: -40)
            .allowsHitTesting(false)

            // Editorial UI Overlay
            VStack(spacing: 0) {
                // MARK: - Top Header Block
                VStack(spacing: 16) {
                    // 1. Row 1: Profile & Greeting / Pro Status Only
                    HStack {
                        Button(action: { showProfile = true }) {
                            ZStack {
                                if let profileImageData, let uiImage = UIImage(data: profileImageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        // NOTE(skip): .ultraThinMaterial has no
                                        // Android equivalent — was cascading
                                        // into the .clipShape/'frame' errors.
                                        .fill(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "person.fill")
                                        .font(theme.font(15, weight: .light))
                                        .foregroundStyle(theme.accent)
                                }
                                Circle()
                                    .stroke(theme.cardStroke, lineWidth: 1)
                                    .frame(width: 40, height: 40)
                            }
                        }

                        Spacer()

                        if entitlementManager.isPro {
                            Text(greetingText)
                                .font(theme.font(18, weight: .semibold))
                                .foregroundStyle(theme.textPrimary.opacity(0.95))
                        } else {
                            Button(action: { showPaywall = true }) {
                                Badge(text: "Pro", icon: "crown.fill")
                            }
                        }

                        Spacer()

                        HStack(spacing: 10) {
                            HeaderIconButton(systemName: "calendar") { selectedTab = 2 }
                            PrivacyQuickToggleButton()
                        }
                    }
                    .padding(.horizontal, Layout.pageMargin)

                    // 2. Row 2: Active Journey Selector Button
                    HStack {
                        Button(action: { showSetupGoalSheet = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: goalKind.displayIcon)
                                    .font(theme.font(13, weight: .medium))
                                    .foregroundStyle(theme.accent)

                                Text(goalTitle.isEmpty ? "Choose a journey" : goalTitle)
                                    .font(theme.font(14, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary.opacity(0.9))

                                Image(systemName: "chevron.down")
                                    .font(theme.font(10, weight: .semibold))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(theme.cardStroke, lineWidth: 1))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, Layout.pageMargin)
                }
                // Small extra buffer on top of the real safe-area inset —
                // tight to the notch/Dynamic Island without touching it.
                //
                // Android-only: the +25 buffer (on top of the real,
                // measured safe-area inset) read as noticeably more empty
                // space above the greeting than the equivalent gap on iOS.
                // Shrinking just this extra buffer for Android — not the
                // measured inset itself — tightens the header without
                // touching iOS's spacing at all.
                #if !SKIP
                .padding(.top, topSafeAreaInset + 25)
                #else
                .padding(.top, topSafeAreaInset + 6)
                #endif

                // Goal Picker
                GoalPickerBar(goalStore: goalStore) {
                    newGoalTitle = ""
                    newGoalKindRaw = GoalKind.flight.rawValue
                    newGoalTarget = 1200.0
                    newGoalSavings = 0.0
                    newGoalDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
                    newGoalVoxelBlueprintJSON = nil
                    showAddGoalSheet = true
                }
                .padding(.top, 16)

                // Editorial Hero Progress Text
                ZStack {
                    VStack(spacing: 4) {
                        Text("\(Int(displayProgress * 100))%")
                            .font(theme.font(92, weight: .ultraLight))
                            .tracking(-3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [theme.textPrimary, theme.textPrimary.opacity(0.75)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )

                        HStack(spacing: 8) {
                            Text("$\(Int(currentSavings))")
                                .font(theme.font(16, weight: .medium))
                                .foregroundStyle(theme.accent)

                            Text("of $\(Int(targetGoal))")
                                .font(theme.font(13, weight: .medium))
                                .foregroundStyle(.secondary) // was .tertiary
                        }

                        if currentSavings == 0.0 {
                            Text("Head start for creating your goal — deposit to keep it moving")
                                .font(theme.font(9, weight: .light))
                                .foregroundStyle(.secondary) // was .tertiary
                                .padding(.top, 2)
                        }

                        // Minimalist Hairline Progress Line
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(theme.hairline)

                                Rectangle()
                                    .fill(theme.accent)
                                    .frame(width: geo.size.width * CGFloat(displayProgress))
                            }
                        }
                        .frame(height: 2)
                        .padding(.horizontal, 80)
                        .padding(.top, 12)
                    }
                    // FIX: `privacy.shouldMask ? 14 : 0` — Swift infers
                    // Double for both ternary branches from the `radius:
                    // Double` parameter, but Skip's Kotlin codegen doesn't
                    // do that implicit Int-to-Double literal promotion
                    // inside a ternary (same issue the `quickAmounts`
                    // array below already works around by spelling out
                    // the decimal points) — reports "actual type is
                    // 'Int', but 'Double' was expected". Spell out the
                    // decimals here too.
                    .blur(radius: privacy.shouldMask ? 14.0 : 0.0)
                    .overlay {
                        if privacy.shouldMask {
                            PrivacyRevealOverlay()
                        }
                    }

                    ParticleBurstView(isActive: $showBurst)
                        .offset(y: -20)
                }
                .padding(.top, 20)

                SavingsTrendChart(
                    history: goalStore.activeGoal?.history ?? [],
                    targetAmount: targetGoal
                )
                .padding(.top, 24)

                // Ask AI — docked here, right under the chart, instead of
                // floating on top of it. This is the one tab where a
                // fixed-position floating bubble would always end up
                // overlapping either the chart or the Deposit button, so
                // it's inline here; every other tab still gets the
                // floating version (see MainTabView).
                HStack {
                    Spacer()
                    AskAIButton(selectedTab: $selectedTab, isPro: entitlementManager.isPro)
                }
                .padding(.horizontal, Layout.pageMargin)
                .padding(.top, 16)

                Spacer()

                // Deposit Button — the one action this screen should
                // drive toward, so it's the only fully-filled control on
                // screen and shares the same edge margin as everything
                // else (including the dock below it).
                PrimaryCTAButton(accent: theme.accent, onAccent: theme.onAccent, action: { showDepositSheet = true }) {
                    Text("Deposit funds")
                }
                .padding(.horizontal, Layout.pageMargin)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { topSafeAreaInset = proxy.safeAreaInsets.top }
            }
        )
        .onAppear { loadProfileImage() }
        .sheet(isPresented: $showDepositSheet) {
            AestheticDepositModalView(currentSavings: $currentSavings) { amount in
                depositSavings(amount: amount)
            }
        }
        .sheet(isPresented: $showSetupGoalSheet) {
            SetupGoalView(
                goalTitle: $goalTitle,
                goalKindRaw: $goalKindRaw,
                targetGoal: $targetGoal,
                currentSavings: $currentSavings,
                targetDate: $targetDate
            )
        }
        .themedSurface(ignoresSafeArea: true)
        .sheet(isPresented: $showAddGoalSheet) {
            SetupGoalView(
                goalTitle: $newGoalTitle,
                goalKindRaw: $newGoalKindRaw,
                targetGoal: $newGoalTarget,
                currentSavings: $newGoalSavings,
                targetDate: $newGoalDate,
                customVoxelBlueprint: $newGoalVoxelBlueprintJSON,
                onSave: {
                    goalStore.addGoal(
                        title: newGoalTitle,
                        kindRaw: newGoalKindRaw,
                        targetAmount: newGoalTarget,
                        targetDate: newGoalDate,
                        customVoxelBlueprintJSON: newGoalVoxelBlueprintJSON
                    )
                }
            )
        }
        .sheet(isPresented: $showProfile, onDismiss: {
            profileImageData = UserDefaults.standard.data(forKey: profileImageKey)
        }) {
            ProfileView()
        }
        .sheet(isPresented: $showPaywall) {
            CustomPaywallView(
                goalTitle: goalTitle,
                targetGoal: targetGoal,
                currentSavings: currentSavings,
                chatMessages: $chatMessages,
                selectedTab: $selectedTab
            )
        }
    }

    private func loadProfileImage() {
        profileImageData = UserDefaults.standard.data(forKey: profileImageKey)
    }

    private func depositSavings(amount: Double) {
        currentSavings += amount
        streakManager.recordDeposit()
        #if !SKIP
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        showBurst = true

        // If the active goal is shared, this is the ONLY place a deposit
        // toward it happens, so it also has to be the place that reaches
        // the server — otherwise `currentSavings` above updates this
        // device only, shared_deposits never gets a row, and the partner
        // (and SharedBudgetView's own total) never sees it. Fire-and
        // -forget is intentional here so a slow/failed network call never
        // blocks the local deposit animation the user already sees; a
        // failure surfaces via sharedBudgetManager.errorMessage the next
        // time SharedBudgetView is opened, same as any other failed call
        // in that manager.
        if let sharedID = goalStore.activeGoal?.sharedGoalID {
            Task {
                await sharedBudgetManager.addDeposit(
                    sharedGoalID: sharedID,
                    contributorID: myID,
                    contributorName: leaderboardManager.myDisplayName,
                    amount: amount,
                    accessToken: authManager.accessToken
                )
            }
        }
    }
}

// MARK: - Separate Deposit Forge Modal View
struct AestheticDepositModalView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var theme: ThemeManager
    @Binding var currentSavings: Double
    var onDeposit: (Double) -> Void

    @State private var customAmount: String = "100"
    @State private var artifactRotation: Float = Float(0.0)
    // NOTE(skip): without the decimal points, Skip transpiles this
    // literal array as Array<Int>, not Array<Double>, which is exactly
    // the "Assignment type mismatch" error — Swift infers Double from
    // the `[Double]` annotation, but Kotlin needs the literals spelled
    // out.
    let quickAmounts: [Double] = [25.0, 50.0, 100.0, 250.0]

    var body: some View {
        ZStack {
            // 3D Assembly Preview Forge Background
            forgeBackground
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                        // Explicit Float(...) cast: Kotlin needs a concrete
                        // type here rather than inferring it from context
                        // the way Swift does with bare `.pi`.
                        artifactRotation = Float(Double.pi * 2)
                    }
                }

            VStack(spacing: 28) {
                Text("Add a deposit")
                    .font(theme.font(22, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.top, 40)

                // Quick Amount Chips
                HStack(spacing: 12) {
                    ForEach(quickAmounts, id: \.self) { amt in
                        Button(action: { customAmount = "\(Int(amt))" }) {
                            Text("+$\(Int(amt))")
                                .font(theme.font(12, weight: .bold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(customAmount == "\(Int(amt))" ? theme.accent : (theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.07)))
                                .foregroundColor(customAmount == "\(Int(amt))" ? theme.onAccent : theme.textPrimary)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(customAmount == "\(Int(amt))" ? Color.clear : theme.cardStroke, lineWidth: 1.2))
                        }
                    }
                }

                // Amount Input
                VStack(spacing: 6) {
                    SectionLabel("Amount ($)")

                    TextField("Amount", text: $customAmount)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(theme.font(52, weight: .ultraLight))
                        .foregroundStyle(.primary)
                }

                Spacer()

                PrimaryCTAButton(accent: theme.accent, onAccent: theme.onAccent, action: {
                    if let amt = Double(customAmount), amt > 0 {
                        onDeposit(amt)
                        dismiss()
                    }
                }) {
                    Text("Confirm deposit")
                }
                .padding(.horizontal, Layout.pageMargin)
                .padding(.bottom, 44)
            }
        }
        .themedSurface(ignoresSafeArea: true)
    }

    /// The rotating 3D "forge" artifact behind the deposit sheet on iOS,
    /// with a pure-SwiftUI animated equivalent on Android — RealityKit
    /// itself isn't available under Skip, but the same spinning-object
    /// feel is easy to approximate with a rotating gradient shape so the
    /// screen isn't just flat on Android.
    @ViewBuilder
    private var forgeBackground: some View {
        #if !SKIP
        if #available(iOS 18.0, *) {
            RealityView { content in
                let mesh = MeshResource.generateBox(size: [0.4, 0.4, 0.4], cornerRadius: 0.04)
                let material = SimpleMaterial(color: UIColor(theme.accent), isMetallic: true)
                let entity = ModelEntity(mesh: mesh, materials: [material])
                entity.name = "forgeArtifact"
                entity.position = [0, 0.1, -0.9]
                content.add(entity)

                let keyLight = Entity()
                keyLight.components.set(DirectionalLightComponent(color: .white, intensity: 4000))
                keyLight.look(at: [0, 0.1, -0.9], from: [0.5, 0.6, -0.4], relativeTo: nil)
                content.add(keyLight)

                let fillLight = Entity()
                fillLight.components.set(PointLightComponent(color: .white, intensity: 3000, attenuationRadius: 4))
                fillLight.position = [-0.4, 0, -0.7]
                content.add(fillLight)
            } update: { content in
                if let entity = content.entities.first(where: { $0.name == "forgeArtifact" }) {
                    entity.orientation = simd_quatf(angle: artifactRotation, axis: [0, 1, 0])
                }
            }
        } else {
            // Fallback for earlier iOS versions
            EmptyView()
        }
        #else
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [theme.accent.opacity(0.35), theme.accent.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 140, height: 140)
                .rotation3DEffect(.radians(Double(artifactRotation)), axis: (x: 0, y: 1, z: 0))
                .position(x: geo.size.width / 2, y: geo.size.height * 0.32)
                .blur(radius: 2)
        }
        #endif
    }
}
