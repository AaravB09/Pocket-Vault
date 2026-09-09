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
            VStack(spacing: 24.0) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image.platformSymbol("xmark.circle.fill", android: "xmark")
                            .font(theme.font(22, weight: Font.Weight.bold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    #if !SKIP
                    .buttonStyle(PlainButtonStyle())
                    #endif
                }
                .padding(Edge.Set.horizontal, Layout.pageMargin)
                .padding(Edge.Set.top, 20.0)

                VStack(spacing: 6.0) {
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

                VStack(alignment: HorizontalAlignment.leading, spacing: 8.0) {
                    SectionLabel("Your message")

                    TextEditor(text: $message)
                        .focused($isFocused)
                        .scrollContentBackground(Visibility.hidden)
                        .foregroundStyle(theme.textPrimary)
                        .font(theme.font(14, weight: Font.Weight.light))
                        .frame(height: 160.0)
                        .padding(12.0)
                        // NOTE(skip): .ultraThinMaterial has no Android
                        // equivalent — was cascading into the .clipShape
                        // right below it.
                        .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 14.0))
                        .overlay(RoundedRectangle(cornerRadius: 14.0).stroke(Color.clear, lineWidth: 1.0))
                        .overlay(alignment: Alignment.topLeading) {
                            if message.isEmpty {
                                Text("What's on your mind?")
                                    .font(theme.font(14, weight: Font.Weight.light))
                                    .foregroundStyle(theme.textTertiary)
                                    .padding(Edge.Set.horizontal, 18.0)
                                    .padding(Edge.Set.vertical, 20.0)
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

                // MIGRATED: PrimaryCTAButton (Thememanager.swift) → VaultButton.
                // VaultButton's isLoading already handles the spinner/label
                // swap and folds into isInteractive, so the separate
                // `|| feedbackManager.isSubmitting` disable clause is no
                // longer needed — only the validation guard stays external.
                VaultButton(
                    "Send feedback",
                    variant: .primary,
                    isLoading: feedbackManager.isSubmitting
                ) {
                    isFocused = false
                    Task {
                        await feedbackManager.submit(
                            message: message,
                            userID: authManager.userID ?? leaderboardManager.myUserID,
                            displayName: leaderboardManager.myDisplayName
                        )
                    }
                }
                .disabled(!isValid)
                .padding(Edge.Set.horizontal, Layout.pageMargin)

                Spacer(minLength: 40)
            }
        }
    }

    private var confirmationState: some View {
        VStack(spacing: 20.0) {
            Image.platformSymbol("checkmark.seal.fill", android: "checkmark.circle.fill")
                .font(theme.font(40, weight: Font.Weight.light))
                .foregroundStyle(theme.accent)

            VStack(spacing: 6.0) {
                SectionLabel("Thank you")
                Text("Feedback sent")
                    .font(theme.font(20, weight: Font.Weight.light))
                    .foregroundStyle(theme.textPrimary)
            }

            Text("We read every message — appreciate you taking the time.")
                .font(theme.font(13, weight: Font.Weight.light))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(TextAlignment.center)
                .padding(Edge.Set.horizontal, 40.0)

            // MIGRATED: SecondaryCTAButton (Thememanager.swift) → VaultButton.
            VaultButton("Done", variant: .secondary) {
                dismiss()
            }
            .padding(Edge.Set.horizontal, 40.0)
            .padding(Edge.Set.top, 8.0)
        }
    }
}
