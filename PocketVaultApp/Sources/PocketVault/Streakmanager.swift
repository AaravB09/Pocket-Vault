import Foundation
import Combine

/// Tracks the user's daily-deposit streak. Call `recordDeposit()` any time
/// money is added to a goal. Call `evaluateStreakOnLaunch()` once at app
/// start (done automatically in `init`) so a streak silently expires if the
/// user skipped a day, using a "streak freeze" grace period like Duolingo.
final class StreakManager: ObservableObject {
    @Published var currentStreak: Int
    @Published var longestStreak: Int
    @Published var lastDepositDate: Date?
    @Published var streakFreezesAvailable: Int
    @Published var justExtendedStreak: Bool = false

    private let defaults = UserDefaults.standard
    private let streakKey: String
    private let longestKey: String
    private let lastDateKey: String
    private let freezesKey: String

    private var calendar: Calendar { Calendar.current }

    /// `namespace` isolates one account's (or one guest session's) streak
    /// from every other — see AuthManager.storageNamespace. Without this,
    /// signing out and continuing as a guest would show whatever streak
    /// the previous signed-in account had.
    init(namespace: String) {
        streakKey = "\(namespace)_pv_currentStreak"
        longestKey = "\(namespace)_pv_longestStreak"
        lastDateKey = "\(namespace)_pv_lastDepositDate"
        freezesKey = "\(namespace)_pv_streakFreezes"

        currentStreak = defaults.integer(forKey: streakKey)
        longestStreak = defaults.integer(forKey: longestKey)
        lastDepositDate = defaults.object(forKey: lastDateKey) as? Date
        streakFreezesAvailable = defaults.object(forKey: freezesKey) != nil
            ? defaults.integer(forKey: freezesKey)
            : 2 // new users start with 2 free freezes
        evaluateStreakOnLaunch()
    }

    /// Call once on app launch. If more than one full day has passed since
    /// the last deposit, either spend a freeze or reset the streak to zero.
    func evaluateStreakOnLaunch() {
        guard let last = lastDepositDate else { return }
        let daysSince = calendar.dateComponents(
            [Calendar.Component.day],
            from: calendar.startOfDay(for: last),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0

        guard daysSince > 1 else { return }

        if streakFreezesAvailable > 0 && daysSince == 2 {
            streakFreezesAvailable -= 1
        } else {
            currentStreak = 0
        }
        persist()
    }

    /// Call whenever the user deposits money toward any goal.
    func recordDeposit() {
        let today = calendar.startOfDay(for: Date())

        if let last = lastDepositDate {
            let lastDay = calendar.startOfDay(for: last)
            let daysSince = calendar.dateComponents([Calendar.Component.day], from: lastDay, to: today).day ?? 0

            switch daysSince {
            case 0:
                break // already deposited today — streak unchanged
            case 1:
                currentStreak += 1
                justExtendedStreak = true
            default:
                currentStreak = 1
                justExtendedStreak = true
            }
        } else {
            currentStreak = 1
            justExtendedStreak = true
        }

        lastDepositDate = Date()
        longestStreak = max(longestStreak, currentStreak)
        persist()
    }

    private func persist() {
        defaults.set(currentStreak, forKey: streakKey)
        defaults.set(longestStreak, forKey: longestKey)
        defaults.set(lastDepositDate, forKey: lastDateKey)
        defaults.set(streakFreezesAvailable, forKey: freezesKey)
    }
}
