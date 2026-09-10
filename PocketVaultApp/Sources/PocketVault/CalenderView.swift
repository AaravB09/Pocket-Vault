import SwiftUI

public struct CalendarView: View {
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var theme: ThemeManager
    @StateObject private var calendarSync = CalendarSyncManager()

    @Binding var currentSavings: Double
    @Binding var targetGoal: Double
    @Binding var goalTitle: String

    @State private var selectedDate: Date = Date()
    @State private var isCalendarSyncPressed = false
    private let calendar = Calendar.current

    var remainingAmount: Double {
        let diff = targetGoal - currentSavings
        return diff > 0.0 ? diff : 0.0
    }

    var completionPercentage: Double {
        let safeTarget = targetGoal > 1.0 ? targetGoal : 1.0
        let raw = currentSavings / safeTarget
        if raw < 0.0 { return 0.0 }
        if raw > 1.0 { return 1.0 }
        return raw
    }

    var estimatedCompletionDateValue: Date? {
        let streakDays = Double(streakManager.currentStreak)
        let safeStreakDays = streakDays > 1.0 ? streakDays : 1.0
        let dailyPace = currentSavings / safeStreakDays
        let daysLeft = dailyPace > 0 ? Int(ceil(remainingAmount / dailyPace)) : 30
        return calendar.date(byAdding: Calendar.Component.day, value: daysLeft, to: Date())
    }

    var estimatedCompletionDate: String {
        guard let date = estimatedCompletionDateValue else { return "In Progress" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private var calendarSyncButtonFill: Color {
        let opacity = isCalendarSyncPressed ? 0.08 : 0.04
        let darkOpacity = isCalendarSyncPressed ? 0.12 : 0.08
        return theme.isLight ? Color.black.opacity(opacity) : Color.white.opacity(darkOpacity)
    }

    private var calendarSyncStrokeOpacity: Double {
        isCalendarSyncPressed ? 0.6 : 0.4
    }

    public var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24.0) {
                    ScreenHeader("Calendar", subtitle: "Deposit streaks & forecast") {
                        EmptyView()
                    }
                    #if !SKIP
                    .padding(Edge.Set.top, 40.0)
                    #else
                    .padding(Edge.Set.top, 12.0)
                    #endif

                    // MARK: - Streak Stats Grid
                    HStack(spacing: 12.0) {
                        VStack(spacing: 8.0) {
                            HStack(spacing: 6.0) {
                                Image.platformSymbol("flame.fill", android: "heart.fill")
                                    .foregroundStyle(theme.accent)
                                SectionLabel("Active streak")
                            }

                            Text("\(streakManager.currentStreak) days")
                                .font(theme.font(22, weight: Font.Weight.semibold))
                        }
                        .frame(maxWidth: CGFloat.infinity)
                        .padding(Edge.Set.vertical, 18.0)
                        .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 16.0))
                        .overlay(RoundedRectangle(cornerRadius: 16.0).stroke(Color.clear, lineWidth: 1.0))

                        VStack(spacing: 8.0) {
                            HStack(spacing: 6.0) {
                                Image.platformSymbol("trophy.fill", android: "star.fill")
                                    .foregroundStyle(theme.accent)
                                SectionLabel("Best streak")
                            }

                            Text("\(streakManager.longestStreak) days")
                                .font(theme.font(22, weight: Font.Weight.semibold))
                        }
                        .frame(maxWidth: CGFloat.infinity)
                        .padding(Edge.Set.vertical, 18.0)
                        .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 16.0))
                        .overlay(RoundedRectangle(cornerRadius: 16.0).stroke(Color.clear, lineWidth: 1.0))
                    }
                    .padding(Edge.Set.horizontal, Layout.pageMargin)

                    // MARK: - Monthly Deposit Activity Grid
                    VStack(alignment: HorizontalAlignment.leading, spacing: 16.0) {
                        HStack {
                            Text(currentMonthYearString)
                                .font(theme.font(15, weight: Font.Weight.semibold))
                                .foregroundStyle(theme.accent)

                            Spacer()

                            HStack(spacing: 4.0) {
                                Circle()
                                    .fill(theme.accent)
                                    .frame(width: 6.0, height: 6.0)
                                Text("Deposit day")
                                    .font(theme.font(11, weight: Font.Weight.medium))
                                    .foregroundStyle(Color.secondary)
                            }
                        }

                        HStack {
                            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                                Text(day)
                                    .font(theme.font(10, weight: Font.Weight.bold))
                                    .foregroundStyle(Color.secondary)
                                    .frame(maxWidth: CGFloat.infinity)
                            }
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(GridItem.Size.flexible()), count: 7), spacing: 10.0) {
                            ForEach(Array(daysInCurrentMonth().enumerated()), id: \.offset) { _, date in
                                if let date = date {
                                    DayCell(date: date, isDepositDay: isDepositMadeOn(date: date))
                                } else {
                                    Color.clear
                                        .frame(height: 36.0)
                                }
                            }
                        }
                    }
                    .padding(20.0)
                    .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 20.0))
                    .overlay(RoundedRectangle(cornerRadius: 20.0).stroke(Color.clear, lineWidth: 1.0))
                    .padding(Edge.Set.horizontal, Layout.pageMargin)

                    // MARK: - Goal Forecast Summary
                    VStack(spacing: 12.0) {
                        HStack {
                            VStack(alignment: HorizontalAlignment.leading, spacing: 4.0) {
                                SectionLabel("Target goal")

                                Text(goalTitle.isEmpty ? "Current goal" : goalTitle)
                                    .font(theme.font(14, weight: Font.Weight.semibold))
                            }
                            Spacer()

                            VStack(alignment: HorizontalAlignment.trailing, spacing: 4.0) {
                                SectionLabel("Estimated completion")

                                Text(estimatedCompletionDate)
                                    .font(theme.font(14, weight: Font.Weight.semibold))
                            }
                        }

                        Rectangle()
                            .fill(theme.hairline)
                            .frame(height: 1.0)

                        HStack {
                            SectionLabel("Remaining to save")

                            Spacer()

                            Text("$\(Int(remainingAmount))")
                                .font(theme.font(14, weight: Font.Weight.semibold))
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
                            HStack(spacing: 8.0) {
                                if calendarSync.isSyncing {
                                    ProgressView().tint(theme.accent)
                                } else {
                                    Image.platformSymbol("calendar.badge.plus", android: "calendar")
                                }
                                Text(calendarSync.isSyncing ? "Syncing…" : "Add to Apple Calendar")
                                    .font(theme.font(14, weight: Font.Weight.semibold))
                            }
                            .frame(maxWidth: CGFloat.infinity)
                            .padding(Edge.Set.vertical, 14.0)
                            .background(calendarSyncButtonFill)
                            .foregroundStyle(theme.accent)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(theme.accent.opacity(calendarSyncStrokeOpacity), lineWidth: 1.0))
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in isCalendarSyncPressed = true }
                                .onEnded { _ in isCalendarSyncPressed = false }
                        )
                        .disabled(calendarSync.isSyncing || estimatedCompletionDateValue == nil)
                        .padding(Edge.Set.top, 6.0)

                        if let message = calendarSync.lastResultMessage {
                            Text(message)
                                .font(theme.font(11))
                                .foregroundStyle(calendarSync.lastSyncSucceeded ? theme.accent : theme.danger.opacity(0.9))
                                .multilineTextAlignment(TextAlignment.center)
                        }
                    }
                    .padding(20.0)
                    .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 20.0))
                    .overlay(RoundedRectangle(cornerRadius: 20.0).stroke(Color.clear, lineWidth: 1.0))
                    .padding(Edge.Set.horizontal, Layout.pageMargin)
                    .padding(Edge.Set.bottom, 120.0)
                }
            }
        }
        .themedSurface()
    }

    // MARK: - Calendar Helpers

    private var currentMonthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }

    private func daysInCurrentMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: Calendar.Component.month, for: Date()),
              let firstDay = calendar.date(from: calendar.dateComponents([Calendar.Component.year, Calendar.Component.month], from: monthInterval.start)) else {
            return []
        }

        let firstWeekday = calendar.component(Calendar.Component.weekday, from: firstDay) - 1

        let numberOfDays: Int = {
            guard let nextMonthStart = calendar.date(byAdding: Calendar.Component.month, value: 1, to: firstDay) else { return 30 }
            let diff = calendar.dateComponents([Calendar.Component.day], from: firstDay, to: nextMonthStart)
            return diff.day ?? 30
        }()

        var days: [Date?] = Array(repeating: nil, count: firstWeekday)

        for day in 0..<numberOfDays {
            if let date = calendar.date(byAdding: Calendar.Component.day, value: day, to: firstDay) {
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
public struct DayCell: View {
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

    // FIX: same root cause as GoalPickerBar's chip fill — a nested Color
    // ternary passed directly into `.foregroundStyle(...)` doesn't
    // reliably transpile through Skip on Android. Extracting to a
    // computed property first fixes it.
    private var dayNumberColor: Color {
        if isDepositDay { return theme.onAccent }
        return isToday ? theme.textPrimary : theme.textSecondary
    }

    public var body: some View {
        ZStack {
            if isDepositDay {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 30.0, height: 30.0)
            } else if isToday {
                Circle()
                    .stroke(Color.primary.opacity(0.4), lineWidth: 1.0)
                    .frame(width: 30.0, height: 30.0)
            }

            Text(dayNumber)
                .font(theme.font(11, weight: isToday || isDepositDay ? Font.Weight.bold : Font.Weight.regular))
                .foregroundStyle(dayNumberColor)
        }
        .frame(height: 36.0)
    }
}
