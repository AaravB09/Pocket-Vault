import SwiftUI

public struct SharedBudgetView: View {
    @EnvironmentObject var sharedBudgetManager: SharedBudgetManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var goalStore: GoalStore
    @Environment(\.dismiss) var dismiss: DismissAction

    /// Set when this view is shown as its own permanent tab (see
    /// MainTabView) rather than pushed as a sheet from LeaderboardView.
    /// Leaving the shared budget then routes back to the VAULT tab
    /// instead of calling `dismiss()`, which has nothing to dismiss in
    /// that context — and the tab bar hides this tab itself once
    /// there's no partner left, so there's nowhere else useful to land.
    var selectedTab: Binding<Int>? = nil

    @State private var joinCodeInput: String = ""
    @State private var showCopiedToast: Bool = false
    @State private var showLeaveConfirm: Bool = false

    private var myID: String { authManager.userID ?? leaderboardManager.myUserID }
    private var myName: String { leaderboardManager.myDisplayName }

    /// Cross-platform stand-in for `.ultraThinMaterial`. Materials are a
    /// UIKit/AppKit blur effect with no Compose equivalent, so Skip can't
    /// resolve them at all (that's the "Unresolved reference" error). A
    /// plain translucent fill built from an existing theme token renders
    /// identically on both platforms instead of relying on a system
    /// effect that only one side has.
    private var cardFill: Color { theme.cardStroke.opacity(0.35) }

    public var body: some View {
        if authManager.isGuest {
            AccountRequiredGateView(featureName: "Shared Budget")
        } else {
            content
        }
    }

    private var content: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    if selectedTab == nil {
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
                    } else {
                        Color.clear.frame(height: 8)
                    }

                    VStack(spacing: 6) {
                        SectionLabel("Shared budget")
                        Text("Save Together")
                            .font(theme.font(22, weight: Font.Weight.light))
                            .foregroundStyle(theme.textPrimary)
                    }

                    if let goal = goalStore.activeGoal, let sharedID = goal.sharedGoalID {
                        sharedGoalCard(goal: goal, sharedID: sharedID)
                    } else if let goal = goalStore.activeGoal {
                        shareThisGoalCard(goal: goal)
                    } else {
                        Text("Create a goal first, then come back to share it.")
                            .font(theme.font(13, weight: Font.Weight.light))
                            .foregroundStyle(theme.textTertiary)
                            .multilineTextAlignment(TextAlignment.center)
                            .padding(Edge.Set.horizontal, Layout.pageMargin)
                    }

                    joinCard

                    if let errorMessage = sharedBudgetManager.errorMessage {
                        Text(errorMessage)
                            .font(theme.font(11))
                            .foregroundStyle(theme.danger.opacity(0.9))
                            .multilineTextAlignment(TextAlignment.center)
                            .padding(Edge.Set.horizontal, Layout.pageMargin)
                    }

                    Spacer(minLength: 40)
                }
            }
            .refreshable {
                if let sharedID = goalStore.activeGoal?.sharedGoalID {
                    await sharedBudgetManager.loadShare(id: sharedID, accessToken: authManager.accessToken)
                }
            }
        }
        // FIX: Replaced `theme` with `ignoresSafeArea: true` to resolve the compiler error
        .themedSurface(ignoresSafeArea: true)
        .task {
            if let sharedID = goalStore.activeGoal?.sharedGoalID {
                await sharedBudgetManager.loadShare(id: sharedID, accessToken: authManager.accessToken)
            }
        }
    }

    // MARK: - Active goal isn't shared yet
    private func shareThisGoalCard(goal: Goal) -> some View {
        VStack(spacing: 14) {
            Image.platformSymbol("person.2.fill", android: "person.fill")
                .font(theme.font(26, weight: Font.Weight.light))
                .foregroundStyle(theme.accent)

            Text("Share “\(goal.title)” with a partner")
                .font(theme.font(14, weight: Font.Weight.light))
                .foregroundStyle(theme.textPrimary.opacity(0.7))
                .multilineTextAlignment(TextAlignment.center)

            Text("You'll both see every deposit and how close you are together.")
                .font(theme.font(12, weight: Font.Weight.light))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(TextAlignment.center)

            PrimaryCTAButton(accent: theme.accent, onAccent: theme.onAccent, action: {
                Task {
                    if let record = await sharedBudgetManager.createShare(
                        goalTitle: goal.title,
                        targetAmount: goal.targetAmount,
                        ownerID: myID,
                        ownerName: myName,
                        accessToken: authManager.accessToken
                    ) {
                        goalStore.mutateActive { $0.sharedGoalID = record.id }
                        await sharedBudgetManager.loadShare(id: record.id, accessToken: authManager.accessToken)
                    }
                }
            }) {
                HStack {
                    if sharedBudgetManager.isLoading { ProgressView().tint(theme.onAccent) }
                    Text(sharedBudgetManager.isLoading ? "Please wait…" : "Share this goal")
                }
            }
            .disabled(sharedBudgetManager.isLoading)
        }
        .padding(Layout.cardPadding)
        .background(cardFill)
        .cornerRadius(Layout.cardRadius)
        .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius).stroke(theme.cardStroke, lineWidth: 1))
        .padding(Edge.Set.horizontal, Layout.pageMargin)
    }

    // MARK: - Already shared: split-avatar card
    private func sharedGoalCard(goal: Goal, sharedID: String) -> some View {
        let mine = sharedBudgetManager.contributed(by: myID)
        let partnerID = sharedBudgetManager.share?.partner_id
        // FIXED: Changed 0 to 0.0 so Skip infers `partnerAmount` as Double instead of Int/Number
        let partnerAmount = partnerID.map { sharedBudgetManager.contributed(by: $0) } ?? 0.0
        let partnerName = sharedBudgetManager.share?.partner_name ?? "Waiting for partner"
        let combined = mine + partnerAmount
        let progress = min(max(combined / max(goal.targetAmount, 1.0), 0.0), 1.0)

        return VStack(spacing: 26) {
            HStack(spacing: 0) {
                contributorAvatar(initial: "Y", label: "You", amount: mine)
                Image.platformSymbol("arrow.left.arrow.right", android: "arrow.clockwise.circle")
                    .font(theme.font(12))
                    .foregroundStyle(theme.accent.opacity(0.6))
                    .padding(Edge.Set.horizontal, 6)
                contributorAvatar(
                    initial: String(partnerName.prefix(1)).uppercased(),
                    label: partnerName,
                    amount: partnerAmount,
                    isPending: partnerID == nil
                )
            }

            VStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: Alignment.leading) {
                        Rectangle().fill(theme.cardStroke)
                        Rectangle().fill(theme.accent).frame(width: geo.size.width * CGFloat(progress))
                    }
                }
                .frame(height: 4)
                .cornerRadius(2)

                HStack {
                    Text("$\(Int(combined)) combined")
                        .font(theme.font(11, weight: Font.Weight.semibold))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Text("of $\(Int(goal.targetAmount))")
                        .font(theme.font(11, weight: Font.Weight.semibold))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            if let code = sharedBudgetManager.share?.share_code, partnerID == nil {
                Rectangle().fill(theme.hairline).frame(height: 1)
                VStack(spacing: 8) {
                    SectionLabel("Share code")
                    HStack(spacing: 8) {
                        Text(code)
                            .font(theme.font(20, weight: Font.Weight.semibold))
                            .tracking(3)
                            .foregroundStyle(theme.textPrimary)
                        Button(action: {
                            UIPasteboard.general.string = code
                            showCopiedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showCopiedToast = false }
                        }) {
                            Image.platformSymbol("doc.on.doc", android: "square.and.arrow.up").foregroundStyle(theme.accent)
                        }
                    }
                    Text(showCopiedToast ? "Copied" : "Send this to your partner")
                        .font(theme.font(11))
                        .foregroundStyle(showCopiedToast ? theme.accent : theme.textTertiary)
                }
            }

            if !sharedBudgetManager.deposits.isEmpty {
                Rectangle().fill(theme.hairline).frame(height: 1)
                VStack(alignment: HorizontalAlignment.leading, spacing: 14) {
                    SectionLabel("Recent deposits")

                    VStack(spacing: 10) {
                        ForEach(sharedBudgetManager.deposits.prefix(6)) { deposit in
                            HStack {
                                Text(deposit.contributor_id == myID ? "You" : deposit.contributor_name)
                                    .font(theme.font(12, weight: Font.Weight.light))
                                    .foregroundStyle(theme.textPrimary.opacity(0.7))
                                Spacer()
                                Text("+$\(Int(deposit.amount))")
                                    .font(theme.font(12, weight: Font.Weight.semibold))
                                    .foregroundStyle(theme.accent)
                            }
                        }
                    }
                }
            }

            Rectangle().fill(theme.hairline).frame(height: 1)

            Button(role: ButtonRole.destructive, action: { showLeaveConfirm = true }) {
                Text("Leave this shared budget")
                    .font(theme.font(13, weight: Font.Weight.semibold))
                    .foregroundStyle(theme.danger.opacity(0.9))
            }
            .disabled(sharedBudgetManager.isLoading)
        }
        .padding(Layout.cardPadding)
        .background(cardFill)
        .cornerRadius(Layout.cardRadius)
        .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius).stroke(theme.cardStroke, lineWidth: 1))
        .padding(Edge.Set.horizontal, Layout.pageMargin)
        .confirmationDialog(
            isOwnerOfActiveShare ? "Leave and end this shared budget?" : "Leave this shared budget?",
            isPresented: $showLeaveConfirm,
            titleVisibility: Visibility.visible
        ) {
            Button("Leave", role: ButtonRole.destructive) { leaveSharedBudget(sharedID: sharedID) }
            Button("Cancel", role: ButtonRole.cancel) {}
        } message: {
            Text(isOwnerOfActiveShare
                ? "Since it's your goal, this ends the shared budget for both of you. Your partner will lose access next time they refresh."
                : "You'll stop seeing combined progress and deposits. \(sharedBudgetManager.share?.owner_name ?? "The owner") can invite someone else to your spot with the same code.")
        }
    }

    private var isOwnerOfActiveShare: Bool {
        sharedBudgetManager.share?.owner_id == myID
    }

    private func leaveSharedBudget(sharedID: String) {
        Task {
            let success = await sharedBudgetManager.leaveShare(sharedGoalID: sharedID, accessToken: authManager.accessToken)
            if success {
                goalStore.mutateActive { $0.sharedGoalID = nil }
                if let selectedTab {
                    selectedTab.wrappedValue = 0
                } else {
                    dismiss()
                }
            }
        }
    }

    private func contributorAvatar(initial: String, label: String, amount: Double, isPending: Bool = false) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(cardFill)
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(theme.accent.opacity(isPending ? 0.2 : 0.6), lineWidth: 1.5)
                    .frame(width: 64, height: 64)
                Text(initial)
                    .font(theme.font(22, weight: Font.Weight.light))
                    .foregroundStyle(isPending ? theme.textTertiary : theme.textPrimary)
            }
            Text(label)
                .font(theme.font(11, weight: Font.Weight.semibold))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
            Text(isPending ? "—" : "$\(Int(amount))")
                .font(theme.font(15, weight: Font.Weight.semibold))
                .foregroundStyle(theme.accent)
        }
        .frame(maxWidth: CGFloat.infinity)
    }

    // MARK: - Join someone else's shared budget
    private var joinCard: some View {
        VStack(spacing: 12) {
            SectionLabel("Join a shared budget")

            HStack(spacing: 10) {
                TextField("Enter their code", text: $joinCodeInput)
                    .textInputAutocapitalization(TextInputAutocapitalization.characters)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(cardFill)
                    .cornerRadius(14)
                    .foregroundStyle(theme.textPrimary)

                Button(action: {
                    Task {
                        if let record = await sharedBudgetManager.joinShare(code: joinCodeInput, partnerName: myName, accessToken: authManager.accessToken) {
                            goalStore.addGoal(
                                title: record.goal_title,
                                kindRaw: GoalKind.custom.rawValue,
                                targetAmount: record.target_amount,
                                targetDate: Calendar.current.date(byAdding: Calendar.Component.month, value: 3, to: Date()) ?? Date()
                            )
                            goalStore.mutateActive { $0.sharedGoalID = record.id }
                            await sharedBudgetManager.loadShare(id: record.id, accessToken: authManager.accessToken)
                            joinCodeInput = ""
                        }
                    }
                }) {
                    Text("Join")
                        .font(theme.font(14, weight: Font.Weight.semibold))
                        .padding(Edge.Set.horizontal, 20)
                        .padding(Edge.Set.vertical, 16)
                        .background(theme.accent)
                        .foregroundColor(theme.onAccent)
                        .cornerRadius(Layout.controlRadius)
                }
                .disabled(joinCodeInput.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty || sharedBudgetManager.isLoading)
            }
        }
        .padding(Edge.Set.horizontal, Layout.pageMargin)
    }
}
