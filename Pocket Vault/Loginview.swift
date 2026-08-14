import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var theme: ThemeManager

    /// When true, the "Continue as Guest" escape hatch is hidden. Use this
    /// when LoginView is presented somewhere that specifically requires a
    /// real account — e.g. the paywall, which needs a guest to actually
    /// create an account before subscribing.
    var hideGuestOption: Bool = false

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSignUpMode: Bool = false
    @State private var awaitingEmailConfirmation: Bool = false
    @State private var isPasswordVisible: Bool = false
    @State private var showForgotPassword: Bool = false
    @State private var resetEmail: String = ""
    @State private var resetSentMessage: String?

    private var isValid: Bool {
        email.contains("@") && passwordRequirements.allSatisfy { $0.isMet(password) }
    }

    private struct PasswordRequirement: Identifiable {
        let id = UUID()
        let label: String
        let isMet: (String) -> Bool
    }

    private let passwordRequirements: [PasswordRequirement] = [
        PasswordRequirement(label: "At least 6 characters", isMet: { $0.count >= 6 }),
        PasswordRequirement(label: "One uppercase letter", isMet: { $0.contains(where: { $0.isUppercase }) }),
        PasswordRequirement(label: "One number", isMet: { $0.contains(where: { $0.isNumber }) })
    ]

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            RadialGradient(
                colors: [theme.textPrimary.opacity(0.08), .clear],
                center: .top, startRadius: 10, endRadius: 320
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 30) {
                    VStack(spacing: 8) {
                        Text("POCKET VAULT")
                            .font(theme.font(11, weight: .bold))
                            .tracking(4)
                            .foregroundStyle(theme.accent)
                        Text(isSignUpMode ? "Create Your Vault" : "Welcome Back")
                            .font(theme.font(26, weight: .light))
                            .foregroundStyle(theme.textPrimary)
                        if hideGuestOption {
                            Text("Create a free account to continue")
                                .font(theme.font(12, weight: .light))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    .padding(.top, 110)

                    VStack(spacing: 16) {
                        TextField("", text: $email, prompt: Text("Email").foregroundColor(theme.textTertiary))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .foregroundStyle(theme.textPrimary)
                            .tint(theme.accent)
                            .padding(16)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))

                        ZStack(alignment: .trailing) {
                            Group {
                                if isPasswordVisible {
                                    TextField("", text: $password, prompt: Text("Password (6+ characters)").foregroundColor(theme.textTertiary))
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                } else {
                                    SecureField("", text: $password, prompt: Text("Password (6+ characters)").foregroundColor(theme.textTertiary))
                                }
                            }
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

                        if !isSignUpMode {
                            HStack {
                                Spacer()
                                Button(action: {
                                    resetEmail = email
                                    resetSentMessage = nil
                                    showForgotPassword = true
                                }) {
                                    Text("Forgot password?")
                                        .font(theme.font(12, weight: .light))
                                        .foregroundStyle(theme.accent)
                                }
                            }
                        }

                        if isSignUpMode {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(passwordRequirements) { requirement in
                                    let met = requirement.isMet(password)
                                    HStack(spacing: 8) {
                                        Image(systemName: met ? "checkmark.circle.fill" : "circle")
                                            .font(theme.font(13))
                                            .foregroundStyle(met ? theme.accent : theme.textTertiary)
                                        Text(requirement.label)
                                            .font(theme.font(12, weight: .light))
                                            .foregroundStyle(met ? theme.textPrimary.opacity(0.8) : theme.textTertiary)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 30)
                    .animation(.easeInOut(duration: 0.2), value: isSignUpMode)

                    if awaitingEmailConfirmation {
                        VStack(spacing: 10) {
                            Image(systemName: "envelope.badge.fill")
                                .font(theme.font(20, weight: .semibold))
                                .foregroundStyle(theme.accent)
                            Text("Check your email")
                                .font(theme.font(13, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text("We sent a confirmation link to \(email). Tap it, then come back and sign in.")
                                .font(theme.font(12, weight: .light))
                                .foregroundStyle(theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.accent.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 30)
                    } else if let errorMessage = authManager.errorMessage {
                        Text(errorMessage)
                            .font(theme.font(12, weight: .light))
                            .foregroundStyle(theme.danger.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }

                    Button(action: {
                        Task {
                            if isSignUpMode {
                                authManager.errorMessage = nil
                                awaitingEmailConfirmation = false
                                await authManager.signUp(email: email, password: password)
                                if authManager.isAuthenticated == false, authManager.errorMessage == nil {
                                    // No error and not authenticated means signup succeeded
                                    // but is waiting on email confirmation.
                                    awaitingEmailConfirmation = true
                                }
                            } else {
                                await authManager.signIn(email: email, password: password)
                            }
                        }
                    }) {
                        HStack {
                            if authManager.isLoading { ProgressView().tint(theme.background) }
                            Text(authManager.isLoading ? "PLEASE WAIT..." : (isSignUpMode ? "CREATE ACCOUNT" : "SIGN IN"))
                                .font(theme.font(13, weight: .bold))
                                .tracking(2.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(isValid ? theme.textPrimary : theme.textPrimary.opacity(0.25))
                        .foregroundColor(theme.background)
                        .clipShape(Capsule())
                        .shadow(
                            color: theme.textPrimary.opacity(isValid ? 0.25 : 0),
                            radius: 16, y: 8
                        )
                    }
                    .disabled(!isValid || authManager.isLoading)
                    .padding(.horizontal, 30)

                    Button(action: {
                        isSignUpMode.toggle()
                        authManager.errorMessage = nil
                        awaitingEmailConfirmation = false
                    }) {
                        Text(isSignUpMode ? "Already have an account? Sign in" : "New here? Create an account")
                            .font(theme.font(12, weight: .light))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .padding(.top, 4)

                    if !hideGuestOption {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            authManager.continueAsGuest()
                        }) {
                            Text("Continue as Guest — try it free")
                                .font(theme.font(12, weight: .semibold))
                                .foregroundStyle(theme.accent)
                        }
                        .padding(.top, 12)
                    }

                    Spacer(minLength: 40)

                    Spacer(minLength: 40)
                }
            }
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(email: $resetEmail)
        }
        .onChange(of: authManager.needsPasswordReset) { _, needsReset in
            if needsReset {
                showForgotPassword = false
            }
        }
    }
}

// MARK: - Forgot Password Sheet
private struct ForgotPasswordSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) var dismiss
    @Binding var email: String

    @State private var isSending: Bool = false
    @State private var sentMessage: String?
    @State private var errorText: String?

    private var isValidEmail: Bool { email.contains("@") }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

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

                VStack(spacing: 6) {
                    Text("POCKET VAULT")
                        .font(theme.font(11, weight: .bold))
                        .tracking(4)
                        .foregroundStyle(theme.accent)
                    Text("Reset Password")
                        .font(theme.font(22, weight: .light))
                        .foregroundStyle(theme.textPrimary)
                }

                Text("Enter your account email and we'll send you a link to reset your password.")
                    .font(theme.font(13, weight: .light))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                TextField("", text: $email, prompt: Text("Email").foregroundColor(theme.textTertiary))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .foregroundStyle(theme.textPrimary)
                    .tint(theme.accent)
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))
                    .padding(.horizontal, 30)

                if let sentMessage {
                    Text(sentMessage)
                        .font(theme.font(12, weight: .light))
                        .foregroundStyle(theme.accent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                } else if let errorText {
                    Text(errorText)
                        .font(theme.font(12, weight: .light))
                        .foregroundStyle(theme.danger.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                Button(action: sendReset) {
                    HStack {
                        if isSending { ProgressView().tint(theme.background) }
                        Text(isSending ? "SENDING..." : "SEND RESET LINK")
                            .font(theme.font(13, weight: .bold))
                            .tracking(2.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(isValidEmail ? theme.textPrimary : theme.textPrimary.opacity(0.25))
                    .foregroundColor(theme.background)
                    .clipShape(Capsule())
                    .shadow(
                        color: theme.textPrimary.opacity(isValidEmail ? 0.25 : 0),
                        radius: 16, y: 8
                    )
                }
                .disabled(!isValidEmail || isSending)
                .padding(.horizontal, 30)

                Spacer()
            }
        }
    }

    private func sendReset() {
        isSending = true
        errorText = nil
        sentMessage = nil
        Task {
            do {
                try await authManager.sendPasswordReset(email: email)
                sentMessage = "Check your email for a link to reset your password."
            } catch {
                errorText = "Couldn't send the reset email. Check the address and try again."
            }
            isSending = false
        }
    }
}
