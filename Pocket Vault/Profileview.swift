import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var privacyManager: PrivacyManager
    @EnvironmentObject var goalStore: GoalStore
    @EnvironmentObject var budgetManager: BudgetManager

    @State private var displayName: String = ""
    @State private var showSignOutConfirm: Bool = false
    @State private var showFeedback: Bool = false
    @State private var showLeaderboard: Bool = false
    @State private var exportURLs: [URL]? = nil
    @State private var exportFormat: ExportFormat = .csv

    private enum ExportFormat: String, CaseIterable, Identifiable {
        case csv = "CSV"
        case json = "JSON"
        var id: String { rawValue }
    }

    @State private var profileImageData: Data?
    @State private var selectedItem: PhotosPickerItem? = nil

    private var profileImageKey: String { "pv_profileImage_\(leaderboardManager.myUserID)" }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    HStack {
                        ShareLink(item: "Join me on Pocket Vault and let's save together! Add me with friend code \(leaderboardManager.myFriendCode).") {
                            HStack(spacing: 6) {
                                Image(systemName: "person.badge.plus")
                                    .font(theme.font(12, weight: .semibold))
                                Text("INVITE FRIENDS")
                                    .font(theme.font(10, weight: .bold))
                                    .tracking(1.2)
                            }
                            .foregroundStyle(theme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(
                                    LinearGradient(
                                        colors: [theme.accent.opacity(0.7), theme.textPrimary.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                            )
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                        }

                        // Opens the leaderboard/add-friend screen, which
                        // also has the entry point into Shared Budget —
                        // ProfileView itself only ever showed the "invite"
                        // share sheet and the friend code, with no way
                        // back into the fuller Friends experience.
                        Button(action: { showLeaderboard = true }) {
                            Image(systemName: "trophy.fill")
                                .font(theme.font(13, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(theme.cardStroke, lineWidth: 1))
                        }

                        Spacer()

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(theme.font(22, weight: .bold))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Profile Header & Avatar Picker
                    VStack(spacing: 12) {
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            ZStack {
                                if let profileImageData, let uiImage = UIImage(data: profileImageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 80, height: 80)
                                    Image(systemName: "person.fill")
                                        .font(theme.font(30, weight: .light))
                                        .foregroundStyle(theme.accent)
                                }

                                Circle()
                                    .stroke(theme.accent.opacity(0.6), lineWidth: 1.5)
                                    .frame(width: 80, height: 80)

                                Image(systemName: "camera.fill")
                                    .font(theme.font(10, weight: .bold))
                                    .foregroundStyle(theme.onAccent)
                                    .padding(6)
                                    .background(theme.accent)
                                    .clipShape(Circle())
                                    .offset(x: 28, y: 28)
                            }
                        }
                        .onChange(of: selectedItem) {
                            Task {
                                if let data = try? await selectedItem?.loadTransferable(type: Data.self) {
                                    profileImageData = data
                                    UserDefaults.standard.set(data, forKey: profileImageKey)
                                }
                            }
                        }

                        Text("YOUR VAULT")
                            .font(theme.font(10, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(theme.accent)

                        Text(authManager.userEmail ?? "No email on file")
                            .font(theme.font(15, weight: .light))
                            .foregroundStyle(theme.textPrimary.opacity(0.8))
                    }

                    // Display name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DISPLAY NAME")
                            .font(theme.font(9, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(theme.textTertiary)

                        HStack {
                            TextField("Saver", text: $displayName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .foregroundStyle(theme.textPrimary)
                                .padding(14)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))

                            Button(action: saveDisplayName) {
                                Text("SAVE")
                                    .font(theme.font(10, weight: .bold))
                                    .tracking(1)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(theme.accent)
                                    .foregroundColor(theme.onAccent)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Friend code
                    VStack(spacing: 8) {
                        Text("FRIEND CODE")
                            .font(theme.font(9, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(theme.textTertiary)
                        Text(leaderboardManager.myFriendCode)
                            .font(theme.font(20, weight: .semibold))
                            .tracking(3)
                            .foregroundStyle(theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.cardStroke, lineWidth: 1))
                    .padding(.horizontal, 24)

                    // Privacy Mode + local data export — nothing here is
                    // gated behind Pro: manual tracking and getting your
                    // own data back out should always be free.
                    privacyAndDataSection

                    // Appearance — accent color + light/dark/system
                    ThemePickerSection()

                    Button(action: { showFeedback = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill")
                            Text("SEND FEEDBACK")
                        }
                    }
                    .buttonStyle(.secondaryCTA(theme))
                    .padding(.horizontal, 24)

                    Button(action: { showSignOutConfirm = true }) {
                        Text("SIGN OUT")
                            .font(theme.font(11, weight: .bold))
                            .tracking(2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.ultraThinMaterial)
                            .foregroundColor(.red.opacity(0.85))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 1))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    Spacer(minLength: 40)
                }
            }
        }
        .onAppear {
            displayName = leaderboardManager.myDisplayName
            profileImageData = UserDefaults.standard.data(forKey: profileImageKey)
        }
        .confirmationDialog(
            "Sign out of Pocket Vault?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await authManager.signOut()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
        }
        .sheet(isPresented: $showLeaderboard) {
            LeaderboardView(goalStore: goalStore)
        }
    }

    private func saveDisplayName() {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        leaderboardManager.myDisplayName = trimmed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Privacy & Data

    private var privacyAndDataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PRIVACY & DATA")
                .font(theme.font(9, weight: .bold))
                .tracking(2)
                .foregroundStyle(theme.textTertiary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Privacy Mode")
                        .font(theme.font(13, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Text("Blurs balances until you tap to reveal — handy with people around.")
                        .font(theme.font(10, weight: .light))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $privacyManager.isPrivacyModeOn)
                    .labelsHidden()
                    .tint(theme.accent)
            }
            .padding(14)
            .background(theme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                Picker("Format", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: exportFormat) { _, _ in exportURLs = nil }

                if let exportURLs, !exportURLs.isEmpty {
                    ShareLink(items: exportURLs) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                            Text("EXPORT MY DATA")
                        }
                    }
                    .buttonStyle(.secondaryCTA(theme))
                } else {
                    Button(action: prepareExport) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                            Text("EXPORT MY DATA")
                        }
                    }
                    .buttonStyle(.secondaryCTA(theme))
                }

                Text("Exports your goals, savings history, and transactions as plain \(exportFormat.rawValue) files — a format any spreadsheet or other app can open. Nothing leaves your device unless you choose to share it.")
                    .font(theme.font(10, weight: .light))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1))
        .padding(.horizontal, 24)
    }

    /// Builds the export files fresh right before sharing, rather than
    /// keeping them around, so an export never goes stale against
    /// whatever's actually in GoalStore/BudgetManager right now.
    private func prepareExport() {
        var urls: [URL] = []
        switch exportFormat {
        case .csv:
            if let goalsURL = DataExporter.writeTempFile(DataExporter.goalsCSV(goalStore.goals), filename: "pocket_vault_goals.csv") {
                urls.append(goalsURL)
            }
            if let transactionsURL = DataExporter.writeTempFile(DataExporter.transactionsCSV(budgetManager.transactions), filename: "pocket_vault_transactions.csv") {
                urls.append(transactionsURL)
            }
        case .json:
            if let goalsURL = DataExporter.writeTempFile(DataExporter.goalsJSON(goalStore.goals), filename: "pocket_vault_goals.json") {
                urls.append(goalsURL)
            }
            if let transactionsURL = DataExporter.writeTempFile(DataExporter.transactionsJSON(budgetManager.transactions), filename: "pocket_vault_transactions.json") {
                urls.append(transactionsURL)
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        exportURLs = urls
    }
}
