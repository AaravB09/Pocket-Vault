import SwiftUI

/// Calls YOUR backend proxy (never Google directly) to generate a
/// tailored savings plan via Gemini. The caller's Supabase JWT, not a
/// reusable app secret, authorizes this request.
public enum SavingsCoachService {
    static let proxyURL = URL(string: "https://hbbyrgmckacgbqqtteaq.supabase.co/functions/v1/coach")!

    struct PlanRequest {
        let goalTitle: String
        let targetAmount: Double
        let currentSavings: Double
        let targetDate: Date
        let currentStreak: Int
    }

    static func generatePlan(_ request: PlanRequest, accessToken: String) async throws -> String {
        let remaining = max(request.targetAmount - request.currentSavings, 0)
        let days = max(Calendar.current.dateComponents([Calendar.Component.day], from: Date(), to: request.targetDate).day ?? 30, 1)
        let formatter = DateFormatter()
        formatter.dateStyle = DateFormatter.Style.medium

        let prompt = """
        You are a warm, encouraging savings coach inside a budgeting app called Pocket Vault.
        The user is saving toward: \(request.goalTitle)
        Target amount: $\(Int(request.targetAmount))
        Already saved: $\(Int(request.currentSavings))
        Remaining: $\(Int(remaining))
        Target date: \(formatter.string(from: request.targetDate)) (\(days) days from today)
        Current deposit streak: \(request.currentStreak) days

        Write a short, specific, encouraging savings plan (150-220 words) that:
        1. States the required weekly savings rate to hit the goal by the target date
        2. Suggests 2-3 concrete, realistic ways to find that money (no generic "cut coffee" cliches)
        3. Ends with one motivating line tied to the specific goal

        Plain text only, no markdown headers, no bullet symbols — short paragraphs.
        """

        var apiRequest = URLRequest(url: proxyURL)
        apiRequest.httpMethod = "POST"
        apiRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        apiRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["prompt": prompt, "max_tokens": 500]
        apiRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: apiRequest)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let raw = String(data: data, encoding: String.Encoding.utf8) ?? "unknown error"
            throw NSError(domain: "SavingsCoach", code: 1, userInfo: [NSLocalizedDescriptionKey: "API error: \(raw)"])
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else {
            throw NSError(domain: "SavingsCoach", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't parse response"])
        }

        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

public struct SavingsCoachView: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var authManager: AuthManager

    let goalTitle: String
    let targetAmount: Double
    let currentSavings: Double
    @Binding var chatMessages: [ChatMessage]
    @Binding var selectedTab: Int

    @State private var targetDate: Date
    @State private var plan: String?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    init(goalTitle: String, targetAmount: Double, currentSavings: Double, goalTargetDate: Date, chatMessages: Binding<[ChatMessage]>, selectedTab: Binding<Int>) {
        self.goalTitle = goalTitle
        self.targetAmount = targetAmount
        self.currentSavings = currentSavings
        _targetDate = State(initialValue: goalTargetDate)
        _chatMessages = chatMessages
        _selectedTab = selectedTab
    }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 26.0) {
                    HStack {
                        Spacer()
                        // Not a VaultButton: icon-only circular dismiss control,
                        // same shape family as HeaderIconButton in
                        // Thememanager.swift — not a CTA.
                        Button(action: { dismiss() }) {
                            Image.platformSymbol("xmark.circle.fill", android: "xmark")
                                .font(theme.font(22, weight: Font.Weight.bold))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .padding(Edge.Set.horizontal, 20.0)
                    .padding(Edge.Set.top, 20.0)

                    VStack(spacing: 4.0) {
                        Text("SAVINGS COACH")
                            .font(theme.font(10, weight: Font.Weight.bold))
                            .tracking(3)
                            .foregroundStyle(theme.accent)
                        Text("Welcome to Pro")
                            .font(theme.font(22, weight: Font.Weight.light))
                            .foregroundStyle(theme.textPrimary)
                    }

                    if plan == nil {
                        VStack(spacing: 18.0) {
                            Text("Tell me when you want to hit your goal and I'll build a tailored plan to get you there.")
                                .font(theme.font(13, weight: Font.Weight.light))
                                .foregroundStyle(theme.textSecondary)
                                .multilineTextAlignment(TextAlignment.center)
                                .padding(Edge.Set.horizontal, 30.0)

                            // Fix: Explicitly typing `DatePickerComponents.date`
                            DatePicker("Target date", selection: $targetDate, in: Date()...Date.distantFuture, displayedComponents: DatePickerComponents.date)
                                #if !SKIP
                                .datePickerStyle(CompactDatePickerStyle())
                                #endif
                                .tint(theme.accent)
                                .colorScheme(theme.isLight ? ColorScheme.light : ColorScheme.dark)
                                .padding(16.0)
                                // NOTE(skip): `.ultraThinMaterial` and `.clipShape`
                                // aren't resolved by Skip's SwiftUI shim — iOS keeps
                                // the real material + shape clip, Android gets a
                                // plain tinted background + `.cornerRadius`, same
                                // pattern used everywhere else in the app.
                                #if !SKIP
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16.0))
                                #else
                                .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                                .cornerRadius(16)
                                #endif
                                .padding(Edge.Set.horizontal, 24.0)

                            // MIGRATED: ad hoc Capsule CTA → VaultButton.
                            // This button pre-dates VaultButton and had drifted
                            // from the app's own conventions in three ways at
                            // once: a Capsule/pill shape instead of the shared
                            // squircle, an all-caps tracked label (see
                            // Thememanager.swift's "sentence case, not all-caps
                            // tracked text" comment on the shared CTA states),
                            // and a colored accent-glow shadow instead of the
                            // shared neutral one. `.primary` already handles the
                            // loading spinner (tinted to onAccent) and the
                            // disabled state, so isLoading/disabled/action carry
                            // straight over — the label stays static ("Generate
                            // my plan") rather than swapping text while loading,
                            // matching how every other VaultButton in the app
                            // handles isLoading (fade to a spinner in place,
                            // not a text change).
                            VaultButton(
                                "Generate my plan",
                                variant: .primary,
                                isLoading: isLoading,
                                horizontalPadding: 0.0,
                                action: { Task { await requestPlan() } }
                            )
                            .disabled(isLoading)
                            .padding(Edge.Set.horizontal, 30.0)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(theme.font(11))
                                    .foregroundStyle(theme.danger.opacity(0.9))
                                    .multilineTextAlignment(TextAlignment.center)
                                    .padding(Edge.Set.horizontal, 30.0)
                            }
                        }
                    } else {
                        planCard
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .themedSurface(ignoresSafeArea: true)
    }

    private var planCard: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 16.0) {
            HStack(spacing: 8.0) {
                Image.platformSymbol("sparkles", android: "star.fill")
                    .foregroundStyle(theme.accent)
                Text("YOUR TAILORED PLAN")
                    .font(theme.font(10, weight: Font.Weight.bold))
                    .tracking(2)
                    .foregroundStyle(theme.accent)
            }

            Text(plan ?? "")
                .font(theme.font(14, weight: Font.Weight.light))
                .foregroundStyle(theme.textPrimary.opacity(0.85))
                .lineSpacing(6)

            // Not converted to VaultButton: its inverted fill (theme.textPrimary
            // background / theme.background text) doesn't correspond to any
            // existing VaultButtonVariant — every variant is accent/danger/
            // onAccent-based, none render as a plain textPrimary-on-background
            // swap, and bending a variant's meaning to fit one screen felt
            // worse than leaving this hand-rolled. It has no loading/disabled
            // state to map anyway. Per the shape-consistency pass, though, its
            // shape/sizing/casing still needed to match the rest of the app:
            // Capsule → the shared squircle (Layout.controlRadius, .continuous),
            // fixed Layout.height instead of vertical padding, and the all-caps
            // tracked label → sentence case (see Thememanager.swift's "sentence
            // case, not all-caps tracked text" comment on the shared CTAs).
            Button(action: {
                dismiss()
                selectedTab = 4 // jump to Ask AI, where the plan now lives
            }) {
                Text("Start saving")
                    .font(theme.font(15, weight: Font.Weight.semibold))
                    .frame(maxWidth: CGFloat.infinity)
                    .frame(height: Layout.height)
                    .background(theme.textPrimary)
                    .foregroundColor(theme.background)
                    #if !SKIP
                    .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: RoundedCornerStyle.continuous))
                    #else
                    .cornerRadius(Layout.controlRadius)
                    #endif
            }
            .padding(Edge.Set.top, 8.0)
        }
        .padding(20.0)
        #if !SKIP
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20.0))
        #else
        .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
        .cornerRadius(20)
        #endif
        .overlay(RoundedRectangle(cornerRadius: 20.0).stroke(Color.clear, lineWidth: 1.0))
        .padding(Edge.Set.horizontal, 24.0)
    }

    private func requestPlan() async {
        guard let accessToken = authManager.accessToken else {
            errorMessage = "Create an account to use AI coaching."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let request = SavingsCoachService.PlanRequest(
                goalTitle: goalTitle.isEmpty ? "your goal" : goalTitle,
                targetAmount: targetAmount,
                currentSavings: currentSavings,
                targetDate: targetDate,
                currentStreak: streakManager.currentStreak
            )
            let result = try await SavingsCoachService.generatePlan(request, accessToken: accessToken)
            plan = result
            chatMessages.append(ChatMessage(role: .model, text: result))
        } catch {
            errorMessage = "Couldn't generate a plan right now. Check your proxy endpoint is set in SavingsCoachService."
        }
        isLoading = false
    }
}