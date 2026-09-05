import SwiftUI
#if !SKIP
import RealityKit
#endif

public struct ContentView: View {
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
    @State private var newGoalDate: Date = Calendar.current.date(byAdding: Calendar.Component.month, value: 3, to: Date()) ?? Date()
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
        let hour = Calendar.current.component(Calendar.Component.hour, from: Date())
        let name = leaderboardManager.myDisplayName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
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
        GeometryReader { rootGeo in
            let topInset = rootGeo.safeAreaInsets.top

            ZStack {
                RadialGradient(
                    colors: [theme.textPrimary.opacity(0.1), Color.clear],
                    center: UnitPoint.center, startRadius: 10, endRadius: 280
                )
                .offset(y: -40)
                .allowsHitTesting(false)

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
                                                .fill(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "person.fill")
                                                .font(theme.font(15, weight: Font.Weight.light))
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
                                        .font(theme.font(18, weight: Font.Weight.semibold))
                                        .foregroundStyle(theme.textPrimary.opacity(0.95))
                                } else {
                                    VaultButton(
                                        "Pro",
                                        variant: VaultButtonVariant.ghost,
                                        horizontalPadding: 0.0,
                                        fullWidth: false,
                                        action: { showPaywall = true }
                                    )
                                    .fixedSize()
                                }

                                Spacer()

                                HStack(spacing: 10) {
                                    HeaderIconButton(systemName: "calendar") { selectedTab = 2 }
                                    PrivacyQuickToggleButton()
                                }
                            }
                            .padding(Edge.Set.horizontal, Layout.pageMargin)

                            // 2. Row 2: Active Journey Selector Button
                            HStack {
                                VaultButton(
                                    variant: VaultButtonVariant.ghost,
                                    height: 36.0,
                                    horizontalPadding: 0.0,
                                    fullWidth: false,
                                    action: {
                                        showSetupGoalSheet = true
                                    },
                                    label: AnyView(
                                        HStack(spacing: 8) {
                                            Image.platformSymbol(goalKind.displayIcon, android: goalKind.androidDisplayIcon)
                                                .font(theme.font(13, weight: Font.Weight.medium))
                                                .foregroundStyle(theme.accent)

                                            Text(goalTitle.isEmpty ? "Choose a journey" : goalTitle)
                                                .font(theme.font(14, weight: Font.Weight.semibold))
                                                .foregroundStyle(theme.textPrimary.opacity(0.9))

                                            Image(systemName: "chevron.down")
                                                .font(theme.font(10, weight: Font.Weight.semibold))
                                                .foregroundStyle(theme.textTertiary)
                                        }
                                        .padding(Edge.Set.horizontal, 16)
                                        .padding(Edge.Set.vertical, 8)
                                    )
                                )

                                Spacer()
                            }
                            .padding(Edge.Set.horizontal, Layout.pageMargin)
                        }
                        #if !SKIP
                        .padding(Edge.Set.top, topInset + 25)
                        #else
                        .padding(Edge.Set.top, 12)
                        #endif

                        // Goal Picker
                        GoalPickerBar(goalStore: goalStore) {
                            newGoalTitle = ""
                            newGoalKindRaw = GoalKind.flight.rawValue
                            newGoalTarget = 1200.0
                            newGoalSavings = 0.0
                            newGoalDate = Calendar.current.date(byAdding: Calendar.Component.month, value: 3, to: Date()) ?? Date()
                            newGoalVoxelBlueprintJSON = nil
                            showAddGoalSheet = true
                        }
                        .padding(Edge.Set.top, 16)

                        // Editorial Hero Progress Text
                        ZStack {
                            VStack(spacing: 4) {
                                Text("\(Int(displayProgress * 100))%")
                                    #if !SKIP
                                    .font(theme.font(92, weight: Font.Weight.ultraLight))
                                    #else
                                    .font(theme.font(68, weight: Font.Weight.ultraLight))
                                    #endif
                                    .tracking(-3)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [theme.textPrimary, theme.textPrimary.opacity(0.75)],
                                            startPoint: UnitPoint.top, endPoint: UnitPoint.bottom
                                        )
                                    )

                                HStack(spacing: 8) {
                                    Text("$\(Int(currentSavings))")
                                        .font(theme.font(16, weight: Font.Weight.medium))
                                        .foregroundStyle(theme.accent)

                                    Text("of $\(Int(targetGoal))")
                                        .font(theme.font(13, weight: Font.Weight.medium))
                                        .foregroundStyle(Color.secondary)
                                }

                                if currentSavings == 0.0 {
                                    Text("Head start for creating your goal — deposit to keep it moving")
                                        .font(theme.font(9, weight: Font.Weight.light))
                                        .foregroundStyle(Color.secondary)
                                        .padding(Edge.Set.top, 2)
                                }

                                // Minimalist Hairline Progress Line
                                GeometryReader { geo in
                                    ZStack(alignment: Alignment.leading) {
                                        Rectangle()
                                            .fill(theme.hairline)

                                        Rectangle()
                                            .fill(theme.accent)
                                            .frame(width: geo.size.width * CGFloat(displayProgress))
                                    }
                                }
                                .frame(height: 2)
                                .padding(Edge.Set.horizontal, 80)
                                .padding(Edge.Set.top, 12)
                            }
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
                        #if !SKIP
                        .padding(Edge.Set.top, 20)
                        #else
                        .padding(Edge.Set.top, 12)
                        #endif

                        SavingsTrendChart(
                            history: goalStore.activeGoal?.history ?? [],
                            targetAmount: targetGoal
                        )
                        #if !SKIP
                        .padding(Edge.Set.top, 24)
                        #else
                        .padding(Edge.Set.top, 14)
                        #endif

                        HStack {
                            Spacer()
                            AskAIButton(selectedTab: $selectedTab, isPro: entitlementManager.isPro)
                        }
                        .padding(Edge.Set.horizontal, Layout.pageMargin)
                        #if !SKIP
                        .padding(Edge.Set.top, 16)
                        #else
                        .padding(Edge.Set.top, 10)
                        #endif

                        Spacer()

                        PrimaryCTAButton(accent: theme.accent, onAccent: theme.onAccent, action: { showDepositSheet = true }) {
                            Text("Deposit funds")
                        }
                        .padding(Edge.Set.horizontal, Layout.pageMargin)
                        .padding(Edge.Set.bottom, 24)
                    }
                    .frame(minHeight: rootGeo.size.height)
                }
            }
            .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
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
public struct AestheticDepositModalView: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @EnvironmentObject var theme: ThemeManager
    @Binding var currentSavings: Double
    var onDeposit: (Double) -> Void

    @State private var customAmount: String = "100"
    @State private var artifactRotation: Float = Float(0.0)

    let quickAmounts: [Double] = [25.0, 50.0, 100.0, 250.0]

    var body: some View {
        ZStack {
            forgeBackground
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(Animation.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                        artifactRotation = Float(Double.pi * 2)
                    }
                }

            VStack(spacing: 28) {
                Text("Add a deposit")
                    .font(theme.font(22, weight: Font.Weight.bold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(Edge.Set.top, 40)

                // Quick Amount Chips
                HStack(spacing: 12) {
                    ForEach(quickAmounts, id: \.self) { amt in
                        VaultButton(
                            "+$\(Int(amt))",
                            variant: customAmount == "\(Int(amt))" ? VaultButtonVariant.primary : VaultButtonVariant.secondary,
                            height: 40.0,
                            fontSize: 12.0,
                            fontWeight: Font.Weight.bold,
                            horizontalPadding: 0.0,
                            fullWidth: false,
                            action: {
                                customAmount = "\(Int(amt))"
                            }
                        )
                        .fixedSize()
                    }
                }

                // Amount Input
                VStack(spacing: 6) {
                    SectionLabel("Amount ($)")

                    TextField("Amount", text: $customAmount)
                        .keyboardType(UIKeyboardType.numberPad)
                        .multilineTextAlignment(TextAlignment.center)
                        .font(theme.font(52, weight: Font.Weight.ultraLight))
                        .foregroundStyle(Color.primary)
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
                .padding(Edge.Set.horizontal, Layout.pageMargin)
                .padding(Edge.Set.bottom, 44)
            }
        }
        .themedSurface(ignoresSafeArea: true)
    }

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
            EmptyView()
        }
        #else
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [theme.accent.opacity(0.35), theme.accent.opacity(0.05)],
                        startPoint: UnitPoint.topLeading, endPoint: UnitPoint.bottomTrailing
                    )
                )
                .frame(width: 140, height: 140)
                .rotation3DEffect(Angle.radians(Double(artifactRotation)), axis: (x: 0, y: 1, z: 0))
                .position(x: geo.size.width / 2, y: geo.size.height * 0.32)
                .blur(radius: 2)
        }
        #endif
    }
}
