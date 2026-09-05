import SwiftUI

/// In-app feedback form, styled to match the rest of Pocket Vault, so
/// testers never leave the app or drop into an external browser/Mail
/// app just to send a thought.
public struct FeedbackView: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    @EnvironmentObject var theme: ThemeManager
    @StateObject private var feedbackManager = FeedbackManager()

    @State private var message: String = ""
    @FocusState private var isFocused: Bool

    private var isValid: Bool {
        !message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        ZStack {
            if feedbackManager.didSubmitSuccessfully {
                confirmationState
            } else {
                formState
            }
        }
        // FIX: Replaced `theme` with `ignoresSafeArea: true` to resolve the compiler error
        .themedSurface(ignoresSafeArea: true)
    }

    private var formState: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image.platformSymbol("xmark.circle.fill", android: "xmark")
                            .font(theme.font(22, weight: Font.Weight.bold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(Edge.Set.horizontal, Layout.pageMargin)
                .padding(Edge.Set.top, 20)

                VStack(spacing: 6) {
                    SectionLabel("We're listening")
                    Text("Send Feedback")
                        .font(theme.font(22, weight: Font.Weight.light))
                        .foregroundStyle(theme.textPrimary)
                }

                Text("Bugs, ideas, anything at all — it goes straight to the team.")
                    .font(theme.font(13, weight: Font.Weight.light))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(TextAlignment.center)
                    .padding(Edge.Set.horizontal, Layout.pageMargin)

                VStack(alignment: HorizontalAlignment.leading, spacing: 8) {
                    SectionLabel("Your message")

                    TextEditor(text: $message)
                        .focused($isFocused)
                        .scrollContentBackground(Visibility.hidden)
                        .foregroundStyle(theme.textPrimary)
                        .font(theme.font(14, weight: Font.Weight.light))
                        .frame(height: 160)
                        .padding(12)
                        // NOTE(skip): .ultraThinMaterial has no Android
                        // equivalent — was cascading into the .clipShape
                        // right below it.
                        .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))
                        .overlay(alignment: Alignment.topLeading) {
                            if message.isEmpty {
                                Text("What's on your mind?")
                                    .font(theme.font(14, weight: Font.Weight.light))
                                    .foregroundStyle(theme.textTertiary)
                                    .padding(Edge.Set.horizontal, 18)
                                    .padding(Edge.Set.vertical, 20)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .padding(Edge.Set.horizontal, Layout.pageMargin)

                if let errorMessage = feedbackManager.errorMessage {
                    Text(errorMessage)
                        .font(theme.font(11))
                        .foregroundStyle(theme.danger.opacity(0.9))
                        .multilineTextAlignment(TextAlignment.center)
                        .padding(Edge.Set.horizontal, Layout.pageMargin)
                }

                // FIX: `.buttonStyle(.primaryCTA(theme))` referenced a
                // custom ButtonStyle static member that no longer exists —
                // same leftover migration gap as every other screen (see
                // PrimaryCTAButton's doc comment in ThemeManager.swift for
                // why custom ButtonStyle conformance was dropped app-wide).
                // Use the wrapper directly instead of a Button + buttonStyle
                // pair.
                PrimaryCTAButton(accent: theme.accent, onAccent: theme.onAccent, action: {
                    isFocused = false
                    Task {
                        await feedbackManager.submit(
                            message: message,
                            userID: authManager.userID ?? leaderboardManager.myUserID,
                            displayName: leaderboardManager.myDisplayName
                        )
                    }
                }) {
                    HStack {
                        if feedbackManager.isSubmitting { ProgressView().tint(theme.onAccent) }
                        Text(feedbackManager.isSubmitting ? "Sending…" : "Send feedback")
                    }
                }
                .disabled(!isValid || feedbackManager.isSubmitting)
                .padding(Edge.Set.horizontal, Layout.pageMargin)

                Spacer(minLength: 40)
            }
        }
    }

    private var confirmationState: some View {
        VStack(spacing: 20) {
            Image.platformSymbol("checkmark.seal.fill", android: "checkmark.circle.fill")
                .font(theme.font(40, weight: Font.Weight.light))
                .foregroundStyle(theme.accent)

            VStack(spacing: 6) {
                SectionLabel("Thank you")
                Text("Feedback sent")
                    .font(theme.font(20, weight: Font.Weight.light))
                    .foregroundStyle(theme.textPrimary)
            }

            Text("We read every message — appreciate you taking the time.")
                .font(theme.font(13, weight: Font.Weight.light))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(TextAlignment.center)
                .padding(Edge.Set.horizontal, 40)

            // FIX: same leftover-ButtonStyle pattern as above, using the
            // secondary variant. SecondaryCTAButton has no onAccent
            // parameter — its own text color is `accent` — so nothing
            // else needs to change here since this label has no tint call
            // to fix up.
            SecondaryCTAButton(accent: theme.accent, action: { dismiss() }) {
                Text("Done")
            }
            .padding(Edge.Set.horizontal, 40)
            .padding(Edge.Set.top, 8)
        }
    }
}
