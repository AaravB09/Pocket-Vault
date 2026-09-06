import SwiftUI

public struct ChatMessage: Identifiable, Equatable, Sendable {
    public let id = UUID()
    let role: Role
    let text: String

    enum Role: String { case user, model }
}

/// Multi-turn chat against the same authenticated Supabase proxy the
/// Savings Coach uses.
public enum AIChatService {
    static func send(
        history: [ChatMessage],
        goalTitle: String,
        targetGoal: Double,
        currentSavings: Double,
        targetDate: Date,
        accessToken: String
    ) async throws -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = DateFormatter.Style.medium

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
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["contents": contents])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let raw = String(data: data, encoding: String.Encoding.utf8) ?? "unknown error"
            // DEBUG: print raw HTTP response so we can see the exact status + body
            // from the function (not just the wrapped error message)
            print("[askAIDebug] HTTP status=\((response as? HTTPURLResponse)?.statusCode ?? -1) body=\(raw) tokenPresent=\(!accessToken.isEmpty)")
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
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

public struct AIChatView: View {
    @EnvironmentObject var entitlementManager: EntitlementManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var authManager: AuthManager
    @Binding var selectedTab: Int
    @Binding var messages: [ChatMessage]

    let goalTitle: String
    let targetGoal: Double
    let currentSavings: Double
    let targetDate: Date

    @State private var draft: String = ""
    @State private var isSending: Bool = false
    @State private var errorMessage: String?
    // FIX ("really weird" tapping VIEW PRO PLANS with no Pro plan): this
    // button used to do `selectedTab = 5`, which swapped CustomPaywallView
    // straight into the tab `switch` in MainTabView — not presented as a
    // sheet. CustomPaywallView's "Close" button calls `@Environment(\.dismiss)`,
    // which only does anything inside an actual presentation (a `.sheet`/
    // `.fullScreenCover`); swapped in as bare tab content, there was no
    // presentation to dismiss, so Close silently did nothing and the only
    // way out was tapping a bottom-bar icon — reading as a stuck, broken
    // screen. Every other Pro upsell in the app (ContentView's Pro badge)
    // already presents this exact same view as a real `.sheet`, which
    // Close correctly dismisses — matching that convention here fixes it.
    @State private var showPaywall: Bool = false

    public var body: some View {
        ZStack {
            if !entitlementManager.isPro {
                lockedState
            } else {
                chatContent
            }
        }
        // FIX (Android "white bars above/below the locked card"): this ZStack
        // only hugs the size of whichever branch is showing — on iOS that's
        // moot because the enclosing tab/navigation context already stretches
        // it full-screen, but Skip doesn't do that implicitly on Android, so
        // `.themedSurface(ignoresSafeArea:)` below was only painting
        // `theme.background` behind the card's own (much smaller) bounds.
        // Whatever's behind that — the system window background — showed
        // through as plain white above and below it. Forcing this to fill
        // all available space first means the theme background (and the
        // card centered within it) now covers the entire screen, matching iOS.
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
        // FIX: Replaced `theme` with the required boolean argument label
        .themedSurface(ignoresSafeArea: true)
        .sheet(isPresented: $showPaywall) {
            CustomPaywallView(
                goalTitle: goalTitle,
                targetGoal: targetGoal,
                currentSavings: currentSavings,
                chatMessages: $messages,
                selectedTab: $selectedTab
            )
        }
    }

    private var lockedState: some View {
        ZStack(alignment: Alignment.topTrailing) {
            VStack(spacing: 18) {
                // FIX (Android "weird, landscape-looking" locked screen):
                // this was a raw `Image(systemName: "lock.fill")`, not routed
                // through `platformSymbol` like every other icon on this
                // screen. "lock.fill" isn't in Skip's fallback-symbol table
                // (only the unfilled "lock" is documented as supported), so
                // Skip was silently substituting its generic "symbol not
                // found" warning-triangle glyph in its place — see the note
                // on `Image.platformSymbol` in Platformsymbol.swift.
                Image.platformSymbol("lock.fill", android: "lock")
                    .font(theme.font(34, weight: Font.Weight.bold))
                    .foregroundStyle(theme.accent)
                // No foregroundStyle set — defaults to .primary, resolved to
                // theme.textPrimary by themedSurface(_:) above.
                Text("ASK AI IS A PRO FEATURE")
                    .font(theme.font(12, weight: Font.Weight.bold))
                    .tracking(2.2)
                // FIX (Android "description line missing from the locked
                // card"): `.foregroundStyle(.secondary)` relies on the
                // screen's `.themedSurface(ignoresSafeArea:)` ancestor to
                // resolve it, the way real SwiftUI's hierarchical
                // foregroundStyle would on iOS. Skip only implements the
                // single-argument form of that call (see the note in
                // ThemedSurfaceModifier), which only covers the default/
                // primary text color on Android — so this Text fell back to
                // a raw platform default instead of the theme, invisible
                // against this card's dark background. Referencing the
                // theme token directly fixes it, matching the title Text
                // right above (which is visible because it uses the
                // covered default/primary color).
                Text("Chat with your savings assistant anytime — ask about pacing, trade-offs, or ways to hit your goal faster.")
                    .font(theme.font(13, weight: Font.Weight.regular))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(TextAlignment.center)
                    .padding(Edge.Set.horizontal, 30)

                Button(action: { showPaywall = true }) {
                    Text("VIEW PRO PLANS")
                        .font(theme.font(12, weight: Font.Weight.bold))
                        .tracking(2.4)
                        .padding(Edge.Set.horizontal, 26)
                        .padding(Edge.Set.vertical, 15)
                        .background(theme.accent)
                        .foregroundColor(theme.onAccent)
                        .clipShape(Capsule())
                        .shadow(color: theme.accent.opacity(0.4), radius: 14, y: 6)
                }
                .padding(Edge.Set.top, 8)
            }
            .padding(20)
            // FIX (matches the video of the real iOS build): this whole
            // VStack had no card treatment at all — just plain content
            // sitting on the screen's flat background — which is what was
            // actually reading as "weird/landscape" on Android next to a
            // screen that, everywhere else in the app, wraps this kind of
            // content in a bounded card. The card look itself (dark
            // elevated surface, rounded corners, hairline stroke) isn't
            // new to this screen — it's the exact same pattern already
            // used for the tailored-plan card in Savingscoachview.swift
            // and the feature-list card in PaywallView.swift, just never
            // applied here. Reusing it verbatim (including the existing
            // iOS-blur / Android-flat-overlay split those two already use)
            // is what makes this render identically to the rest of the
            // app on both platforms, not just visually similar.
            #if !SKIP
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            #else
            .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
            .cornerRadius(20)
            #endif
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1))
            .padding(Edge.Set.horizontal, 24)

            // FIX: this locked state is shown directly as tab content (case 4
            // in MainTabView's switch), not presented as a sheet, so there
            // was previously no way to leave it besides tapping a different
            // bottom-bar icon. Adding an explicit close button that hops back
            // to the Vault tab, same on both platforms.
            // FIX (Android "close button is a caution triangle"): this
            // mapped `android:` to the same unsupported "xmark.circle.fill"
            // name that was causing the fallback in the first place — Skip's
            // fallback table doesn't include it (see Platformsymbol.swift),
            // so it rendered as the "symbol not found" warning triangle
            // instead of a close icon. Every other close button in the app
            // (Profileview, Loginview, Sharedbudgetview, LeaderboardView,
            // Budgettrackerview, Savingscoachview, Feedbackview) already
            // substitutes the supported "xmark" glyph on Android — matching
            // that here fixes it.
            Button(action: { selectedTab = 0 }) {
                Image.platformSymbol("xmark.circle.fill", android: "xmark")
                    .font(theme.font(22, weight: Font.Weight.semibold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(Edge.Set.top, 16)
            .padding(Edge.Set.trailing, 40)
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image.platformSymbol("sparkles", android: "star.fill").foregroundStyle(theme.accent)
                Text("ASK AI").font(theme.font(10, weight: Font.Weight.bold)).tracking(3).foregroundStyle(theme.accent)
            }
            .padding(Edge.Set.top, 90) // Increased top padding to push content lower
            .padding(Edge.Set.bottom, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: HorizontalAlignment.leading, spacing: 14) {
                        if messages.isEmpty {
                            Text("Ask me anything about your savings — \u{201C}Am I on pace?\u{201D}, \u{201C}How do I save faster?\u{201D}, \u{201C}What if I skip a week?\u{201D}")
                                .font(theme.font(13, weight: Font.Weight.light))
                                .foregroundStyle(Color.gray.opacity(0.5))
                                .padding(Edge.Set.horizontal, 24)
                                .padding(Edge.Set.top, 24) // Added extra top padding to push initial prompt bubble lower
                        }
                        ForEach(messages) { message in
                            bubble(for: message).id(message.id)
                        }
                        if isSending {
                            HStack {
                                ProgressView().tint(theme.accent)
                                Text("Thinking…").font(theme.font(12)).foregroundStyle(Color.gray.opacity(0.5))
                            }
                            .padding(Edge.Set.horizontal, 24)
                        }
                    }
                    .padding(Edge.Set.vertical, 12)
                }
                .onChange(of: messages) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: UnitPoint.bottom) }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(theme.font(11))
                    .foregroundStyle(theme.danger.opacity(0.9))
                    .padding(Edge.Set.horizontal, 24)
            }

            if !networkMonitor.isOnline {
                Text("Ask AI needs a connection — your goal data is still all here, just can't chat about it right now.")
                    .font(theme.font(11))
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .multilineTextAlignment(TextAlignment.center)
                    .padding(Edge.Set.horizontal, 24)
            }

            HStack(spacing: 10) {
                TextField("Ask a question…", text: $draft, axis: Axis.vertical)
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
                    Image.platformSymbol("arrow.up.circle.fill", android: "paperplane.fill")
                        .font(theme.font(30))
                        // Image doesn't participate in the .primary/.secondary/
                        // .tertiary "free default" the way Text does, so this
                        // one keeps an explicit color — theme.textTertiary
                        // rather than .tertiary, since a conditional value
                        // like this reads clearer as the concrete token.
                        .foregroundStyle(draft.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty ? theme.textTertiary : theme.accent)
                }
                .disabled(draft.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty || isSending || !networkMonitor.isOnline)
            }
            .padding(Edge.Set.horizontal, 16)
            .padding(Edge.Set.top, 8)
            .padding(Edge.Set.bottom, 100)
        }
    }

    private func bubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(theme.font(14, weight: Font.Weight.light))
                .foregroundStyle(message.role == .user ? theme.onAccent : theme.textPrimary.opacity(0.9))
                .padding(12)
                .background(message.role == .user ? theme.accent : (theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if message.role == .model { Spacer(minLength: 40) }
        }
        .padding(Edge.Set.horizontal, 16)
    }

    @MainActor
    private func send() async {
        let text = draft.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let accessToken = authManager.accessToken else {
            errorMessage = "Create an account to use Ask AI."
            return
        }
        draft = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, text: text))
        isSending = true
        let historySnapshot = messages
        do {
            let reply = try await AIChatService.send(
                history: historySnapshot,
                goalTitle: goalTitle,
                targetGoal: targetGoal,
                currentSavings: currentSavings,
                targetDate: targetDate,
                accessToken: accessToken
            )
            messages.append(ChatMessage(role: .model, text: reply))
        } catch {
            // DEBUG: surface the actual error so we can see whether it's auth/quota/key/parse/network.
            errorMessage = "Couldn't reach the assistant. \(error.localizedDescription)"
        }
        isSending = false
    }
}
