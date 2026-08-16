import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var theme: ThemeManager
    @StateObject private var calendarSync = CalendarSyncManager()

    @Binding var currentSavings: Double
    @Binding var targetGoal: Double
    @Binding var goalTitle: String

    @State private var selectedDate: Date = Date()
    private let calendar = Calendar.current

    var remainingAmount: Double {
        max(targetGoal - currentSavings, 0.0)
    }

    var completionPercentage: Double {
        min(max(currentSavings / max(targetGoal, 1.0), 0.0), 1.0)
    }

    // Estimated target date based on streak momentum. Split into a raw
    // Date (used for the Apple Calendar export) and a formatted string
    // (used for display) so both stay in sync from one calculation.
    var estimatedCompletionDateValue: Date? {
        let dailyPace = currentSavings / max(Double(streakManager.currentStreak), 1.0)
        let daysLeft = dailyPace > 0 ? Int(ceil(remainingAmount / dailyPace)) : 30
        return calendar.date(byAdding: .day, value: daysLeft, to: Date())
    }

    var estimatedCompletionDate: String {
        guard let date = estimatedCompletionDateValue else { return "In Progress" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header Title
                    ScreenHeader("Calendar", subtitle: "Deposit streaks & forecast")
                        .padding(.top, 40)

                    // MARK: - Streak Stats Grid
                    HStack(spacing: 12) {
                        // Current Streak Card
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "flame.fill")
                                    .foregroundStyle(theme.accent)
                                SectionLabel("Active streak")
                            }

                            Text("\(streakManager.currentStreak) days")
                                .font(theme.font(22, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.cardStroke, lineWidth: 1))

                        // Longest Streak Card
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(theme.accent)
                                SectionLabel("Best streak")
                            }

                            Text("\(streakManager.longestStreak) days")
                                .font(theme.font(22, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.cardStroke, lineWidth: 1))
                    }
                    .padding(.horizontal, Layout.pageMargin)

                    // MARK: - Monthly Deposit Activity Grid
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(currentMonthYearString)
                                .font(theme.font(15, weight: .semibold))
                                .foregroundStyle(theme.accent)

                            Spacer()

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(theme.accent)
                                    .frame(width: 6, height: 6)
                                Text("Deposit day")
                                    .font(theme.font(11, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        // Days of week header
                        HStack {
                            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                                Text(day)
                                    .font(theme.font(10, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        // Month Grid Days
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                            ForEach(daysInCurrentMonth(), id: \.self) { date in
                                if let date = date {
                                    DayCell(date: date, isDepositDay: isDepositMadeOn(date: date))
                                } else {
                                    Color.clear
                                        .frame(height: 36)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1))
                    .padding(.horizontal, Layout.pageMargin)

                    // MARK: - Goal Forecast Summary
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                SectionLabel("Target goal")

                                Text(goalTitle.isEmpty ? "Current goal" : goalTitle)
                                    .font(theme.font(14, weight: .semibold))
                            }
                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                SectionLabel("Estimated completion")

                                Text(estimatedCompletionDate)
                                    .font(theme.font(14, weight: .semibold))
                            }
                        }

                        // Hairline divider
                        Rectangle()
                            .fill(theme.hairline)
                            .frame(height: 1)

                        HStack {
                            SectionLabel("Remaining to save")

                            Spacer()

                            Text("$\(Int(remainingAmount))")
                                .font(theme.font(14, weight: .semibold))
                                .foregroundStyle(theme.accent)
                        }

                        // MARK: Apple Calendar sync
                        Button(action: {
                            guard let date = estimatedCompletionDateValue else { return }
                            Task {
                                await calendarSync.addGoalToCalendar(
                                    goalMarker: goalTitle.isEmpty ? "untitled" : goalTitle,
                                    title: goalTitle,
                                    targetDate: date,
                                    remainingAmount: remainingAmount
                                )
                            }
                        }) {
                            HStack(spacing: 8) {
                                if calendarSync.isSyncing {
                                    ProgressView().tint(theme.accent)
                                } else {
                                    Image(systemName: "calendar.badge.plus")
                                }
                                Text(calendarSync.isSyncing ? "Syncing…" : "Add to Apple Calendar")
                                    .font(theme.font(14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
                            .foregroundStyle(theme.accent)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(theme.accent.opacity(0.4), lineWidth: 1))
                        }
                        .disabled(calendarSync.isSyncing || estimatedCompletionDateValue == nil)
                        .padding(.top, 6)

                        if let message = calendarSync.lastResultMessage {
                            Text(message)
                                .font(theme.font(11))
                                .foregroundStyle(calendarSync.lastSyncSucceeded ? theme.accent : theme.danger.opacity(0.9))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1))
                    .padding(.horizontal, Layout.pageMargin)
                    .padding(.bottom, 120)
                }
            }
        }
        // Sets the background and maps .primary/.secondary/.tertiary to
        // theme.textPrimary/Secondary/Tertiary for this whole screen.
        .themedSurface(theme)
    }

    // MARK: - Calendar Helpers

    private var currentMonthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }

    private func daysInCurrentMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: Date()),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: monthInterval.start)) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstDay) - 1
        let numberOfDays = calendar.range(of: .day, in: .month, for: Date())?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: firstWeekday)

        for day in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: day, to: firstDay) {
                days.append(date)
            }
        }
        return days
    }

    private func isDepositMadeOn(date: Date) -> Bool {
        if let lastDeposit = streakManager.lastDepositDate {
            return calendar.isDate(date, inSameDayAs: lastDeposit)
        }
        return false
    }
}

// MARK: - Day Cell View
struct DayCell: View {
    @EnvironmentObject var theme: ThemeManager
    let date: Date
    let isDepositDay: Bool

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    var body: some View {
        ZStack {
            if isDepositDay {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 30, height: 30)
            } else if isToday {
                Circle()
                    .stroke(.primary.opacity(0.4), lineWidth: 1)
                    .frame(width: 30, height: 30)
            }

            Text(dayNumber)
                .font(theme.font(11, weight: isToday || isDepositDay ? .bold : .regular))
                .foregroundStyle(isDepositDay ? theme.onAccent : (isToday ? theme.textPrimary : theme.textSecondary))
        }
        .frame(height: 36)
    }
}
