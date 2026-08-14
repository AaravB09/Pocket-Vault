import SwiftUI

/// Calls YOUR backend proxy (never Google directly) to generate a
/// tailored savings plan via Gemini. See SECURITY_NOTES.txt for the proxy
/// you need to deploy first — this file intentionally contains no Gemini key.
enum SavingsCoachService {
    static let proxyURL = URL(string: "https://hbbyrgmckacgbqqtteaq.supabase.co/functions/v1/coach")!
    // Pulled from Secrets.swift, which is gitignored — see Secrets.example.swift
    // for the template and SETUP_NOTES.md for how to fill it in locally.
    static let appSharedSecret = Secrets.appSharedSecret

    struct PlanRequest {
        let goalTitle: String
        let targetAmount: Double
        let currentSavings: Double
        let targetDate: Date
        let currentStreak: Int
    }

    static func generatePlan(_ request: PlanRequest) async throws -> String {
        let remaining = max(request.targetAmount - request.currentSavings, 0)
        let days = max(Calendar.current.dateComponents([.day], from: Date(), to: request.targetDate).day ?? 30, 1)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

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
        apiRequest.setValue(appSharedSecret, forHTTPHeaderField: "x-app-secret")

        let body: [String: Any] = ["prompt": prompt, "max_tokens": 500]
        apiRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: apiRequest)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? "unknown error"
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

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SavingsCoachView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var theme: ThemeManager

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

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 26) {
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(theme.font(22, weight: .bold))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    VStack(spacing: 4) {
                        Text("SAVINGS COACH")
                            .font(theme.font(10, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(theme.accent)
                        Text("Welcome to Pro")
                            .font(theme.font(22, weight: .light))
                            .foregroundStyle(theme.textPrimary)
                    }

                    if plan == nil {
                        VStack(spacing: 18) {
                            Text("Tell me when you want to hit your goal and I'll build a tailored plan to get you there.")
                                .font(theme.font(13, weight: .light))
                                .foregroundStyle(theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)

                            DatePicker("Target date", selection: $targetDate, in: Date()..., displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .tint(theme.accent)
                                .colorScheme(theme.isLight ? .light : .dark)
                                .padding(16)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 24)

                            Button(action: { Task { await requestPlan() } }) {
                                HStack {
                                    if isLoading { ProgressView().tint(theme.onAccent) }
                                    Text(isLoading ? "BUILDING YOUR PLAN…" : "GENERATE MY PLAN")
                                        .font(theme.font(13, weight: .bold))
                                        .tracking(2.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 19)
                                .background(theme.accent)
                                .foregroundColor(theme.onAccent)
                                .clipShape(Capsule())
                                .shadow(color: theme.accent.opacity(0.5), radius: 18, y: 8)
                            }
                            .disabled(isLoading)
                            .padding(.horizontal, 30)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(theme.font(11))
                                    .foregroundStyle(theme.danger.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 30)
                            }
                        }
                    } else {
                        planCard
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .themedSurface(theme)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.accent)
                Text("YOUR TAILORED PLAN")
                    .font(theme.font(10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(theme.accent)
            }

            Text(plan ?? "")
                .font(theme.font(14, weight: .light))
                .foregroundStyle(theme.textPrimary.opacity(0.85))
                .lineSpacing(6)

            Button(action: {
                dismiss()
                selectedTab = 4 // jump to Ask AI, where the plan now lives
            }) {
                Text("START SAVING")
                    .font(theme.font(11, weight: .bold))
                    .tracking(2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(theme.textPrimary)
                    .foregroundColor(theme.background)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1))
        .padding(.horizontal, 24)
    }

    private func requestPlan() async {
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
            let result = try await SavingsCoachService.generatePlan(request)
            plan = result
            chatMessages.append(ChatMessage(role: .model, text: result))
        } catch {
            errorMessage = "Couldn't generate a plan right now. Check your proxy endpoint is set in SavingsCoachService."
        }
        isLoading = false
    }
}
