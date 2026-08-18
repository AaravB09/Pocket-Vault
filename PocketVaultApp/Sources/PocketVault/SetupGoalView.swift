import SwiftUI

struct GoalPreset: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
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
private enum SetupStep: Int, CaseIterable {
    case goal, amount
}

struct SetupGoalView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var theme: ThemeManager

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
        GoalPreset(name: "Plane Ticket to Mexico", icon: "paperplane", defaultAmount: 1200, defaultMonths: 4),
        GoalPreset(name: "Gaming Rig", icon: "cpu", defaultAmount: 1500, defaultMonths: 3),
        GoalPreset(name: "New Car", icon: "car.side", defaultAmount: 8000, defaultMonths: 18),
        GoalPreset(name: "Emergency Fund", icon: "shield", defaultAmount: 1000, defaultMonths: 6)
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

    var body: some View {
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
                    .padding(.top, 20)
                    .padding(.bottom, isOnboarding ? 140.0 : 220.0) // FIXED TYPE INFERENCE HERE
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
                    .font(theme.font(14, weight: .semibold))
                    .foregroundStyle(.primary)
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
                    .font(theme.font(14, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
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
            LinearGradient(colors: [theme.background.opacity(0), theme.background], startPoint: .top, endPoint: .bottom)
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
                        Image(systemName: "arrow.right")
                    }
                }
            }
            .disabled(!isStepValid)
            .animation(.easeInOut(duration: 0.2), value: isStepValid)
            .padding(.horizontal, Layout.pageMargin)
            .padding(.bottom, ctaBottomPadding)
            .background(theme.background)
        }
    }

    private func goNext() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let idx = SetupStep.allCases.firstIndex(of: step), idx < totalSteps - 1 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                step = SetupStep.allCases[idx + 1]
            }
        } else {
            confirmGoal()
        }
    }

    private func goBack() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let idx = SetupStep.allCases.firstIndex(of: step), idx > 0 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
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
                    .font(theme.font(22, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            aiGoalCard
                .padding(.horizontal, Layout.pageMargin)

            HStack {
                Rectangle().fill(theme.hairline).frame(height: 1)
                Text("or pick a quick preset")
                    .font(theme.font(12, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize()
                Rectangle().fill(theme.hairline).frame(height: 1)
            }
            .padding(.horizontal, Layout.pageMargin)

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
                        targetDate = Calendar.current.date(byAdding: .month, value: preset.defaultMonths, to: Date()) ?? targetDate
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }) {
                        HStack(spacing: 14) {
                            Image(systemName: preset.icon)
                                .font(theme.font(16, weight: .light))
                                .foregroundStyle(isSelected ? theme.onAccent : theme.textTertiary)

                            Text(preset.name)
                                .font(theme.font(15, weight: .semibold))
                                .foregroundStyle(isSelected ? theme.onAccent : .primary)

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(theme.font(12, weight: .bold))
                                    .foregroundStyle(theme.onAccent)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(isSelected ? theme.accent : (theme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.03)))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.clear : theme.hairline, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, Layout.pageMargin)
        }
    }

    // MARK: - Step 2: Amount

    private var amountStepContent: some View {
        VStack(spacing: 6) {
            SectionLabel("Target value")

            Text("How much are you aiming for?")
                .font(theme.font(22, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 24)

            AmountScrubPicker(amount: amountBinding)
        }
        .padding(.horizontal, Layout.pageMargin)
    }

    // MARK: - AI Goal Card
    private var aiGoalCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.accent)
                Text("Describe your own goal")
                    .font(theme.font(14, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }

            Text("A weekend trip, a gift, a goal just for this week — say it in your own words.")
                .font(theme.font(12, weight: .light))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("", text: $customGoalDescription, prompt: Text("e.g. \"a weekend trip to Tahoe\"").foregroundColor(theme.textTertiary), axis: .vertical)
                .foregroundStyle(.primary)
                .font(theme.font(14, weight: .light))
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
            // the ProgressView's tint is matched to that instead of carrying
            // over the old onAccent tint, which would have been the wrong
            // color even if it still compiled.
            SecondaryCTAButton(accent: theme.accent, action: { Task { await generateSuggestion() } }) {
                HStack(spacing: 8) {
                    if isGeneratingSuggestion { ProgressView().tint(theme.accent) }
                    Text(isGeneratingSuggestion ? "Thinking…" : "Generate with AI")
                }
            }
            .disabled(isGeneratingSuggestion || customGoalDescription.trimmingCharacters(in: .whitespaces).isEmpty)

            if let aiErrorMessage {
                Text(aiErrorMessage)
                    .font(theme.font(11))
                    .foregroundStyle(theme.danger.opacity(0.9))
                    .multilineTextAlignment(.center)
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
                    .font(theme.font(15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("$\(Int(suggestion.suggestedAmount))")
                    .font(theme.font(14, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }

            Text(suggestion.rationale)
                .font(theme.font(11, weight: .light))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: applySuggestion) {
                HStack(spacing: 6) {
                    Image(systemName: isApplied ? "checkmark.circle.fill" : "arrow.turn.right.down")
                    Text(isApplied ? "Applied" : "Use this goal")
                }
                .font(theme.font(14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
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
        isGeneratingSuggestion = true
        aiErrorMessage = nil
        aiSuggestion = nil
        do {
            let suggestion = try await AIGoalBuilderService.suggestGoal(from: customGoalDescription)
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
        targetDate = Calendar.current.date(byAdding: .day, value: aiSuggestion.suggestedTimeframeDays, to: Date()) ?? targetDate
        resolvedGoalKind = aiSuggestion.goalKind
        resolvedVoxelBlueprintJSON = aiSuggestion.voxelBlueprintJSON
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
