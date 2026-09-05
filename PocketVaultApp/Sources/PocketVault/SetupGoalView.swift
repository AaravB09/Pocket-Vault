import SwiftUI

public struct GoalPreset: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    // Skip/Android has no equivalent for "cpu", "car.side", or "shield" —
    // see PlatformSymbol.swift — so each preset carries its own Android
    // stand-in rather than falling back to the warning-triangle glyph.
    let androidIcon: String
    let defaultAmount: Double
    let defaultMonths: Int // smart default: typical timeframe for this kind of goal
}

/// The screens of the setup flow, in order. Each is a single focused
/// question — matching Clucky's one-question-per-screen onboarding
/// rather than one long scrolling form.
///
/// No dedicated date step: the target date already gets a sensible
/// default the moment a goal or preset is picked (see the preset button
/// and applySuggestion() below), and fine-tuning it matters mostly for
/// Pro features like calendar sync and AI coaching pace — not something
/// worth a whole onboarding screen for every user. It stays editable
/// later from wherever goal details are shown.
public enum SetupStep: Int, CaseIterable {
    case goal, amount
}

public struct SetupGoalView: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var authManager: AuthManager

    @Binding var goalTitle: String
    @Binding var goalKindRaw: String
    @Binding var targetGoal: Double
    @Binding var currentSavings: Double
    @Binding var targetDate: Date
    // JSON blueprint for an AI-generated custom sculpture — see
    // Goal.customVoxelBlueprintJSON. Written back here on confirm so a
    // custom goal like "cat food" keeps looking like cat food instead of
    // silently reverting to the generic gift box.
    var customVoxelBlueprint: Binding<String?> = .constant(nil)

    var isOnboarding: Bool = false
    var onSave: (() -> Void)? = nil

    @State private var step: SetupStep = .goal

    // Smart defaults: most people never touch these, so the first (and
    // most common) preset is pre-selected rather than starting blank.
    @State private var selectedPresetName: String = "Plane Ticket to Mexico"
    @State private var amountText: String = "1200"

    // AI custom goal builder — free-text description in, a concrete
    // suggested title/amount/timeframe out. Lets goals like "a weekend
    // trip" or "something for this week" resolve to a realistic
    // short-term plan instead of being forced into the fixed presets
    // below, which all skew toward multi-month goals.
    @State private var customGoalDescription: String = ""
    @State private var isGeneratingSuggestion: Bool = false
    @State private var aiSuggestion: AIGoalBuilderService.Suggestion?
    @State private var aiErrorMessage: String?

    // Tracks which GoalKind (and therefore which 3D build) the current
    // selection maps to. Presets set this directly from their known kind;
    // the AI path sets it from the model's classification instead of
    // re-deriving it from the title text, which would otherwise always
    // land on .custom for anything the model names.
    @State private var resolvedGoalKind: GoalKind = .custom

    // JSON blueprint for a bespoke AI-generated sculpture — only set (and
    // only used) when resolvedGoalKind is .custom and the model actually
    // pictured a specific shape for the item. Cleared whenever a preset
    // is chosen instead, since presets always use a fixed GoalKind build.
    @State private var resolvedVoxelBlueprintJSON: String? = nil

    let presets: [GoalPreset] = [
        GoalPreset(name: "Plane Ticket to Mexico", icon: "paperplane", androidIcon: "paperplane", defaultAmount: 1200, defaultMonths: 4),
        GoalPreset(name: "Gaming Rig", icon: "cpu", androidIcon: "gearshape.fill", defaultAmount: 1500, defaultMonths: 3),
        GoalPreset(name: "New Car", icon: "car.side", androidIcon: "cart.fill", defaultAmount: 8000, defaultMonths: 18),
        GoalPreset(name: "Emergency Fund", icon: "shield", androidIcon: "lock.fill", defaultAmount: 1000, defaultMonths: 6)
    ]

    private var isAmountValid: Bool {
        guard let value = Double(amountText) else { return false }
        return value > 0
    }

    private var amountBinding: Binding<Double> {
        Binding(
            // NOTE(skip): bare `?? 0` here left the Elvis operator's two
            // branches as Double and Int, which Kotlin can't unify — it
            // infers `Number & Comparable<CapturedType(*)>` instead of
            // Double, which then surfaces as several different-looking
            // errors (return type mismatch, argument type mismatch)
            // depending on where the type checker catches it. Same fix
            // as elsewhere in the app: spell out the Double literal.
            get: { Double(amountText) ?? 0.0 },
            set: { amountText = "\(Int($0.rounded()))" }
        )
    }

    private var currentStepIndex: Int { SetupStep.allCases.firstIndex(of: step) ?? 0 }
    private var totalSteps: Int { SetupStep.allCases.count }

    // Only the amount step has a real validity gate — a goal always has a
    // default preset selected, so it's "valid" the moment you land on it.
    private var isStepValid: Bool {
        switch step {
        case .goal: return true
        case .amount: return isAmountValid
        }
    }

    private var ctaTitle: String {
        switch step {
        case .goal: return "Continue"
        case .amount: return isOnboarding ? "Begin" : "Save journey"
        }
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 28) {
                        switch step {
                        case .goal: goalStepContent
                        case .amount: amountStepContent
                        }
                    }
                    .padding(Edge.Set.top, 20)
                    .padding(Edge.Set.bottom, isOnboarding ? 140.0 : 220.0) // FIXED TYPE INFERENCE HERE
                }
            }

            VStack {
                Spacer()
                pinnedCTA
            }
        }
        // FIX: Replaced `theme` with `ignoresSafeArea: true` to fix the compiler error
        // shown in "Screenshot 2026-08-17 at 9.18.03 PM.jpg"
        .themedSurface(ignoresSafeArea: true)
        .onAppear {
            if !goalTitle.isEmpty, presets.contains(where: { $0.name == goalTitle }) {
                selectedPresetName = goalTitle
            }
            if targetGoal > 0 {
                amountText = "\(Int(targetGoal))"
            }
            if let existingKind = GoalKind(rawValue: goalKindRaw) {
                resolvedGoalKind = existingKind
            }
            resolvedVoxelBlueprintJSON = customVoxelBlueprint.wrappedValue
        }
        .interactiveDismissDisabled(isOnboarding)
    }

    // MARK: - Header (back / progress / skip)

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(theme.font(14, weight: Font.Weight.semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 34, height: 34)
                    .background(theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                    // NOTE(skip): `.clipShape` isn't resolved by Skip's
                    // SwiftUI shim — `.cornerRadius` at half the frame's
                    // width/height renders as the same circle on Android.
                    #if !SKIP
                    .clipShape(Circle())
                    #else
                    .cornerRadius(17)
                    #endif
            }

            HStack(spacing: 5) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= currentStepIndex ? theme.accent : theme.hairline)
                        .frame(height: 3)
                }
            }

            Button(action: goNext) {
                Text("Skip")
                    .font(theme.font(14, weight: Font.Weight.medium))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(Edge.Set.horizontal, 20)
        .padding(Edge.Set.top, 16)
    }

    // MARK: - Pinned CTA

    // During onboarding this view is presented full-screen (.fullScreenCover
    // in Pocket_VaultApp.swift) with nothing below it, so 20pt of bottom
    // padding is enough to clear the home indicator. As the "GOALS" tab,
    // though, it's rendered inline inside MainTabView's own ZStack, and
    // MainTabView draws its floating glass tab bar as a SIBLING on top of
    // that — this view has no way to know the tab bar is there, so without
    // extra clearance the CTA renders right underneath it and becomes
    // unreachable. 100pt clears the tab bar's ~64pt content height plus its
    // padding and shadow with a little room to spare.
    private var ctaBottomPadding: CGFloat { isOnboarding ? 20.0 : 100.0 }

    private var pinnedCTA: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [theme.background.opacity(0), theme.background], startPoint: UnitPoint.top, endPoint: UnitPoint.bottom)
                .frame(height: 36)
                .allowsHitTesting(false)

            // FIX: `.buttonStyle(PrimaryCTAButtonStyle(...))` referenced a
            // custom ButtonStyle type that no longer exists — see the long
            // comment above PrimaryCTAButton in ThemeManager.swift for why
            // custom ButtonStyle conformance was dropped app-wide in favor
            // of plain wrapper views. Use PrimaryCTAButton directly instead
            // of a Button + buttonStyle pair; the disabled/animation/padding
            // modifiers that were chained after .buttonStyle(...) still work
            // the same way chained after the wrapper.
            PrimaryCTAButton(
                accent: isStepValid ? theme.accent : theme.accent.opacity(0.3),
                onAccent: theme.onAccent,
                action: goNext
            ) {
                HStack(spacing: 8) {
                    Text(ctaTitle)
                    if step != .amount {
                        Image(systemName: "arrow.forward")
                    }
                }
            }
            .disabled(!isStepValid)
            .animation(Animation.easeInOut(duration: 0.2), value: isStepValid)
            .padding(Edge.Set.horizontal, Layout.pageMargin)
            .padding(Edge.Set.bottom, ctaBottomPadding)
            .background(theme.background)
        }
    }

    private func goNext() {
        // NOTE(skip): UIImpactFeedbackGenerator isn't safe to actually
        // invoke on Android — it compiles under Skip but crashes at
        // runtime when `impactOccurred()` is called. Same guard used
        // everywhere else in the app (see AmountScrubPicker,
        // BuildStudioView, MainTabView, etc.) — this one was missing,
        // which is why the "Continue" button on the Goal step force-
        // closed the app on Android.
        #if !SKIP
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if let idx = SetupStep.allCases.firstIndex(of: step), idx < totalSteps - 1 {
            withAnimation(Animation.spring(response: 0.35, dampingFraction: 0.85)) {
                step = SetupStep.allCases[idx + 1]
            }
        } else {
            confirmGoal()
        }
    }

    private func goBack() {
        #if !SKIP
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if let idx = SetupStep.allCases.firstIndex(of: step), idx > 0 {
            withAnimation(Animation.spring(response: 0.35, dampingFraction: 0.85)) {
                step = SetupStep.allCases[idx - 1]
            }
        } else {
            dismiss()
        }
    }

    // MARK: - Step 1: Goal

    private var goalStepContent: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                SectionLabel(isOnboarding ? "Choose your destination" : "Update journey")

                Text("What are you building toward?")
                    .font(theme.font(22, weight: Font.Weight.semibold))
                    .foregroundStyle(Color.primary)
            }

            aiGoalCard
                .padding(Edge.Set.horizontal, Layout.pageMargin)

            HStack {
                Rectangle().fill(theme.hairline).frame(height: 1)
                Text("or pick a quick preset")
                    .font(theme.font(12, weight: Font.Weight.medium))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize()
                Rectangle().fill(theme.hairline).frame(height: 1)
            }
            .padding(Edge.Set.horizontal, Layout.pageMargin)

            VStack(spacing: 12) {
                ForEach(presets) { preset in
                    let isSelected = selectedPresetName == preset.name

                    Button(action: {
                        selectedPresetName = preset.name
                        amountText = "\(Int(preset.defaultAmount))"
                        aiSuggestion = nil
                        resolvedGoalKind = GoalKind.from(presetName: preset.name)
                        resolvedVoxelBlueprintJSON = nil
                        // Smart default: seed a realistic target date for this
                        // kind of goal instead of leaving "today" selected.
                        targetDate = Calendar.current.date(byAdding: Calendar.Component.month, value: preset.defaultMonths, to: Date()) ?? targetDate
                        #if !SKIP
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    }) {
                        HStack(spacing: 14) {
                            Image.platformSymbol(preset.icon, android: preset.androidIcon)
                                .font(theme.font(16, weight: Font.Weight.light))
                                .foregroundStyle(isSelected ? theme.onAccent : theme.textTertiary)

                            Text(preset.name)
                                .font(theme.font(15, weight: Font.Weight.semibold))
                                .foregroundStyle(isSelected ? theme.onAccent : .primary)

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(theme.font(12, weight: Font.Weight.bold))
                                    .foregroundStyle(theme.onAccent)
                            }
                        }
                        .padding(Edge.Set.horizontal, 20)
                        .padding(Edge.Set.vertical, 16)
                        .background(
                            Capsule()
                                .fill(isSelected ? theme.accent : (theme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.03)))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.clear : theme.hairline, lineWidth: 1)
                        )
                    }
                    // NOTE(skip): same root cause as PrimaryCTAButton /
                    // SecondaryCTAButton / TertiaryCTAButton in
                    // Thememanager.swift — a bare `Button` with no
                    // `.buttonStyle` picks up Skip/Compose's default
                    // Material button styling on Android, which paints its
                    // own (dark/black) container OVER this Button's actual
                    // content instead of just wrapping it. Every other
                    // custom button in the app already carries
                    // `.buttonStyle(PrimitiveButtonStyle.plain)` for exactly this reason; this
                    // preset row was the one Button left without it, which
                    // is why tapping any goal option here turned solid
                    // black on Android instead of showing the theme's
                    // accent color.
                    .buttonStyle(PrimitiveButtonStyle.plain)
                }
            }
            .padding(Edge.Set.horizontal, Layout.pageMargin)
        }
    }

    // MARK: - Step 2: Amount

    private var amountStepContent: some View {
        VStack(spacing: 6) {
            SectionLabel("Target value")

            Text("How much are you aiming for?")
                .font(theme.font(22, weight: Font.Weight.semibold))
                .foregroundStyle(Color.primary)
                .padding(Edge.Set.bottom, 24)

            AmountScrubPicker(amount: amountBinding)
        }
        .padding(Edge.Set.horizontal, Layout.pageMargin)
    }

    // MARK: - AI Goal Card
    private var aiGoalCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image.platformSymbol("sparkles", android: "star.fill")
                    .foregroundStyle(theme.accent)
                Text("Describe your own goal")
                    .font(theme.font(14, weight: Font.Weight.semibold))
                    .foregroundStyle(theme.accent)
            }

            Text("A weekend trip, a gift, a goal just for this week — say it in your own words.")
                .font(theme.font(12, weight: Font.Weight.light))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(TextAlignment.center)

            TextField("", text: $customGoalDescription, prompt: Text("e.g. \"a weekend trip to Tahoe\"").foregroundColor(theme.textTertiary), axis: Axis.vertical)
                .foregroundStyle(Color.primary)
                .font(theme.font(14, weight: Font.Weight.light))
                .padding(14)
                // NOTE(skip): `.ultraThinMaterial` and `.clipShape` aren't
                // resolved by Skip's SwiftUI shim — iOS keeps the real
                // material + shape clip, Android gets a plain tinted
                // background + `.cornerRadius`, same pattern used
                // everywhere else in the app.
                #if !SKIP
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                #else
                .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                .cornerRadius(14)
                #endif
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))

            // FIX: `.buttonStyle(.secondaryCTA(theme))` is the same leftover
            // pattern as PrimaryCTAButtonStyle above — that ButtonStyle no
            // longer exists. SecondaryCTAButton's own foreground color is
            // `accent` (not onAccent, unlike the primary/filled button), so
            // its built-in `isLoading` spinner is matched to that automatically.
            SecondaryCTAButton(
                accent: theme.accent,
                isLoading: isGeneratingSuggestion,
                action: { Task { await generateSuggestion() } }
            ) {
                Text("Generate with AI")
            }
            .disabled(customGoalDescription.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty)

            if let aiErrorMessage {
                Text(aiErrorMessage)
                    .font(theme.font(11))
                    .foregroundStyle(theme.danger.opacity(0.9))
                    .multilineTextAlignment(TextAlignment.center)
            }

            if let aiSuggestion {
                suggestionResultCard(aiSuggestion)
            }
        }
        .padding(20)
        #if !SKIP
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        #else
        .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
        .cornerRadius(20)
        #endif
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.accent.opacity(0.3), lineWidth: 1))
    }

    private func suggestionResultCard(_ suggestion: AIGoalBuilderService.Suggestion) -> some View {
        let isApplied = selectedPresetName == suggestion.title

        return VStack(spacing: 10) {
            HStack {
                Text(suggestion.title)
                    .font(theme.font(15, weight: Font.Weight.semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
                Text("$\(Int(suggestion.suggestedAmount))")
                    .font(theme.font(14, weight: Font.Weight.semibold))
                    .foregroundStyle(theme.accent)
            }

            Text(suggestion.rationale)
                .font(theme.font(11, weight: Font.Weight.light))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(TextAlignment.leading)
                .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)

            Button(action: applySuggestion) {
                HStack(spacing: 6) {
                    Image(systemName: isApplied ? "checkmark.circle.fill" : "arrow.turn.right.down")
                    Text(isApplied ? "Applied" : "Use this goal")
                }
                .font(theme.font(14, weight: Font.Weight.semibold))
                .frame(maxWidth: CGFloat.infinity)
                .padding(Edge.Set.vertical, 12)
                .background(isApplied ? theme.hairline : theme.accent.opacity(0.15))
                .foregroundColor(isApplied ? theme.accent : theme.textPrimary)
                // NOTE(skip): background here is already theme-agnostic,
                // but `.clipShape` itself is still unresolved under Skip.
                #if !SKIP
                .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius))
                #else
                .cornerRadius(Layout.controlRadius)
                #endif
                .overlay(RoundedRectangle(cornerRadius: Layout.controlRadius).stroke(theme.accent.opacity(isApplied ? 0.5 : 0.2), lineWidth: 1))
            }
        }
        .padding(14)
        .background(theme.isLight ? Color.black.opacity(0.05) : Color.black.opacity(0.2))
        // NOTE(skip): same clipShape-only fix as the button above.
        #if !SKIP
        .clipShape(RoundedRectangle(cornerRadius: 14))
        #else
        .cornerRadius(14)
        #endif
    }

    private func generateSuggestion() async {
        guard let accessToken = authManager.accessToken else {
            aiErrorMessage = "Create an account to use AI goal suggestions."
            return
        }
        isGeneratingSuggestion = true
        aiErrorMessage = nil
        aiSuggestion = nil
        do {
            let suggestion = try await AIGoalBuilderService.suggestGoal(from: customGoalDescription, accessToken: accessToken)
            aiSuggestion = suggestion
        } catch {
            aiErrorMessage = error.localizedDescription
        }
        isGeneratingSuggestion = false
    }

    private func applySuggestion() {
        guard let aiSuggestion else { return }
        selectedPresetName = aiSuggestion.title
        amountText = "\(Int(aiSuggestion.suggestedAmount.rounded()))"
        targetDate = Calendar.current.date(byAdding: Calendar.Component.day, value: aiSuggestion.suggestedTimeframeDays, to: Date()) ?? targetDate
        resolvedGoalKind = aiSuggestion.goalKind
        resolvedVoxelBlueprintJSON = aiSuggestion.voxelBlueprintJSON
        #if !SKIP
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func confirmGoal() {
        goalTitle = selectedPresetName
        goalKindRaw = resolvedGoalKind.rawValue
        targetGoal = Double(amountText) ?? 1200.0
        customVoxelBlueprint.wrappedValue = resolvedVoxelBlueprintJSON
        onSave?()
        // targetDate is already live-bound via the DatePicker above.
        dismiss()
    }
}
