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
    // FIX ("turns white" on press): bare Buttons with no `.buttonStyle`
    // picked up the system default dimming — see PressableButton.swift.
    @State private var isSharedBudgetRowPressed = false
    @State private var isAddFriendPressed = false

    /// The id these server calls use — the real Supabase Auth user id.
    /// Falls back to the local `myUserID` defensively, though guests
    /// never reach this view's `.task` (see `body` below).
    private var identityID: String { authManager.userID ?? leaderboardManager.myUserID }

    public var body: some View {
        if authManager.isGuest {
            AccountRequiredGateView(featureName: "Friends & Leaderboard")
        } else {
            content
        }
    }

    private var content: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24.0) {
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image.platformSymbol("xmark.circle.fill", android: "xmark")
                                .font(theme.font(22, weight: Font.Weight.bold))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(Edge.Set.horizontal, Layout.pageMargin)
                    .padding(Edge.Set.top, 20.0)

                    VStack(spacing: 6.0) {
                        SectionLabel("Social")
                        Text("Friends & Streaks")
                            .font(theme.font(20, weight: Font.Weight.light))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .padding(Edge.Set.top, 4.0)

                    // My friend code
                    VStack(spacing: 10.0) {
                        SectionLabel("Your friend code")

                        HStack(spacing: 10.0) {
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
                            .buttonStyle(.plain)
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
                    .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius).stroke(Color.clear, lineWidth: 1.0))
                    .padding(Edge.Set.horizontal, Layout.pageMargin)

                    // Shared Budget entry — reuses the same friend-code
                    // pattern above, but for saving toward one goal together.
                    Button(action: { showSharedBudget = true }) {
                        HStack(spacing: 14.0) {
                            ZStack {
                                Circle().fill(theme.accent.opacity(0.15)).frame(width: 40.0, height: 40.0)
                                Image.platformSymbol("person.2.fill", android: "person.fill")
                                    .font(theme.font(15))
                                    .foregroundStyle(theme.accent)
                            }
                            VStack(alignment: HorizontalAlignment.leading, spacing: 2.0) {
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
                        .padding(16.0)
                        #if !SKIP
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius))
                        #else
                        .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                        .cornerRadius(Layout.controlRadius)
                        #endif
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.controlRadius)
                                .fill(theme.isLight ? Color.black.opacity(isSharedBudgetRowPressed ? 0.05 : 0.0) : Color.white.opacity(isSharedBudgetRowPressed ? 0.06 : 0.0))
                        )
                        .overlay(RoundedRectangle(cornerRadius: Layout.controlRadius).stroke(Color.clear, lineWidth: 1.0))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isSharedBudgetRowPressed = true }
                            .onEnded { _ in isSharedBudgetRowPressed = false }
                    )
                    .padding(Edge.Set.horizontal, Layout.pageMargin)

                    // Add a friend
                    HStack(spacing: 10.0) {
                        TextField("Enter a friend's code", text: $friendCodeInput)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(TextInputAutocapitalization.characters)
                            .autocorrectionDisabled()
                            .padding(14.0)
                            #if !SKIP
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14.0))
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
                                .padding(Edge.Set.horizontal, 20.0)
                                .padding(Edge.Set.vertical, 16.0)
                                .background(theme.accent.opacity(isAddFriendPressed ? 0.85 : 1.0))
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
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in isAddFriendPressed = true }
                                .onEnded { _ in isAddFriendPressed = false }
                        )
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
                    VStack(spacing: 10.0) {
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
                                .padding(Edge.Set.top, 20.0)
                        } else {
                            VStack(spacing: 10.0) {
                                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, entry in
                                    leaderboardRow(rank: index + 1, entry: entry, isMe: entry.id == identityID)
                                }
                            }
                            .padding(Edge.Set.horizontal, Layout.pageMargin)
                        }
                    }
                    .padding(Edge.Set.bottom, 120.0)
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
        // FIX: same root cause as GoalPickerBar's chip fill — a nested
        // Color ternary passed directly into `.background(...)` doesn't
        // reliably transpile through Skip on Android. Extracting to a
        // `let` first fixes it.
        let rowFillColor: Color = isMe
            ? (theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
            : Color.clear

        return HStack(spacing: 14.0) {
            Text("#\(rank)")
                .font(theme.font(12, weight: Font.Weight.bold))
                .foregroundStyle(rank == 1 ? theme.accent : theme.textTertiary)
                .frame(width: 28.0, alignment: Alignment.leading)

            Text(isMe ? "You" : entry.display_name)
                .font(theme.font(13, weight: isMe ? Font.Weight.bold : Font.Weight.regular))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            HStack(spacing: 4.0) {
                Image.platformSymbol("flame.fill", android: "heart.fill").font(theme.font(11)).foregroundStyle(theme.accent)
                Text("\(entry.current_streak)")
                    .font(theme.font(13, weight: Font.Weight.semibold))
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .padding(Edge.Set.horizontal, 16.0)
        .padding(Edge.Set.vertical, 14.0)
        .background(rowFillColor)
        #if !SKIP
        .clipShape(RoundedRectangle(cornerRadius: 14.0))
        #else
        .cornerRadius(14)
        #endif
        .overlay(RoundedRectangle(cornerRadius: 14.0).stroke(Color.clear, lineWidth: 1.0))
    }
}
