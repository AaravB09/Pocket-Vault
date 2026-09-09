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
                VStack(spacing: 24.0) {
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
                        .padding(Edge.Set.top, 20.0)
                    } else {
                        Color.clear.frame(height: 8.0)
                    }

                    VStack(spacing: 6.0) {
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
        VStack(spacing: 14.0) {
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

            // MIGRATED: PrimaryCTAButton (Thememanager.swift) → VaultButton.
            // VaultButton's own isLoading param already swaps in a
            // ProgressView and fades the label — no need for the manual
            // HStack + ternary label text PrimaryCTAButton needed.
            VaultButton(
                "Share this goal",
                variant: .primary,
                isLoading: sharedBudgetManager.isLoading
            ) {
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
            }
        }
        .padding(Layout.cardPadding)
        .background(cardFill)
        .cornerRadius(Layout.cardRadius)
        .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius).stroke(Color.clear, lineWidth: 1.0))
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

        return VStack(spacing: 26.0) {
            HStack(spacing: 0.0) {
                contributorAvatar(initial: "Y", label: "You", amount: mine)
                Image.platformSymbol("arrow.left.arrow.right", android: "arrow.clockwise.circle")
                    .font(theme.font(12))
                    .foregroundStyle(theme.accent.opacity(0.6))
                    .padding(Edge.Set.horizontal, 6.0)
                contributorAvatar(
                    initial: String(partnerName.prefix(1)).uppercased(),
                    label: partnerName,
                    amount: partnerAmount,
                    isPending: partnerID == nil
                )
            }

            VStack(spacing: 10.0) {
                GeometryReader { geo in
                    ZStack(alignment: Alignment.leading) {
                        Rectangle().fill(theme.cardStroke)
                        Rectangle().fill(theme.accent).frame(width: geo.size.width * CGFloat(progress))
                    }
                }
                .frame(height: 4.0)
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
                Rectangle().fill(theme.hairline).frame(height: 1.0)
                VStack(spacing: 8.0) {
                    SectionLabel("Share code")
                    HStack(spacing: 8.0) {
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
                Rectangle().fill(theme.hairline).frame(height: 1.0)
                VStack(alignment: HorizontalAlignment.leading, spacing: 14.0) {
                    SectionLabel("Recent deposits")

                    VStack(spacing: 10.0) {
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

            Rectangle().fill(theme.hairline).frame(height: 1.0)

            // MIGRATED: raw Button(role: .destructive) → VaultButton.
            // This was always a plain text link (no fill), not a filled
            // CTA — .destructive is VaultButton's solid red-fill variant,
            // which would visibly redesign this into a bold button rather
            // than just fixing its shape. .tertiary keeps the "no fill,
            // no stroke" text-link look; the label itself still sets
            // theme.danger explicitly, and that wins over VaultButton's
            // default tertiary text color since it's the closer/child
            // modifier. fullWidth: false preserves the original's
            // intrinsic (non-stretched) width.
            VaultButton(
                variant: .tertiary,
                fullWidth: false,
                action: { showLeaveConfirm = true },
                label: AnyView(
                    Text("Leave this shared budget")
                        .font(theme.font(13, weight: Font.Weight.semibold))
                        .foregroundStyle(theme.danger.opacity(0.9))
                )
            )
            .disabled(sharedBudgetManager.isLoading)
        }
        .padding(Layout.cardPadding)
        .background(cardFill)
        .cornerRadius(Layout.cardRadius)
        .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius).stroke(Color.clear, lineWidth: 1.0))
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
        VStack(spacing: 8.0) {
            ZStack {
                Circle()
                    .fill(cardFill)
                    .frame(width: 64.0, height: 64.0)
                Circle()
                    .stroke(theme.accent.opacity(isPending ? 0.2 : 0.6), lineWidth: 1.5)
                    .frame(width: 64.0, height: 64.0)
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
        VStack(spacing: 12.0) {
            SectionLabel("Join a shared budget")

            HStack(spacing: 10.0) {
                TextField("Enter their code", text: $joinCodeInput)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(TextInputAutocapitalization.characters)
                    .autocorrectionDisabled()
                    .padding(14.0)
                    .background(cardFill)
                    .cornerRadius(14)
                    .foregroundStyle(theme.textPrimary)

                // MIGRATED: raw Button with its own one-off
                // padding/background/cornerRadius(Layout.controlRadius) →
                // VaultButton. This was exactly the kind of bespoke
                // button-shape duplication the shared-constants pass is
                // meant to eliminate — it already reached for the right
                // radius token but hand-rolled its own fill/shape/plain
                // `.cornerRadius()` instead of getting them from one
                // place. fullWidth: false since it sits beside the text
                // field rather than spanning the row.
                VaultButton(
                    "Join",
                    variant: .primary,
                    isLoading: sharedBudgetManager.isLoading,
                    fontSize: 14.0,
                    fullWidth: false
                ) {
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
                }
                .disabled(joinCodeInput.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty)
            }
        }
        .padding(Edge.Set.horizontal, Layout.pageMargin)
    }
}
