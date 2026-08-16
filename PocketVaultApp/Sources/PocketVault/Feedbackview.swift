import SwiftUI

/// In-app feedback form, styled to match the rest of Pocket Vault, so
/// testers never leave the app or drop into an external browser/Mail
/// app just to send a thought.
struct FeedbackView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    @EnvironmentObject var theme: ThemeManager
    @StateObject private var feedbackManager = FeedbackManager()

    @State private var message: String = ""
    @FocusState private var isFocused: Bool

    private var isValid: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            if feedbackManager.didSubmitSuccessfully {
                confirmationState
            } else {
                formState
            }
        }
        .themedSurface(theme)
    }

    private var formState: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(theme.font(22, weight: .bold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(.horizontal, Layout.pageMargin)
                .padding(.top, 20)

                VStack(spacing: 6) {
                    SectionLabel("We're listening")
                    Text("Send Feedback")
                        .font(theme.font(22, weight: .light))
                        .foregroundStyle(theme.textPrimary)
                }

                Text("Bugs, ideas, anything at all — it goes straight to the team.")
                    .font(theme.font(13, weight: .light))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Layout.pageMargin)

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Your message")

                    TextEditor(text: $message)
                        .focused($isFocused)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(theme.textPrimary)
                        .font(theme.font(14, weight: .light))
                        .frame(height: 160)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))
                        .overlay(alignment: .topLeading) {
                            if message.isEmpty {
                                Text("What's on your mind?")
                                    .font(theme.font(14, weight: .light))
                                    .foregroundStyle(theme.textTertiary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 20)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .padding(.horizontal, Layout.pageMargin)

                if let errorMessage = feedbackManager.errorMessage {
                    Text(errorMessage)
                        .font(theme.font(11))
                        .foregroundStyle(theme.danger.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Layout.pageMargin)
                }

                Button(action: {
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
                .buttonStyle(.primaryCTA(theme))
                .disabled(!isValid || feedbackManager.isSubmitting)
                .padding(.horizontal, Layout.pageMargin)

                Spacer(minLength: 40)
            }
        }
    }

    private var confirmationState: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(theme.font(40, weight: .light))
                .foregroundStyle(theme.accent)

            VStack(spacing: 6) {
                SectionLabel("Thank you")
                Text("Feedback sent")
                    .font(theme.font(20, weight: .light))
                    .foregroundStyle(theme.textPrimary)
            }

            Text("We read every message — appreciate you taking the time.")
                .font(theme.font(13, weight: .light))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { dismiss() }) {
                Text("Done")
            }
            .buttonStyle(.secondaryCTA(theme))
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
    }
}
