import Foundation
import Combine

// MARK: - Model

enum SpendCategory: String, Codable, CaseIterable, Identifiable {
    case food, transport, shopping, bills, subscriptions, entertainment, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .food: return "Food"
        case .transport: return "Transport"
        case .shopping: return "Shopping"
        case .bills: return "Bills"
        case .subscriptions: return "Subscriptions"
        case .entertainment: return "Fun"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .shopping: return "bag.fill"
        case .bills: return "doc.text.fill"
        case .subscriptions: return "repeat.circle.fill"
        case .entertainment: return "popcorn.fill"
        case .other: return "circle.grid.2x2.fill"
        }
    }

    /// Maps Plaid's personal_finance_category.primary values onto our
    /// simpler set. Anything unrecognized falls back to .other rather
    /// than crashing the decode.
    static func fromPlaid(_ raw: String?) -> SpendCategory {
        switch raw?.uppercased() {
        case "FOOD_AND_DRINK": return .food
        case "TRANSPORTATION": return .transport
        case "GENERAL_MERCHANDISE", "SHOPPING": return .shopping
        case "RENT_AND_UTILITIES", "LOAN_PAYMENTS", "BILLS": return .bills
        case "ENTERTAINMENT", "PERSONAL_CARE": return .entertainment
        case "SUBSCRIPTIONS": return .subscriptions
        default: return .other
        }
    }
}

struct SpendTransaction: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var amount: Double
    var category: SpendCategory
    var note: String
    var date: Date
    /// nil for manually-logged entries. Set for anything pulled in via
    /// Plaid — this is the dedup key so a repeat sync doesn't double-count.
    var plaidTransactionID: String? = nil
    var isAutoImported: Bool { plaidTransactionID != nil }
}

enum BudgetStatus { case onTrack, approaching, over }

// MARK: - BudgetManager

@MainActor
final class BudgetManager: ObservableObject {
    @Published var monthlyLimit: Double { didSet { persist() } }
    @Published var transactions: [SpendTransaction] = [] { didSet { persist() } }
    @Published var justCrossedThreshold: BudgetStatus?

    private let defaults = UserDefaults.standard
    private let limitKey: String
    private let transactionsKey: String
    private var lastKnownStatus: BudgetStatus = .onTrack
    private var calendar: Calendar { Calendar.current }

    init(namespace: String) {
        limitKey = "\(namespace)_pv_budgetLimit_v1"
        transactionsKey = "\(namespace)_pv_budgetTransactions_v1"

        monthlyLimit = defaults.object(forKey: limitKey) != nil ? defaults.double(forKey: limitKey) : 500.0

        if let data = defaults.data(forKey: transactionsKey),
           let decoded = try? JSONDecoder().decode([SpendTransaction].self, from: data) {
            transactions = decoded
        }
        lastKnownStatus = status
    }

    var transactionsThisMonth: [SpendTransaction] {
        transactions.filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: Calendar.Component.month) }
            .sorted { $0.date > $1.date }
    }

    var totalSpentThisMonth: Double { transactionsThisMonth.reduce(0.0) { $0 + $1.amount } }
    var remaining: Double { max(monthlyLimit - totalSpentThisMonth, 0.0) }
    var percentUsed: Double { monthlyLimit > 0.0 ? min(totalSpentThisMonth / monthlyLimit, 1.5) : 0.0 }

    var status: BudgetStatus {
        guard monthlyLimit > 0.0 else { return .onTrack }
        let ratio = totalSpentThisMonth / monthlyLimit
        if ratio >= 1.0 { return .over }
        if ratio >= 0.8 { return .approaching }
        return .onTrack
    }

    func totalSpent(in category: SpendCategory) -> Double {
        transactionsThisMonth.filter { $0.category == category }.reduce(0.0) { $0 + $1.amount }
    }

    var transactionsByDay: [(date: Date, items: [SpendTransaction])] {
        var grouped = [Date: [SpendTransaction]]()
        
        for transaction in transactionsThisMonth {
            let day = calendar.startOfDay(for: transaction.date)
            grouped[day, default: [SpendTransaction]()].append(transaction)
        }
        
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day]!.sorted { $0.date > $1.date })
        }
    }

    // MARK: - Manual entry

    func addTransaction(amount: Double, category: SpendCategory, note: String, date: Date = Date()) {
        guard amount > 0.0 else { return }
        transactions.append(SpendTransaction(amount: amount, category: category, note: note, date: date))
        evaluateThresholdChange()
    }

    func deleteTransaction(_ id: UUID) {
        transactions.removeAll { $0.id == id }
        evaluateThresholdChange()
    }

    func setLimit(_ newLimit: Double) {
        guard newLimit >= 0.0 else { return }
        monthlyLimit = newLimit
        evaluateThresholdChange()
    }

    // MARK: - Auto-imported entries (Plaid)

    /// Merges bank-synced rows in, skipping any `plaidTransactionID`
    /// already present so re-syncing (app launch, pull-to-refresh) never
    /// creates duplicates. Call from PlaidConnectionManager after a sync.
    func mergeImportedTransactions(_ rows: [PlaidTransactionRow]) {
        let existingIDs = Set(transactions.compactMap { $0.plaidTransactionID })
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [ISO8601DateFormatter.Options.withFullDate]

        var added = 0
        for row in rows where !existingIDs.contains(row.plaid_transaction_id) {
            let date = formatter.date(from: row.date) ?? Date()
            let entry = SpendTransaction(
                amount: row.amount,
                category: SpendCategory.fromPlaid(row.category),
                note: row.merchant_name ?? "Bank transaction",
                date: date,
                plaidTransactionID: row.plaid_transaction_id
            )
            transactions.append(entry)
            added += 1
        }
        if added > 0 { evaluateThresholdChange() }
    }

    private func evaluateThresholdChange() {
        let newStatus = status
        let worsened: Bool
        switch (lastKnownStatus, newStatus) {
        case (.onTrack, .approaching), (.onTrack, .over), (.approaching, .over): worsened = true
        default: worsened = false
        }
        if worsened { justCrossedThreshold = newStatus }
        lastKnownStatus = newStatus
    }

    private func persist() {
        defaults.set(monthlyLimit, forKey: limitKey)
        if let data = try? JSONEncoder().encode(transactions) {
            defaults.set(data, forKey: transactionsKey)
        }
    }
}
