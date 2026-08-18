import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let text: String

    enum Role: String { case user, model }
}

/// Multi-turn chat against the same Supabase proxy the Savings Coach uses.
/// Reuses SavingsCoachService's proxyURL/appSharedSecret so you only ever
/// have to update those values in one place.
enum AIChatService {
    static func send(
        history: [ChatMessage],
        goalTitle: String,
        targetGoal: Double,
        currentSavings: Double,
        targetDate: Date
    ) async throws -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let contextPrimer = """
        You are a friendly, concise financial savings assistant inside an app called Pocket Vault. \
        Answer the user's questions about budgeting, saving strategy, and their progress. Keep answers \
        under 120 words unless they explicitly ask for more detail. Their current goal: \
        \(goalTitle.isEmpty ? "not set" : goalTitle), target $\(Int(targetGoal)), saved so far \
        $\(Int(currentSavings)), target date \(formatter.string(from: targetDate)).
        """

        var contents: [[String: Any]] = [
            ["role": "user", "parts": [["text": contextPrimer]]],
            ["role": "model", "parts": [["text": "Got it — I'm ready to help with your savings plan. What's on your mind?"]]]
        ]
        for message in history {
            contents.append(["role": message.role.rawValue, "parts": [["text": message.text]]])
        }

        var request = URLRequest(url: SavingsCoachService.proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(SavingsCoachService.appSharedSecret, forHTTPHeaderField: "x-app-secret")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["contents": contents])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "AIChat", code: 1, userInfo: [NSLocalizedDescriptionKey: "API error: \(raw)"])
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else {
            throw NSError(domain: "AIChat", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't parse response"])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AIChatView: View {
    @EnvironmentObject var entitlementManager: EntitlementManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Binding var selectedTab: Int
    @Binding var messages: [ChatMessage]

    let goalTitle: String
    let targetGoal: Double
    let currentSavings: Double
    let targetDate: Date

    @State private var draft: String = ""
    @State private var isSending: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if !entitlementManager.isPro {
                lockedState
            } else {
                chatContent
            }
        }
        // FIX: Replaced `theme` with the required boolean argument label
        .themedSurface(ignoresSafeArea: true)
    }

    private var lockedState: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(theme.font(34, weight: .bold)).foregroundStyle(theme.accent)
            // No foregroundStyle set — defaults to .primary, resolved to
            // theme.textPrimary by themedSurface(_:) above.
            Text("ASK AI IS A PRO FEATURE")
                .font(theme.font(12, weight: .bold))
                .tracking(2.2)
            Text("Chat with your savings assistant anytime — ask about pacing, trade-offs, or ways to hit your goal faster.")
                .font(theme.font(13, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Button(action: { selectedTab = 5 }) {
                Text("VIEW PRO PLANS")
                    .font(theme.font(12, weight: .bold))
                    .tracking(2.4)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 15)
                    .background(theme.accent)
                    .foregroundColor(theme.onAccent)
                    .clipShape(Capsule())
                    .shadow(color: theme.accent.opacity(0.4), radius: 14, y: 6)
            }
            .padding(.top, 8)
        }
        .padding()
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(theme.accent)
                Text("ASK AI").font(theme.font(10, weight: .bold)).tracking(3).foregroundStyle(theme.accent)
            }
            .padding(.top, 90) // Increased top padding to push content lower
            .padding(.bottom, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty {
                            Text("Ask me anything about your savings — \u{201C}Am I on pace?\u{201D}, \u{201C}How do I save faster?\u{201D}, \u{201C}What if I skip a week?\u{201D}")
                                .font(theme.font(13, weight: .light))
                                .foregroundStyle(Color.gray.opacity(0.5))
                                .padding(.horizontal, 24)
                                .padding(.top, 24) // Added extra top padding to push initial prompt bubble lower
                        }
                        ForEach(messages) { message in
                            bubble(for: message).id(message.id)
                        }
                        if isSending {
                            HStack {
                                ProgressView().tint(theme.accent)
                                Text("Thinking…").font(theme.font(12)).foregroundStyle(Color.gray.opacity(0.5))
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: messages) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(theme.font(11))
                    .foregroundStyle(theme.danger.opacity(0.9))
                    .padding(.horizontal, 24)
            }

            if !networkMonitor.isOnline {
                Text("Ask AI needs a connection — your goal data is still all here, just can't chat about it right now.")
                    .font(theme.font(11))
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 10) {
                TextField("Ask a question…", text: $draft, axis: .vertical)
                    .padding(12)
                    #if !SKIP
                    .background(.ultraThinMaterial)
                    #else
                    .background(theme.background.opacity(0.8))
                    #endif
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    // No explicit color — defaults to .primary, resolved to
                    // theme.textPrimary by themedSurface(_:) on the screen root.
                    .disabled(!networkMonitor.isOnline)

                Button(action: { Task { await send() } }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(theme.font(30))
                        // Image doesn't participate in the .primary/.secondary/
                        // .tertiary "free default" the way Text does, so this
                        // one keeps an explicit color — theme.textTertiary
                        // rather than .tertiary, since a conditional value
                        // like this reads clearer as the concrete token.
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? theme.textTertiary : theme.accent)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isSending || !networkMonitor.isOnline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
    }

    private func bubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(theme.font(14, weight: .light))
                .foregroundStyle(message.role == .user ? theme.onAccent : theme.textPrimary.opacity(0.9))
                .padding(12)
                .background(message.role == .user ? theme.accent : (theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if message.role == .model { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 16)
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, text: text))
        isSending = true
        do {
            let reply = try await AIChatService.send(
                history: messages,
                goalTitle: goalTitle,
                targetGoal: targetGoal,
                currentSavings: currentSavings,
                targetDate: targetDate
            )
            messages.append(ChatMessage(role: .model, text: reply))
        } catch {
            errorMessage = "Couldn't reach the assistant. Check your proxy is deployed."
        }
        isSending = false
    }
}
