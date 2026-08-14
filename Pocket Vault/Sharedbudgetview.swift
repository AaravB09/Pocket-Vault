import SwiftUI

struct SharedBudgetView: View {
    @EnvironmentObject var sharedBudgetManager: SharedBudgetManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var goalStore: GoalStore
    @Environment(\.dismiss) var dismiss

    @State private var joinCodeInput: String = ""
    @State private var showCopiedToast: Bool = false

    private var myID: String { authManager.userID ?? leaderboardManager.myUserID }
    private var myName: String { leaderboardManager.myDisplayName }

    var body: some View {
        if authManager.isGuest {
            AccountRequiredGateView(featureName: "Shared Budget")
        } else {
            content
        }
    }

    private var content: some View {
        ZStack {
            theme.background.ignoresSafeArea()

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
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    VStack(spacing: 4) {
                        Text("SHARED BUDGET")
                            .font(theme.font(10, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(theme.accent)
                        Text("Save Together")
                            .font(theme.font(22, weight: .light))
                            .foregroundStyle(theme.textPrimary)
                    }

                    if let goal = goalStore.activeGoal, let sharedID = goal.sharedGoalID {
                        sharedGoalCard(goal: goal, sharedID: sharedID)
                    } else if let goal = goalStore.activeGoal {
                        shareThisGoalCard(goal: goal)
                    } else {
                        Text("Create a goal first, then come back to share it.")
                            .font(theme.font(13, weight: .light))
                            .foregroundStyle(theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }

                    joinCard

                    if let errorMessage = sharedBudgetManager.errorMessage {
                        Text(errorMessage)
                            .font(theme.font(11))
                            .foregroundStyle(theme.danger.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
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
        .task {
            if let sharedID = goalStore.activeGoal?.sharedGoalID {
                await sharedBudgetManager.loadShare(id: sharedID, accessToken: authManager.accessToken)
            }
        }
    }

    // MARK: - Active goal isn't shared yet
    private func shareThisGoalCard(goal: Goal) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.fill")
                .font(theme.font(26, weight: .light))
                .foregroundStyle(theme.accent)

            Text("Share “\(goal.title)” with a partner")
                .font(theme.font(14, weight: .light))
                .foregroundStyle(theme.textPrimary.opacity(0.7))
                .multilineTextAlignment(.center)

            Text("You'll both see every deposit and how close you are together.")
                .font(theme.font(12, weight: .light))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)

            Button(action: {
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
                    Text(sharedBudgetManager.isLoading ? "PLEASE WAIT…" : "SHARE THIS GOAL")
                        .font(theme.font(13, weight: .bold))
                        .tracking(2.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 19)
                .background(theme.accent)
                .foregroundColor(theme.onAccent)
                .clipShape(Capsule())
                .shadow(color: theme.accent.opacity(0.5), radius: 18, y: 8)
            }
            .disabled(sharedBudgetManager.isLoading)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1))
        .padding(.horizontal, 24)
    }

    // MARK: - Already shared: split-avatar card
    private func sharedGoalCard(goal: Goal, sharedID: String) -> some View {
        let mine = sharedBudgetManager.contributed(by: myID)
        let partnerID = sharedBudgetManager.share?.partner_id
        let partnerAmount = partnerID.map { sharedBudgetManager.contributed(by: $0) } ?? 0
        let partnerName = sharedBudgetManager.share?.partner_name ?? "Waiting for partner"
        let combined = mine + partnerAmount
        let progress = min(max(combined / max(goal.targetAmount, 1), 0), 1)

        return VStack(spacing: 20) {
            HStack(spacing: 0) {
                contributorAvatar(initial: "Y", label: "You", amount: mine)
                Image(systemName: "arrow.left.arrow.right")
                    .font(theme.font(12))
                    .foregroundStyle(theme.accent.opacity(0.6))
                    .padding(.horizontal, 6)
                contributorAvatar(
                    initial: String(partnerName.prefix(1)).uppercased(),
                    label: partnerName,
                    amount: partnerAmount,
                    isPending: partnerID == nil
                )
            }

            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(theme.cardStroke)
                        Rectangle().fill(theme.accent).frame(width: geo.size.width * CGFloat(progress))
                    }
                }
                .frame(height: 4)
                .clipShape(Capsule())

                HStack {
                    Text("$\(Int(combined)) COMBINED")
                        .font(theme.font(9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Text("OF $\(Int(goal.targetAmount))")
                        .font(theme.font(9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            if let code = sharedBudgetManager.share?.share_code, partnerID == nil {
                VStack(spacing: 8) {
                    Text("SHARE CODE")
                        .font(theme.font(9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(theme.textTertiary)
                    HStack(spacing: 8) {
                        Text(code)
                            .font(theme.font(20, weight: .semibold))
                            .tracking(3)
                            .foregroundStyle(theme.textPrimary)
                        Button(action: {
                            UIPasteboard.general.string = code
                            showCopiedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showCopiedToast = false }
                        }) {
                            Image(systemName: "doc.on.doc").foregroundStyle(theme.accent)
                        }
                    }
                    Text(showCopiedToast ? "Copied" : "Send this to your partner")
                        .font(theme.font(11))
                        .foregroundStyle(showCopiedToast ? theme.accent : theme.textTertiary)
                }
            }

            if !sharedBudgetManager.deposits.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("RECENT DEPOSITS")
                        .font(theme.font(9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(theme.accent)

                    ForEach(sharedBudgetManager.deposits.prefix(6)) { deposit in
                        HStack {
                            Text(deposit.contributor_id == myID ? "You" : deposit.contributor_name)
                                .font(theme.font(12, weight: .light))
                                .foregroundStyle(theme.textPrimary.opacity(0.7))
                            Spacer()
                            Text("+$\(Int(deposit.amount))")
                                .font(theme.font(12, weight: .semibold))
                                .foregroundStyle(theme.accent)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1))
        .padding(.horizontal, 24)
    }

    private func contributorAvatar(initial: String, label: String, amount: Double, isPending: Bool = false) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(theme.accent.opacity(isPending ? 0.2 : 0.6), lineWidth: 1.5)
                    .frame(width: 64, height: 64)
                Text(initial)
                    .font(theme.font(22, weight: .light))
                    .foregroundStyle(isPending ? theme.textTertiary : theme.textPrimary)
            }
            Text(label)
                .font(theme.font(10, weight: .bold))
                .tracking(1)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
            Text(isPending ? "—" : "$\(Int(amount))")
                .font(theme.font(15, weight: .semibold))
                .foregroundStyle(theme.accent)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Join someone else's shared budget
    private var joinCard: some View {
        VStack(spacing: 12) {
            Text("JOIN A SHARED BUDGET")
                .font(theme.font(9, weight: .bold))
                .tracking(2)
                .foregroundStyle(theme.textTertiary)

            HStack(spacing: 10) {
                TextField("Enter their code", text: $joinCodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(theme.textPrimary)

                Button(action: {
                    Task {
                        if let record = await sharedBudgetManager.joinShare(code: joinCodeInput, partnerName: myName, accessToken: authManager.accessToken) {
                            goalStore.addGoal(
                                title: record.goal_title,
                                kindRaw: GoalKind.custom.rawValue,
                                targetAmount: record.target_amount,
                                targetDate: Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
                            )
                            goalStore.mutateActive { $0.sharedGoalID = record.id }
                            await sharedBudgetManager.loadShare(id: record.id, accessToken: authManager.accessToken)
                            joinCodeInput = ""
                        }
                    }
                }) {
                    Text("JOIN")
                        .font(theme.font(12, weight: .bold))
                        .tracking(1.5)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(theme.accent)
                        .foregroundColor(theme.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: theme.accent.opacity(0.35), radius: 10, y: 4)
                }
                .disabled(joinCodeInput.trimmingCharacters(in: .whitespaces).isEmpty || sharedBudgetManager.isLoading)
            }
        }
        .padding(.horizontal, 24)
    }
}
