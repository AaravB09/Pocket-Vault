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
                .padding(.horizontal, 20)
                .padding(.top, 20)

                VStack(spacing: 4) {
                    Text("WE'RE LISTENING")
                        .font(theme.font(10, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(theme.accent)
                    Text("Send Feedback")
                        .font(theme.font(22, weight: .light))
                        .foregroundStyle(theme.textPrimary)
                }

                Text("Bugs, ideas, anything at all — it goes straight to the team.")
                    .font(theme.font(13, weight: .light))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR MESSAGE")
                        .font(theme.font(9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(theme.textTertiary)

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
                .padding(.horizontal, 24)

                if let errorMessage = feedbackManager.errorMessage {
                    Text(errorMessage)
                        .font(theme.font(11))
                        .foregroundStyle(theme.danger.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
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
                        Text(feedbackManager.isSubmitting ? "SENDING…" : "SEND FEEDBACK")
                            .font(theme.font(13, weight: .bold))
                            .tracking(2.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(isValid ? theme.accent : theme.accent.opacity(0.25))
                    .foregroundColor(theme.onAccent)
                    .clipShape(Capsule())
                    .shadow(color: theme.accent.opacity(isValid ? 0.4 : 0), radius: 16, y: 8)
                }
                .disabled(!isValid || feedbackManager.isSubmitting)
                .padding(.horizontal, 30)

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
                Text("THANK YOU")
                    .font(theme.font(10, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(theme.accent)
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
                Text("DONE")
                    .font(theme.font(11, weight: .bold))
                    .tracking(2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(theme.textPrimary)
                    .foregroundColor(theme.background)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
    }
}
