import SwiftUI

struct GoalPreset: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let defaultAmount: Double
    let defaultMonths: Int // smart default: typical timeframe for this kind of goal
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

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 6) {
                        Text(isOnboarding ? "CHOOSE YOUR DESTINATION" : "UPDATE JOURNEY")
                            .font(theme.font(11, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(theme.accent)

                        Text("What are you building toward?")
                            .font(theme.font(20, weight: .light))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .padding(.top, 50)

                    // AI custom goal builder — the primary entry point.
                    // Describe anything, any timeframe, and let the model
                    // fill in a realistic amount and date.
                    aiGoalCard
                        .padding(.horizontal, 24)

                    HStack {
                        Rectangle().fill(theme.hairline).frame(height: 1)
                        Text("OR PICK A QUICK PRESET")
                            .font(theme.font(9, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize()
                        Rectangle().fill(theme.hairline).frame(height: 1)
                    }
                    .padding(.horizontal, 24)

                    // Presets Grid
                    VStack(spacing: 12) {
                        ForEach(presets) { preset in
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
                                        .foregroundStyle(selectedPresetName == preset.name ? theme.accent : theme.textTertiary)

                                    Text(preset.name.uppercased())
                                        .font(theme.font(11, weight: .bold))
                                        .tracking(2)
                                        .foregroundStyle(theme.textPrimary)

                                    Spacer()

                                    if selectedPresetName == preset.name {
                                        Image(systemName: "sparkle")
                                            .font(theme.font(12))
                                            .foregroundStyle(theme.accent)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    Capsule()
                                        .fill(selectedPresetName == preset.name ? theme.accent.opacity(0.12) : (theme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.03)))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(selectedPresetName == preset.name ? theme.accent.opacity(0.5) : theme.hairline, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Amount Input
                    VStack(spacing: 8) {
                        Text("TARGET VALUE ($)")
                            .font(theme.font(9, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(theme.textTertiary)

                        TextField("Amount", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(theme.font(44, weight: .ultraLight))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .padding(.horizontal, 24)

                    // Target Date — lets the Coach and Ask AI talk about pacing
                    // from the very first deposit instead of guessing.
                    VStack(spacing: 8) {
                        Text("REACH IT BY")
                            .font(theme.font(9, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(theme.textTertiary)

                        DatePicker("", selection: $targetDate, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(theme.accent)
                            .colorScheme(theme.isLight ? .light : .dark)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)

                    Button(action: confirmGoal) {
                        Text(isOnboarding ? "BEGIN MANIFESTATION" : "SAVE JOURNEY")
                            .font(theme.font(13, weight: .bold))
                            .tracking(3.2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(theme.textPrimary)
                            .foregroundColor(theme.background)
                            .clipShape(Capsule())
                            .shadow(color: theme.textPrimary.opacity(0.3), radius: 18, y: 8)
                    }
                    .disabled(!isAmountValid)
                    .opacity(isAmountValid ? 1.0 : 0.4)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 60)
                }
            }
        }
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

    // MARK: - AI Goal Card
    private var aiGoalCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.accent)
                Text("DESCRIBE YOUR OWN GOAL")
                    .font(theme.font(10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(theme.accent)
            }

            Text("A weekend trip, a gift, a goal just for this week — say it in your own words.")
                .font(theme.font(12, weight: .light))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)

            TextField("", text: $customGoalDescription, prompt: Text("e.g. \"a weekend trip to Tahoe\"").foregroundColor(theme.textTertiary), axis: .vertical)
                .foregroundStyle(theme.textPrimary)
                .font(theme.font(14, weight: .light))
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))

            Button(action: { Task { await generateSuggestion() } }) {
                HStack(spacing: 8) {
                    if isGeneratingSuggestion { ProgressView().tint(theme.onAccent) }
                    Text(isGeneratingSuggestion ? "THINKING…" : "GENERATE WITH AI")
                        .font(theme.font(12, weight: .bold))
                        .tracking(2.2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(theme.accent)
                .foregroundColor(theme.onAccent)
                .clipShape(Capsule())
                .shadow(color: theme.accent.opacity(0.35), radius: 12, y: 5)
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
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.accent.opacity(0.3), lineWidth: 1))
    }

    private func suggestionResultCard(_ suggestion: AIGoalBuilderService.Suggestion) -> some View {
        let isApplied = selectedPresetName == suggestion.title

        return VStack(spacing: 10) {
            HStack {
                Text(suggestion.title.uppercased())
                    .font(theme.font(12, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("$\(Int(suggestion.suggestedAmount))")
                    .font(theme.font(14, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }

            Text(suggestion.rationale)
                .font(theme.font(11, weight: .light))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: applySuggestion) {
                HStack(spacing: 6) {
                    Image(systemName: isApplied ? "checkmark.circle.fill" : "arrow.turn.right.down")
                    Text(isApplied ? "APPLIED" : "USE THIS GOAL")
                }
                .font(theme.font(10, weight: .bold))
                .tracking(1.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isApplied ? theme.hairline : theme.accent.opacity(0.15))
                .foregroundColor(isApplied ? theme.accent : theme.textPrimary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(theme.accent.opacity(isApplied ? 0.5 : 0.2), lineWidth: 1))
            }
        }
        .padding(14)
        .background(theme.isLight ? Color.black.opacity(0.05) : Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
