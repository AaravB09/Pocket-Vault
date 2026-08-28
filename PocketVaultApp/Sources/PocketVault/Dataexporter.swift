import Foundation

/// Turns the user's own on-device data into plain CSV files they can
/// save, email, or move into another app — no server round-trip, no
/// account required, and not gated behind Pro. Everything it reads
/// (GoalStore, BudgetManager) already lives entirely in UserDefaults;
/// this just makes it portable on request instead of trapped in the app.
enum DataExporter {
    private static var isoFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = ISO8601DateFormatter.Options.withInternetDateTime
        return formatter
    }

    // MARK: - JSON
    //
    // The structured, lossless counterpart to the CSV export below —
    // whichever another app or script expects, the user isn't stuck
    // re-typing their history to switch tools.

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = JSONEncoder.DateEncodingStrategy.iso8601
        encoder.outputFormatting = [JSONEncoder.OutputFormatting.prettyPrinted, JSONEncoder.OutputFormatting.sortedKeys]
        return encoder
    }

    static func goalsJSON(_ goals: [Goal]) -> String {
        guard let data = try? jsonEncoder.encode(goals), let string = String(data: data, encoding: String.Encoding.utf8) else {
            return "[]"
        }
        return string
    }

    static func transactionsJSON(_ transactions: [SpendTransaction]) -> String {
        let sorted = transactions.sorted { $0.date < $1.date }
        guard let data = try? jsonEncoder.encode(sorted), let string = String(data: data, encoding: String.Encoding.utf8) else {
            return "[]"
        }
        return string
    }

    // MARK: - CSV

    static func goalsCSV(_ goals: [Goal]) -> String {
        var lines = ["Goal,Target Amount,Current Savings,Target Date,Snapshot Date,Snapshot Amount"]
        for goal in goals {
            let base = "\(csvEscape(goal.title)),\(goal.targetAmount),\(goal.currentSavings),\(isoFormatter.string(from: goal.targetDate))"
            let history = goal.history.sorted { $0.date < $1.date }
            if history.isEmpty {
                lines.append("\(base),,")
            } else {
                for snapshot in history {
                    lines.append("\(base),\(isoFormatter.string(from: snapshot.date)),\(snapshot.amount)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func transactionsCSV(_ transactions: [SpendTransaction]) -> String {
        var lines = ["Date,Category,Amount,Note,Source"]
        for transaction in transactions.sorted(by: { $0.date < $1.date }) {
            let source = transaction.isAutoImported ? "Bank Sync" : "Manual"
            lines.append("\(isoFormatter.string(from: transaction.date)),\(transaction.category.displayName),\(transaction.amount),\(csvEscape(transaction.note)),\(source)")
        }
        return lines.joined(separator: "\n")
    }

    /// Writes a CSV string to a temp file and returns its URL, ready to
    /// hand to a ShareLink so the user picks where it actually goes
    /// (Files, Mail, AirDrop, another app, etc).
    static func writeTempFile(_ contents: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try contents.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
