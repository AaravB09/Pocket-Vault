import SwiftUI

/// Shown when someone taps the "reset your password" link from their
/// email. Previously the app had no screen for this at all — the link
/// just quietly signed the person in without ever asking for a new
/// password. This is the missing step: it uses the one-time recovery
/// token AuthManager captured from the link to actually set a new
/// password, then signs the person in.
struct NewPasswordView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) var dismiss

    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorText: String?

    private struct PasswordRequirement: Identifiable {
        let id = UUID()
        let label: String
        let isMet: (String) -> Bool
    }

    private let requirements: [PasswordRequirement] = [
        PasswordRequirement(label: "At least 6 characters", isMet: { $0.count >= 6 }),
        PasswordRequirement(label: "One uppercase letter", isMet: { $0.contains(where: { $0.isUppercase }) }),
        PasswordRequirement(label: "One number", isMet: { $0.contains(where: { $0.isNumber }) })
    ]

    private var isValid: Bool {
        requirements.allSatisfy { $0.isMet(newPassword) } && newPassword == confirmPassword
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text("POCKET VAULT")
                            .font(theme.font(11, weight: .bold))
                            .tracking(4)
                            .foregroundStyle(theme.accent)
                        Text("Choose a New Password")
                            .font(theme.font(22, weight: .light))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .padding(.top, 90)

                    if let email = authManager.userEmail {
                        Text("Resetting the password for \(email)")
                            .font(theme.font(12, weight: .light))
                            .foregroundStyle(theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }

                    VStack(spacing: 14) {
                        ZStack(alignment: .trailing) {
                            Group {
                                if isPasswordVisible {
                                    TextField("", text: $newPassword, prompt: Text("New password").foregroundColor(theme.textTertiary))
                                } else {
                                    SecureField("", text: $newPassword, prompt: Text("New password").foregroundColor(theme.textTertiary))
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(theme.textPrimary)
                            .tint(theme.accent)
                            .padding(16)
                            .padding(.trailing, 40)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))

                            Button(action: { isPasswordVisible.toggle() }) {
                                Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                    .font(theme.font(14))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .padding(.trailing, 16)
                        }

                        SecureField("", text: $confirmPassword, prompt: Text("Confirm new password").foregroundColor(theme.textTertiary))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(theme.textPrimary)
                            .tint(theme.accent)
                            .padding(16)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(requirements) { requirement in
                                let met = requirement.isMet(newPassword)
                                HStack(spacing: 8) {
                                    Image(systemName: met ? "checkmark.circle.fill" : "circle")
                                        .font(theme.font(13))
                                        .foregroundStyle(met ? theme.accent : theme.textTertiary)
                                    Text(requirement.label)
                                        .font(theme.font(12, weight: .light))
                                        .foregroundStyle(met ? theme.textPrimary.opacity(0.8) : theme.textTertiary)
                                }
                            }
                            if !confirmPassword.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: newPassword == confirmPassword ? "checkmark.circle.fill" : "circle")
                                        .font(theme.font(13))
                                        .foregroundStyle(newPassword == confirmPassword ? theme.accent : theme.textTertiary)
                                    Text("Passwords match")
                                        .font(theme.font(12, weight: .light))
                                        .foregroundStyle(newPassword == confirmPassword ? theme.textPrimary.opacity(0.8) : theme.textTertiary)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 30)

                    if let errorText {
                        Text(errorText)
                            .font(theme.font(12, weight: .light))
                            .foregroundStyle(theme.danger.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }

                    Button(action: save) {
                        HStack {
                            if isSaving { ProgressView().tint(theme.background) }
                            Text(isSaving ? "SAVING…" : "SAVE NEW PASSWORD")
                                .font(theme.font(13, weight: .bold))
                                .tracking(2.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(isValid ? theme.textPrimary : theme.textPrimary.opacity(0.25))
                        .foregroundColor(theme.background)
                        .clipShape(Capsule())
                        .shadow(color: theme.textPrimary.opacity(isValid ? 0.25 : 0), radius: 16, y: 8)
                    }
                    .disabled(!isValid || isSaving)
                    .padding(.horizontal, 30)

                    Spacer(minLength: 40)
                }
            }
        }
        .themedSurface(theme)
        .interactiveDismissDisabled(true)
    }

    private func save() {
        isSaving = true
        errorText = nil
        Task {
            do {
                try await authManager.completePasswordReset(newPassword: newPassword)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            isSaving = false
        }
    }
}
