import SwiftUI
import UIKit
#if !SKIP
import PhotosUI
#endif

// ⚠️ PLAY STORE RELEASE CHECKLIST — MUST READ BEFORE SHIPPING ⚠️
// ────────────────────────────────────────────────────────────────
// The `devSection` in this file is conditionally compiled in via
// `#if DEBUG` on iOS (safe — Xcode strips it from release) but
// `#if SKIP` on Android. Skip does NOT strip the code inside
// `#if SKIP` — only the outer guard. So the Android devSection
// ships in the release APK unless `EntitlementManager.androidDevBuildsOnly`
// is flipped to `false`. See Entitlementmanager.swift for the
// full checklist. Both `shouldShowDevSection` (here) and `isPro`
// (there) gate on the same flag, so a forgotten flip means the
// toggle is hidden in the UI even if the code path is still present.
// ────────────────────────────────────────────────────────────────

struct ProfileView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var privacyManager: PrivacyManager
    @EnvironmentObject var goalStore: GoalStore
    @EnvironmentObject var budgetManager: BudgetManager
    #if DEBUG
    @EnvironmentObject var entitlementManager: EntitlementManager
    #endif

    @State private var displayName: String = ""
    @State private var showSignOutConfirm: Bool = false
    @State private var showDeleteAccountConfirm: Bool = false
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

    /// Local toggle state for the dev-section Force Pro toggle. We use a local
    /// `@State` rather than binding directly to `EntitlementManager.forceProOverride`
    /// because on Android Skip translates a static `@Published` as a plain `var`
    /// with no Compose-tracked state, so a direct binding doesn't trigger a re-render
    /// when the user flips the switch. The local `@State` is the source of truth
    /// for the toggle UI; `.task` reads the initial value from
    /// `EntitlementManager.forceProOverride`, and `.onChange(of: isForceProOverride)`
    /// pushes changes back. On iOS Release, `forceProOverride`'s setter is a no-op,
    /// so the push is harmless.
    @State private var isForceProOverride: Bool = false

    #if !SKIP
    @State private var selectedItem: PhotosPickerItem? = nil
    #endif

    private var profileImageKey: String { "pv_profileImage_\(leaderboardManager.myUserID)" }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 26) {
                    HStack {
                        ShareLink(item: "Join me on Pocket Vault and let's save together! Add me with friend code \(leaderboardManager.myFriendCode).") {
                            HStack(spacing: 6) {
                                Image.platformSymbol("person.badge.plus", android: "plus.circle.fill")
                                    .font(theme.font(12, weight: .semibold))
                                Text("Invite friends")
                                    .font(theme.font(13, weight: .semibold))
                            }
                            .foregroundStyle(theme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            // Unified cross-platform styling
                            .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                            .cornerRadius(100)
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

                        Button(action: { showLeaderboard = true }) {
                            Image.platformSymbol("trophy.fill", android: "star.fill")
                                .font(theme.font(13, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 38, height: 38)
                                .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                                .cornerRadius(19)
                                .overlay(Circle().stroke(theme.cardStroke, lineWidth: 1))
                        }

                        Spacer()

                        Button(action: { dismiss() }) {
                            Image.platformSymbol("xmark.circle.fill", android: "xmark")
                                .font(theme.font(22, weight: .bold))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Profile Header & Avatar Picker
                    VStack(spacing: 12) {
                        #if !SKIP
                        PhotosPicker(selection: $selectedItem, matching: PHPickerFilter.images) {
                            avatarContent
                        }
                        .onChange(of: selectedItem) {
                            Task {
                                if let data = try? await selectedItem?.loadTransferable(type: Data.self) {
                                    profileImageData = data
                                    UserDefaults.standard.set(data, forKey: profileImageKey)
                                }
                            }
                        }
                        #else
                        avatarContent
                        #endif

                        Text("Your vault")
                            .font(theme.font(15, weight: .semibold))
                            .foregroundStyle(theme.accent)

                        Text(authManager.userEmail ?? "No email on file")
                            .font(theme.font(15, weight: .light))
                            .foregroundStyle(theme.textPrimary.opacity(0.8))
                    }

                    // Display name
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Display name")

                        HStack {
                            TextField("Saver", text: $displayName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .foregroundStyle(theme.textPrimary)
                                .padding(14)
                                .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                                .cornerRadius(Layout.controlRadius)
                                .overlay(RoundedRectangle(cornerRadius: Layout.controlRadius).stroke(theme.cardStroke, lineWidth: 1))

                            Button(action: saveDisplayName) {
                                Text("Save")
                                    .font(theme.font(14, weight: .semibold))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 14)
                                    .background(theme.accent)
                                    .foregroundColor(theme.onAccent)
                                    .cornerRadius(Layout.controlRadius)
                            }
                            .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.horizontal, Layout.pageMargin)

                    // Friend code
                    VStack(spacing: 8) {
                        SectionLabel("Friend code")
                        Text(leaderboardManager.myFriendCode)
                            .font(theme.font(20, weight: .semibold))
                            .tracking(3)
                            .foregroundStyle(theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.cardStroke, lineWidth: 1))
                    .padding(.horizontal, Layout.pageMargin)

                    privacyAndDataSection
                    ThemePickerSection()

                    if shouldShowDevSection {
                        devSection
                    }

                    LegalFinePrint()
                        .padding(.top, 4)

                    Button(action: { showFeedback = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill")
                            Text("Send feedback")
                        }
                    }
                    .secondaryCTA(accent: theme.accent)
                    .padding(.horizontal, Layout.pageMargin)

                    Button(action: { showSignOutConfirm = true }) {
                        Text("Sign out")
                    }
                    .secondaryCTA(accent: theme.danger)
                    .padding(.horizontal, Layout.pageMargin)
                    .padding(.top, 8)

                    Button(action: { showDeleteAccountConfirm = true }) {
                        Text("Delete account")
                    }
                    .secondaryCTA(accent: Color.red.opacity(0.85))
                    .padding(.horizontal, Layout.pageMargin)
                    .padding(.top, 6)

                    Spacer(minLength: 40)
                }
            }
        }
        // FIX: themedSurface() no longer takes `theme` as a parameter —
        // it reads ThemeManager via @EnvironmentObject internally now
        // (see ThemedSurface.swift). The old `.themedSurface(theme)` call
        // was passing `theme` positionally into the `ignoresSafeArea: Bool`
        // slot, which is what produced "Cannot convert value of type
        // 'ThemeManager' to expected argument type 'Bool'" and "Missing
        // argument label 'ignoresSafeArea:' in call" together. It also
        // broke type inference for the rest of this modifier chain, which
        // is why Skip couldn't resolve `.visible` in the
        // `.confirmationDialog(titleVisibility:)` call further down —
        // that error should clear along with this one.
        .themedSurface()
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
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task {
                    do {
                        try await authManager.deleteAccount()
                        dismiss()
                    } catch {
                        print("Delete account failed:", error.localizedDescription)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if EntitlementManager.isPro {
                Text("You have an active Pro subscription. Cancel it in your device's store settings BEFORE deleting, or you may continue to be charged.")
            } else {
                Text("This will permanently delete all your goals, savings history, and account data. This cannot be undone.")
            }
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
        }
        .sheet(isPresented: $showLeaderboard) {
            LeaderboardView(goalStore: goalStore)
        }
    }
    
    // MARK: - Extracted Avatar Content
    private var avatarContent: some View {
        ZStack {
            if let profileImageData, let uiImage = UIImage(data: profileImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .cornerRadius(40)
            } else {
                Circle()
                    .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.fill")
                    .font(theme.font(30, weight: .light))
                    .foregroundStyle(theme.accent)
            }

            Circle()
                .stroke(theme.accent.opacity(0.6), lineWidth: 1.5)
                .frame(width: 80, height: 80)

            #if !SKIP
            Image.platformSymbol("camera.fill", android: "pencil")
                .font(theme.font(10, weight: .bold))
                .foregroundStyle(theme.onAccent)
                .padding(6)
                .background(theme.accent)
                .clipShape(Circle())
                .offset(x: 28, y: 28)
            #endif
        }
    }

    private func saveDisplayName() {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        leaderboardManager.myDisplayName = trimmed
        
        #if !SKIP
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    // iOS: true only in Debug builds (compile-time stripped via #if DEBUG inside)
    // Android: runtime-check against androidDevBuildsOnly (EntitlementManager.isAndroidDevBuild)
    // Both gates together: if androidDevBuildsOnly = false at release
    // time, the dev section is invisible even if the code somehow slipped
    // through (defence in depth; the real gate is in EntitlementManager).
    #if !SKIP
    private var shouldShowDevSection: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    #else
    private var shouldShowDevSection: Bool {
        EntitlementManager.isAndroidDevBuild
    }
    #endif

    // On iOS: `shouldShowDevSection` returns true in Debug builds, false in
    // Release — so this entire section is only reachable when building for
    // development. On Android: same gate via `androidDevBuildsOnly`.
    // The `devSection` is left outside any `#if DEBUG` so Skip's transpile
    // doesn't strip it (Skip only respects `#if SKIP`, not `#if DEBUG`).
    private var devSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Dev tools")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Force Pro unlocked")
                        .font(theme.font(13, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Text("Bypasses RevenueCat entirely for this session. DEBUG builds only — never ships.")
                        .font(theme.font(10, weight: .light))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                // Uses `$isForceProOverride` (local @State) as the source of truth,
                // with .task loading the initial value from EntitlementManager and
                // .onChange pushing updates back. We can't bind directly to the static
                // EntitlementManager.forceProOverride because Skip translates the static
                // @Published as a plain Kotlin var with no Compose state tracking, so
                // a direct Binding wouldn't trigger re-renders on Android.
                Toggle("", isOn: $isForceProOverride)
                    .labelsHidden()
                    .tint(theme.danger)
            }

            Button(action: {
                Task { await EntitlementManager.resetTestAccountStatic() }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset test account")
                }
                .font(theme.font(12, weight: .medium))
                .foregroundStyle(theme.danger)
            }
        }
        .padding(20)
        .background(theme.danger.opacity(0.08))
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.danger.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, Layout.pageMargin)
        // Sync local @State from static EntitlementManager.forceProOverride on appear.
        .task { isForceProOverride = EntitlementManager.forceProOverride }
        // Push local @State changes back into EntitlementManager.forceProOverride.
        .onChange(of: isForceProOverride) { EntitlementManager.forceProOverride = $0 }
    }

    // MARK: - Privacy & Data
    private var privacyAndDataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Privacy & data")

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
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                Picker("Format", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: exportFormat) { _ in exportURLs = nil }

                if let exportURLs, !exportURLs.isEmpty {
                    #if !SKIP
                    ShareLink(items: exportURLs) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                            Text("EXPORT MY DATA")
                        }
                    }
                    .secondaryCTA(accent: theme.accent)
                    #else
                    if let firstURL = exportURLs.first {
                        ShareLink(item: firstURL) {
                            HStack(spacing: 10) {
                                Image(systemName: "square.and.arrow.up")
                                Text("EXPORT MY DATA")
                            }
                        }
                        .secondaryCTA(accent: theme.accent)
                    }
                    #endif
                } else {
                    Button(action: prepareExport) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                            Text("EXPORT MY DATA")
                        }
                    }
                    .secondaryCTA(accent: theme.accent)
                }

                Text("Exports your goals, savings history, and transactions as plain \(exportFormat.rawValue) files — a format any spreadsheet or other app can open. Nothing leaves your device unless you choose to share it.")
                    .font(theme.font(10, weight: .light))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(20)
        .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1))
        .padding(.horizontal, Layout.pageMargin)
    }

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
        
        #if !SKIP
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        
        exportURLs = urls
    }
}

// MARK: - App Button Styles

struct SecondaryCTAStyleModifier: ViewModifier {
    var accent: Color
    
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15, weight: .semibold))
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(accent.opacity(0.12))
            .foregroundColor(accent)
            .cornerRadius(12)
    }
}

extension View {
    // For specific colors like your danger accent
    func secondaryCTA(accent: Color) -> some View {
        self.modifier(SecondaryCTAStyleModifier(accent: accent))
    }
}
