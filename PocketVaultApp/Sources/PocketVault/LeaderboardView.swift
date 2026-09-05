import SwiftUI

public struct LeaderboardView: View {
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var goalStore: GoalStore
    @Environment(\.dismiss) var dismiss: DismissAction

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
                            Image.platformSymbol("xmark.circle.fill", android: "xmark")
                                .font(theme.font(22, weight: Font.Weight.bold))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .padding(Edge.Set.horizontal, Layout.pageMargin)
                    .padding(Edge.Set.top, 20)

                    VStack(spacing: 6) {
                        SectionLabel("Social")
                        Text("Friends & Streaks")
                            .font(theme.font(20, weight: Font.Weight.light))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .padding(Edge.Set.top, 4)

                    // My friend code
                    VStack(spacing: 10) {
                        SectionLabel("Your friend code")

                        HStack(spacing: 10) {
                            Text(leaderboardManager.myFriendCode)
                                .font(theme.font(26, weight: Font.Weight.semibold))
                                .tracking(4)
                                .foregroundStyle(theme.textPrimary)

                            Button(action: {
                                UIPasteboard.general.string = leaderboardManager.myFriendCode
                                showCopiedToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showCopiedToast = false }
                            }) {
                                Image.platformSymbol("doc.on.doc", android: "square.and.arrow.up")
                                    .foregroundStyle(theme.accent)
                            }
                        }

                        Text(showCopiedToast ? "Copied" : "Share this so friends can add you")
                            .font(theme.font(11))
                            .foregroundStyle(showCopiedToast ? theme.accent : theme.textTertiary)
                    }
                    .padding(Layout.cardPadding)
                    .frame(maxWidth: CGFloat.infinity)
                    // NOTE(skip): `.ultraThinMaterial` and `.clipShape` aren't
                    // resolved by Skip's SwiftUI shim — iOS keeps the real
                    // material + shape clip, Android gets a plain tinted
                    // background + `.cornerRadius`.
                    #if !SKIP
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius))
                    #else
                    .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                    .cornerRadius(Layout.cardRadius)
                    #endif
                    .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius).stroke(theme.cardStroke, lineWidth: 1))
                    .padding(Edge.Set.horizontal, Layout.pageMargin)

                    // Shared Budget entry — reuses the same friend-code
                    // pattern above, but for saving toward one goal together.
                    Button(action: { showSharedBudget = true }) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(theme.accent.opacity(0.15)).frame(width: 40, height: 40)
                                Image.platformSymbol("person.2.fill", android: "person.fill")
                                    .font(theme.font(15))
                                    .foregroundStyle(theme.accent)
                            }
                            VStack(alignment: Alignment.leading, spacing: 2) {
                                Text("Shared budget")
                                    .font(theme.font(13, weight: Font.Weight.semibold))
                                    .foregroundStyle(theme.textPrimary)
                                Text("Save toward one goal together")
                                    .font(theme.font(11, weight: Font.Weight.light))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(theme.font(11, weight: Font.Weight.bold))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .padding(16)
                        #if !SKIP
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius))
                        #else
                        .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                        .cornerRadius(Layout.controlRadius)
                        #endif
                        .overlay(RoundedRectangle(cornerRadius: Layout.controlRadius).stroke(theme.cardStroke, lineWidth: 1))
                    }
                    .padding(Edge.Set.horizontal, Layout.pageMargin)

                    // Add a friend
                    HStack(spacing: 10) {
                        TextField("Enter a friend's code", text: $friendCodeInput)
                            .textInputAutocapitalization(TextInputAutocapitalization.characters)
                            .autocorrectionDisabled()
                            .padding(14)
                            #if !SKIP
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            #else
                            .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                            .cornerRadius(14)
                            #endif
                            .foregroundStyle(theme.textPrimary)

                        Button(action: {
                            Task {
                                await leaderboardManager.addFriend(code: friendCodeInput, identityID: identityID, accessToken: authManager.accessToken)
                                friendCodeInput = ""
                            }
                        }) {
                            Text("Add")
                                .font(theme.font(14, weight: Font.Weight.semibold))
                                .padding(Edge.Set.horizontal, 20)
                                .padding(Edge.Set.vertical, 16)
                                .background(theme.accent)
                                .foregroundColor(theme.onAccent)
                                // NOTE(skip): `.clipShape` isn't resolved by Skip's
                                // SwiftUI shim — `.cornerRadius` gives the same
                                // rounded look on Android.
                                #if !SKIP
                                .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius))
                                #else
                                .cornerRadius(Layout.controlRadius)
                                #endif
                        }
                        .disabled(friendCodeInput.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty || leaderboardManager.isLoading)
                    }
                    .padding(Edge.Set.horizontal, Layout.pageMargin)

                    if let errorMessage = leaderboardManager.errorMessage {
                        Text(errorMessage)
                            .font(theme.font(11))
                            .foregroundStyle(theme.danger.opacity(0.9))
                            .multilineTextAlignment(TextAlignment.center)
                            .padding(Edge.Set.horizontal, Layout.pageMargin)
                    }

                    // Leaderboard
                    VStack(spacing: 10) {
                        HStack {
                            SectionLabel("Streak leaderboard")
                            Spacer()
                            if leaderboardManager.isLoading { ProgressView().tint(theme.accent) }
                        }
                        .padding(Edge.Set.horizontal, Layout.pageMargin)

                        let ranked = rankedEntries()
                        if ranked.isEmpty && !leaderboardManager.isLoading {
                            Text("Add a friend's code above to start comparing streaks.")
                                .font(theme.font(13, weight: Font.Weight.light))
                                .foregroundStyle(theme.textTertiary)
                                .multilineTextAlignment(TextAlignment.center)
                                .padding(Edge.Set.horizontal, Layout.pageMargin)
                                .padding(Edge.Set.top, 20)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, entry in
                                    leaderboardRow(rank: index + 1, entry: entry, isMe: entry.id == identityID)
                                }
                            }
                            .padding(Edge.Set.horizontal, Layout.pageMargin)
                        }
                    }
                    .padding(Edge.Set.bottom, 120)
                }
            }
        }
        // FIX: Replaced `theme` with `ignoresSafeArea: true` to resolve the compiler error
        .themedSurface(ignoresSafeArea: true)
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
                .font(theme.font(12, weight: Font.Weight.bold))
                .foregroundStyle(rank == 1 ? theme.accent : theme.textTertiary)
                .frame(width: 28, alignment: Alignment.leading)

            Text(isMe ? "You" : entry.display_name)
                .font(theme.font(13, weight: isMe ? Font.Weight.bold : Font.Weight.regular))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            HStack(spacing: 4) {
                Image.platformSymbol("flame.fill", android: "heart.fill").font(theme.font(11)).foregroundStyle(theme.accent)
                Text("\(entry.current_streak)")
                    .font(theme.font(13, weight: Font.Weight.semibold))
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .padding(Edge.Set.horizontal, 16)
        .padding(Edge.Set.vertical, 14)
        .background(isMe ? (theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06)) : Color.clear)
        #if !SKIP
        .clipShape(RoundedRectangle(cornerRadius: 14))
        #else
        .cornerRadius(14)
        #endif
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))
    }
}
