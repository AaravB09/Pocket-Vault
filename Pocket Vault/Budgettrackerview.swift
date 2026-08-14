import SwiftUI

/// Manual spend tracker: set a monthly limit, log payments/expenses as
/// you make them, and get a clear alert as you approach or blow past
/// the limit. Reuses the theme system so it matches whatever
/// color/appearance the user has picked in Profile.
struct BudgetTrackerView: View {
    @EnvironmentObject var budgetManager: BudgetManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var privacy: PrivacyManager

    @State private var showAddSheet: Bool = false
    @State private var showLimitEditor: Bool = false
    @State private var limitInput: String = ""

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header

                    if let alertStatus = budgetManager.justCrossedThreshold {
                        alertBanner(for: alertStatus)
                    }

                    progressCard

                    // Bank sync — lets Pro users auto-import spending via
                    // Plaid instead of logging every payment by hand.
                    // (Free/guest users see an upsell card instead.)
                    BudgetBankSyncSection(budgetManager: budgetManager)
                        .padding(.horizontal, 24)

                    categoryBreakdown

                    transactionHistory
                }
                .padding(.bottom, 130)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddPaymentSheet()
                .environmentObject(budgetManager)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showLimitEditor) {
            LimitEditorSheet(limitInput: $limitInput)
                .environmentObject(budgetManager)
                .environmentObject(theme)
        }
        .onAppear { limitInput = "\(Int(budgetManager.monthlyLimit))" }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("SPENDING")
                .font(theme.font(10, weight: .bold))
                .tracking(3)
                .foregroundStyle(theme.accent)
            Text("Budget Tracker")
                .font(theme.font(22, weight: .light))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.top, 60)
    }

    // MARK: - Alert banner

    private func alertBanner(for status: BudgetStatus) -> some View {
        let (icon, color, message): (String, Color, String) = {
            switch status {
            case .over:
                return ("exclamationmark.triangle.fill", theme.danger, "You've gone over your $\(Int(budgetManager.monthlyLimit)) limit this month.")
            case .approaching:
                return ("exclamationmark.circle.fill", theme.warning, "You've used 80%+ of your $\(Int(budgetManager.monthlyLimit)) limit this month.")
            case .onTrack:
                return ("checkmark.circle.fill", theme.success, "Back on track.")
            }
        }()

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(theme.font(16, weight: .bold))
                .foregroundStyle(color)
            Text(message)
                .font(theme.font(12, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: { withAnimation { budgetManager.justCrossedThreshold = nil } }) {
                Image(systemName: "xmark")
                    .font(theme.font(11, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(16)
        .background(color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.5), lineWidth: 1.2))
        .padding(.horizontal, 24)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Progress card

    private var statusColor: Color {
        switch budgetManager.status {
        case .onTrack: return theme.success
        case .approaching: return theme.warning
        case .over: return theme.danger
        }
    }

    private var progressCard: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SPENT THIS MONTH")
                        .font(theme.font(9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(theme.textTertiary)
                    Text("$\(Int(budgetManager.totalSpentThisMonth))")
                        .font(theme.font(34, weight: .light))
                        .foregroundStyle(theme.textPrimary)
                }
                Spacer()
                Button(action: { showLimitEditor = true }) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("LIMIT")
                            .font(theme.font(9, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(theme.textTertiary)
                        HStack(spacing: 4) {
                            Text("$\(Int(budgetManager.monthlyLimit))")
                                .font(theme.font(16, weight: .semibold))
                                .foregroundStyle(theme.accent)
                            Image(systemName: "pencil")
                                .font(theme.font(10, weight: .bold))
                                .foregroundStyle(theme.accent)
                        }
                    }
                }
            }
            .blur(radius: privacy.shouldMask ? 10 : 0)
            .overlay {
                if privacy.shouldMask {
                    PrivacyRevealOverlay()
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline)
                    Capsule()
                        .fill(statusColor)
                        .frame(width: geo.size.width * CGFloat(min(budgetManager.percentUsed, 1.0)))
                }
            }
            .frame(height: 10)

            HStack {
                Text("\(Int(min(budgetManager.percentUsed, 1.5) * 100))% used")
                    .font(theme.font(11, weight: .semibold))
                    .foregroundStyle(statusColor)
                Spacer()
                Text(budgetManager.status == .over ? "OVER BY $\(Int(budgetManager.totalSpentThisMonth - budgetManager.monthlyLimit))" : "$\(Int(budgetManager.remaining)) LEFT")
                    .font(theme.font(10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(theme.textTertiary)
            }
            .blur(radius: privacy.shouldMask ? 6 : 0)

            Button(action: { showAddSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("LOG A PAYMENT")
                }
            }
            .buttonStyle(.primaryCTA(theme))
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1))
        .padding(.horizontal, 24)
    }

    // MARK: - Category breakdown

    private var categoryBreakdown: some View {
        let nonZero = SpendCategory.allCases
            .map { ($0, budgetManager.totalSpent(in: $0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }

        return Group {
            if !nonZero.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("BY CATEGORY")
                        .font(theme.font(9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 24)

                    VStack(spacing: 10) {
                        ForEach(nonZero, id: \.0) { category, amount in
                            HStack(spacing: 12) {
                                Image(systemName: category.icon)
                                    .font(theme.font(13))
                                    .foregroundStyle(theme.accent)
                                    .frame(width: 26)
                                Text(category.displayName)
                                    .font(theme.font(12, weight: .medium))
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                                Text("$\(Int(amount))")
                                    .font(theme.font(13, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(theme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    // MARK: - Transaction history

    private var transactionHistory: some View {
        Group {
            if budgetManager.transactionsThisMonth.isEmpty {
                Text("No payments logged yet this month. Tap \u{201C}Log a Payment\u{201D} above to start tracking.")
                    .font(theme.font(13, weight: .light))
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(budgetManager.transactionsByDay, id: \.date) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(dayLabel(day.date))
                                .font(theme.font(9, weight: .bold))
                                .tracking(1.5)
                                .foregroundStyle(theme.textTertiary)
                                .padding(.horizontal, 24)

                            VStack(spacing: 8) {
                                ForEach(day.items) { item in
                                    transactionRow(item)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }
            }
        }
    }

    private func transactionRow(_ item: SpendTransaction) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.15)).frame(width: 34, height: 34)
                Image(systemName: item.category.icon)
                    .font(theme.font(13))
                    .foregroundStyle(theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.note.isEmpty ? item.category.displayName : item.note)
                        .font(theme.font(13, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    // Marks bank-synced entries so it's obvious which
                    // rows came in automatically vs. were typed by hand.
                    if item.isAutoImported {
                        Image(systemName: "building.columns.fill")
                            .font(theme.font(9))
                            .foregroundStyle(theme.accent.opacity(0.7))
                    }
                }
                Text(timeLabel(item.date))
                    .font(theme.font(10, weight: .light))
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
            Text("-$\(Int(item.amount))")
                .font(theme.font(13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation { budgetManager.deleteTransaction(item.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "TODAY" }
        if Calendar.current.isDateInYesterday(date) { return "YESTERDAY" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date).uppercased()
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Add Payment Sheet

private struct AddPaymentSheet: View {
    @EnvironmentObject var budgetManager: BudgetManager
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) var dismiss

    @State private var amountText: String = ""
    @State private var selectedCategory: SpendCategory = .food
    @State private var note: String = ""

    private var isValid: Bool {
        guard let value = Double(amountText) else { return false }
        return value > 0
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            ScrollView {
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
                        Text("LOG PAYMENT")
                            .font(theme.font(10, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(theme.accent)
                        Text("What did you spend?")
                            .font(theme.font(20, weight: .light))
                            .foregroundStyle(theme.textPrimary)
                    }

                    VStack(spacing: 6) {
                        Text("AMOUNT ($)")
                            .font(theme.font(9, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(theme.textTertiary)
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(theme.font(44, weight: .light))
                            .foregroundStyle(theme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("CATEGORY")
                            .font(theme.font(9, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(theme.textTertiary)
                            .padding(.horizontal, 24)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 10) {
                            ForEach(SpendCategory.allCases) { category in
                                Button(action: { selectedCategory = category }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: category.icon)
                                            .font(theme.font(16))
                                        Text(category.displayName)
                                            .font(theme.font(10, weight: .bold))
                                    }
                                    .foregroundStyle(selectedCategory == category ? .black : theme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(selectedCategory == category ? theme.accent : (theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06)))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.accent.opacity(selectedCategory == category ? 0 : 0.25), lineWidth: 1))
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOTE (OPTIONAL)")
                            .font(theme.font(9, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(theme.textTertiary)

                        TextField("e.g. Grocery run", text: $note)
                            .foregroundStyle(theme.textPrimary)
                            .padding(14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))
                    }
                    .padding(.horizontal, 24)

                    Button(action: {
                        guard let amount = Double(amountText) else { return }
                        budgetManager.addTransaction(amount: amount, category: selectedCategory, note: note)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    }) {
                        Text("SAVE PAYMENT")
                    }
                    .buttonStyle(.primaryCTA(theme))
                    .disabled(!isValid)
                    .opacity(isValid ? 1.0 : 0.4)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 50)
                }
            }
        }
    }
}

// MARK: - Limit Editor Sheet

private struct LimitEditorSheet: View {
    @EnvironmentObject var budgetManager: BudgetManager
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) var dismiss
    @Binding var limitInput: String

    private var isValid: Bool {
        guard let value = Double(limitInput) else { return false }
        return value >= 0
    }

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

                VStack(spacing: 4) {
                    Text("MONTHLY LIMIT")
                        .font(theme.font(10, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(theme.accent)
                    Text("Set your spending cap")
                        .font(theme.font(20, weight: .light))
                        .foregroundStyle(theme.textPrimary)
                }

                TextField("500", text: $limitInput)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(theme.font(52, weight: .light))
                    .foregroundStyle(theme.textPrimary)

                Text("You'll get an alert here once you cross 80% and again if you go over.")
                    .font(theme.font(12, weight: .light))
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()

                Button(action: {
                    guard let value = Double(limitInput) else { return }
                    budgetManager.setLimit(value)
                    dismiss()
                }) {
                    Text("SAVE LIMIT")
                }
                .buttonStyle(.primaryCTA(theme))
                .disabled(!isValid)
                .opacity(isValid ? 1.0 : 0.4)
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
        }
    }
}
