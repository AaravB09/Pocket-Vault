import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var goalStore: GoalStore
    @Environment(\.dismiss) var dismiss

    @State private var friendCodeInput: String = ""
    @State private var showCopiedToast: Bool = false
    @State private var showSharedBudget: Bool = false

    /// The id these server calls use — the real Supabase Auth user id.
    /// Falls back to the local `myUserID` defensively, though guests
    /// never reach this view's `.task` (see `body` below).
    private var identityID: String { authManager.userID ?? leaderboardManager.myUserID }

    var body: some View {
        if authManager.isGuest {
            AccountRequiredGateView(featureName: "Friends & Leaderboard")
        } else {
            content
        }
    }

    private var content: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
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
                        SectionLabel("Social")
                        Text("Friends & Streaks")
                            .font(theme.font(20, weight: .light))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .padding(.top, 4)

                    // My friend code
                    VStack(spacing: 10) {
                        SectionLabel("Your friend code")

                        HStack(spacing: 10) {
                            Text(leaderboardManager.myFriendCode)
                                .font(theme.font(26, weight: .semibold))
                                .tracking(4)
                                .foregroundStyle(theme.textPrimary)

                            Button(action: {
                                UIPasteboard.general.string = leaderboardManager.myFriendCode
                                showCopiedToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showCopiedToast = false }
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(theme.accent)
                            }
                        }

                        Text(showCopiedToast ? "Copied" : "Share this so friends can add you")
                            .font(theme.font(11))
                            .foregroundStyle(showCopiedToast ? theme.accent : theme.textTertiary)
                    }
                    .padding(Layout.cardPadding)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius).stroke(theme.cardStroke, lineWidth: 1))
                    .padding(.horizontal, Layout.pageMargin)

                    // Shared Budget entry — reuses the same friend-code
                    // pattern above, but for saving toward one goal together.
                    Button(action: { showSharedBudget = true }) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(theme.accent.opacity(0.15)).frame(width: 40, height: 40)
                                Image(systemName: "person.2.fill")
                                    .font(theme.font(15))
                                    .foregroundStyle(theme.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Shared budget")
                                    .font(theme.font(13, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                                Text("Save toward one goal together")
                                    .font(theme.font(11, weight: .light))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(theme.font(11, weight: .bold))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: Layout.controlRadius).stroke(theme.cardStroke, lineWidth: 1))
                    }
                    .padding(.horizontal, Layout.pageMargin)

                    // Add a friend
                    HStack(spacing: 10) {
                        TextField("Enter a friend's code", text: $friendCodeInput)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(theme.textPrimary)

                        Button(action: {
                            Task {
                                await leaderboardManager.addFriend(code: friendCodeInput, identityID: identityID, accessToken: authManager.accessToken)
                                friendCodeInput = ""
                            }
                        }) {
                            Text("Add")
                                .font(theme.font(14, weight: .semibold))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(theme.accent)
                                .foregroundColor(theme.onAccent)
                                .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius))
                        }
                        .disabled(friendCodeInput.trimmingCharacters(in: .whitespaces).isEmpty || leaderboardManager.isLoading)
                    }
                    .padding(.horizontal, Layout.pageMargin)

                    if let errorMessage = leaderboardManager.errorMessage {
                        Text(errorMessage)
                            .font(theme.font(11))
                            .foregroundStyle(theme.danger.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Layout.pageMargin)
                    }

                    // Leaderboard
                    VStack(spacing: 10) {
                        HStack {
                            SectionLabel("Streak leaderboard")
                            Spacer()
                            if leaderboardManager.isLoading { ProgressView().tint(theme.accent) }
                        }
                        .padding(.horizontal, Layout.pageMargin)

                        let ranked = rankedEntries()
                        if ranked.isEmpty && !leaderboardManager.isLoading {
                            Text("Add a friend's code above to start comparing streaks.")
                                .font(theme.font(13, weight: .light))
                                .foregroundStyle(theme.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Layout.pageMargin)
                                .padding(.top, 20)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, entry in
                                    leaderboardRow(rank: index + 1, entry: entry, isMe: entry.id == identityID)
                                }
                            }
                            .padding(.horizontal, Layout.pageMargin)
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
        }
        .themedSurface(theme)
        .task {
            await leaderboardManager.syncMyStreak(currentStreak: streakManager.currentStreak, longestStreak: streakManager.longestStreak, identityID: identityID, accessToken: authManager.accessToken)
            await leaderboardManager.fetchLeaderboard(identityID: identityID, accessToken: authManager.accessToken)
        }
        .refreshable {
            await leaderboardManager.fetchLeaderboard(identityID: identityID, accessToken: authManager.accessToken)
        }
        .sheet(isPresented: $showSharedBudget) {
            SharedBudgetView(goalStore: goalStore)
        }
    }

    private func rankedEntries() -> [LeaderboardEntry] {
        var all = leaderboardManager.friends
        if let me = leaderboardManager.myEntry { all.append(me) }
        return all.sorted { $0.current_streak > $1.current_streak }
    }

    private func leaderboardRow(rank: Int, entry: LeaderboardEntry, isMe: Bool) -> some View {
        HStack(spacing: 14) {
            Text("#\(rank)")
                .font(theme.font(12, weight: .bold))
                .foregroundStyle(rank == 1 ? theme.accent : theme.textTertiary)
                .frame(width: 28, alignment: .leading)

            Text(isMe ? "You" : entry.display_name)
                .font(theme.font(13, weight: isMe ? .bold : .regular))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "flame.fill").font(theme.font(11)).foregroundStyle(theme.accent)
                Text("\(entry.current_streak)")
                    .font(theme.font(13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isMe ? (theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06)) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))
    }
}
