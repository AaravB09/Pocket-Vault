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
        // FIX (tab-switch glitch, Build -> Vault): the top inset used to
        // live in `@State private var topSafeAreaInset: CGFloat = 0`,
        // only ever set via `.onAppear` on a `GeometryReader` stuck in
        // this view's `.background`. That means the very first frame
        // this view ever draws — including every time MainTabView's
        // tab `switch` tears it down and rebuilds it fresh, which is
        // exactly what happens switching away from and back to this
        // tab — painted the header with `topSafeAreaInset` still 0, then
        // snapped to the real inset a frame later once `.onAppear` ran.
        // That one-frame jump is the "glitch" switching Build -> Vault:
        // BuildStudioView doesn't remeasure anything on appear, so it
        // never showed this; this view rebuilds from scratch every time
        // it's switched back to, so it did, every single time.
        //
        // Reading `GeometryProxy.safeAreaInsets.top` inline here instead
        // gives the correct value on the very first layout pass, with no
        // state and no `.onAppear` delay — nothing left to snap into
        // place after the fact.
        GeometryReader { rootGeo in
            let topInset = rootGeo.safeAreaInsets.top

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
                //
                // FIX (Android: Deposit button unreachable): this was the
                // only one of the main tabs (compare Budgettrackerview.swift
                // / CalenderView.swift, both wrapped in `ScrollView`) laid
                // out as a fixed-height VStack with a `Spacer()` pushing
                // the Deposit button down to the bottom edge, instead of
                // living inside a ScrollView. That only works if the
                // content is guaranteed to fit in whatever height is
                // available — true often enough across iPhone's fairly
                // uniform screen sizes, but Android's much wider spread of
                // screen sizes/aspect ratios (plus some devices' on-screen
                // nav bar eating extra height) means this content can end
                // up taller than the space actually available. With
                // nothing to scroll, that overflow pushed the Deposit
                // button — the last view in the stack — off the bottom of
                // the screen with no way to reach it. Wrapping in a
                // ScrollView (matching every other tab) fixes that:
                // `.frame(minHeight: rootGeo.size.height)` below keeps
                // today's fixed, non-scrolling look on screens where
                // everything already fits, and only starts scrolling on
                // the screens where it doesn't.
                ScrollView(showsIndicators: false) {
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
                                // FIX: was `Image(systemName: goalKind.displayIcon)`
                                // directly — see the note on
                                // GoalKind.androidDisplayIcon in
                                // Goalbuildmodels.swift. This is the journey
                                // selector at the top of the Vault tab, so a
                                // car/gaming-rig/emergency-fund/custom goal
                                // showed the "symbol not found" warning
                                // triangle here on every single screen visit.
                                Image.platformSymbol(goalKind.displayIcon, android: goalKind.androidDisplayIcon)
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
                // FIX (Android: huge blank gap above the header): this was
                // padding by the FULL raw `topInset` on Android with no
                // buffer trimmed off, on the assumption Android needed
                // exactly the safe-area value and nothing more. It
                // doesn't — Android's system window already reserves
                // space for the status bar before this view's own layout
                // pass starts, so re-applying the entire `topInset` on
                // top of that reserved space double-counts it, stacking
                // a second status-bar's worth of blank padding above the
                // header on every device (confirmed against a real
                // screenshot: ~10% of the whole screen height was empty
                // space before the profile row even started, which is
                // also what was shoving the Deposit button below the
                // fold). A small fixed value gets the same "clear of the
                // notch/status bar" spacing without double-paying for
                // it. iOS's buffer (which genuinely does need the full
                // `topInset`, since iOS doesn't reserve that space for
                // us) is untouched.
                #if !SKIP
                .padding(.top, topInset + 25)
                #else
                .padding(.top, 12)
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
                            // FIX (Android: fits without scrolling): 92pt
                            // was consuming a large share of the screen's
                            // vertical budget on top of the inset bug
                            // above — between the two, the Deposit button
                            // needed a scroll to reach on most Android
                            // screens even after the ScrollView fix.
                            // Smaller on Android only; iOS unchanged.
                            #if !SKIP
                            .font(theme.font(92, weight: .ultraLight))
                            #else
                            .font(theme.font(68, weight: .ultraLight))
                            #endif
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
                    //
                    // PERF (Android): `.blur` isn't implemented under Skip
                    // at all (see the identical note/fix in
                    // SavingsTrendChart.swift) — the `PrivacyRevealOverlay`
                    // right below already fully covers this content when
                    // masked, so the blur itself was dead weight on
                    // Android: a modifier evaluated on every recomposition
                    // of this screen's biggest, most frequently-updating
                    // view (the hero % / dollar text) for zero visible
                    // effect. Gating it to iOS-only removes that
                    // per-frame cost on Android with no change to what's
                    // shown on either platform.
                    #if !SKIP
                    .blur(radius: privacy.shouldMask ? 14.0 : 0.0)
                    #endif
                    .overlay {
                        if privacy.shouldMask {
                            PrivacyRevealOverlay()
                        }
                    }

                    ParticleBurstView(isActive: $showBurst)
                        .offset(y: -20)
                }
                // FIX (Android: fits without scrolling): trimmed slightly
                // alongside the chart's own top padding below, now that
                // the inset/hero-text fixes above have freed up real
                // room — small compounding gaps like these were the rest
                // of what pushed the Deposit button below the fold. iOS
                // unchanged.
                #if !SKIP
                .padding(.top, 20)
                #else
                .padding(.top, 12)
                #endif

                SavingsTrendChart(
                    history: goalStore.activeGoal?.history ?? [],
                    targetAmount: targetGoal
                )
                #if !SKIP
                .padding(.top, 24)
                #else
                .padding(.top, 14)
                #endif

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
                #if !SKIP
                .padding(.top, 16)
                #else
                .padding(.top, 10)
                #endif

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
                // See FIX note above the `ScrollView` that opens this
                // block — this `minHeight` is what keeps the layout
                // identical to before on screens tall enough to fit
                // everything, while letting it scroll instead of clip on
                // the ones that aren't.
                .frame(minHeight: rootGeo.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
