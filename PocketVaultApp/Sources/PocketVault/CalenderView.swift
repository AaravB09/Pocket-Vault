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

    // FIX: `max(targetGoal - currentSavings, 0.0)` is the same generic
    // min/max-over-Double overload Skip's Kotlin codegen can't resolve
    // (broke AmountScrubPicker, BudgetTrackerView, BuildStudioView) —
    // clamp with a plain comparison instead.
    var remainingAmount: Double {
        let diff = targetGoal - currentSavings
        return diff > 0.0 ? diff : 0.0
    }

    // FIX: same nested min(max(...)) pattern as BuildStudioView's
    // progressRatio — clamp manually.
    var completionPercentage: Double {
        let safeTarget = targetGoal > 1.0 ? targetGoal : 1.0
        let raw = currentSavings / safeTarget
        if raw < 0.0 { return 0.0 }
        if raw > 1.0 { return 1.0 }
        return raw
    }

    // Estimated target date based on streak momentum. Split into a raw
    // Date (used for the Apple Calendar export) and a formatted string
    // (used for display) so both stay in sync from one calculation.
    var estimatedCompletionDateValue: Date? {
        // FIX: another Double max() call — same pattern as above.
        let streakDays = Double(streakManager.currentStreak)
        let safeStreakDays = streakDays > 1.0 ? streakDays : 1.0
        let dailyPace = currentSavings / safeStreakDays
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
                    // NOTE(skip): ScreenHeader's trailing-accessory generic
                    // param can't be inferred from its default value on the
                    // Skip/Kotlin side ("Cannot infer type for type
                    // parameter 'Trailing'") — spelling out an empty
                    // trailing closure fixes it, and also clears the
                    // Edge.Set/SafeArea + Modifier.padding + 'Compose'
                    // errors that were cascading from this same call.
                    ScreenHeader("Calendar", subtitle: "Deposit streaks & forecast") {
                        EmptyView()
                    }
                    // Android-only: 40pt on top of the safe-area inset (plus
                    // ScreenHeader's own 8pt) left a noticeably bigger gap
                    // above the title than on iOS. Tightening this just for
                    // Android instead of touching the shared 40 value keeps
                    // iOS's spacing exactly as it was.
                    #if !SKIP
                    .padding(.top, 40)
                    #else
                    .padding(.top, 12)
                    #endif

                    // MARK: - Streak Stats Grid
                    HStack(spacing: 12) {
                        // Current Streak Card
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image.platformSymbol("flame.fill", android: "heart.fill")
                                    .foregroundStyle(theme.accent)
                                SectionLabel("Active streak")
                            }

                            Text("\(streakManager.currentStreak) days")
                                .font(theme.font(22, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        // NOTE(skip): .ultraThinMaterial has no Android
                        // equivalent — was cascading into the .clipShape
                        // right below it too.
                        .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.cardStroke, lineWidth: 1))

                        // Longest Streak Card
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image.platformSymbol("trophy.fill", android: "star.fill")
                                    .foregroundStyle(theme.accent)
                                SectionLabel("Best streak")
                            }

                            Text("\(streakManager.longestStreak) days")
                                .font(theme.font(22, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
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
                                    .foregroundStyle(.secondary) // was .tertiary
                            }
                        }

                        // Days of week header
                        HStack {
                            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                                Text(day)
                                    .font(theme.font(10, weight: .bold))
                                    .foregroundStyle(.secondary) // was .tertiary
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        // Month Grid Days
                        //
                        // FIX(Android crash): keying `ForEach` by the Date?
                        // value itself (`id: \.self`) meant every leading
                        // blank cell — there can be several, since most
                        // months don't start on a Sunday — shared the same
                        // `nil` key. SwiftUI/iOS tolerates duplicate
                        // identifiers, but Compose does not: LazyVerticalGrid
                        // throws "Key ... was already used" and the app
                        // crashes the moment this screen renders. Keying by
                        // the array's own index instead guarantees every
                        // cell has a unique id on both platforms.
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                            ForEach(Array(daysInCurrentMonth().enumerated()), id: \.offset) { _, date in
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
                    .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
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
                                    Image.platformSymbol("calendar.badge.plus", android: "calendar")
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
                    .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1))
                    .padding(.horizontal, Layout.pageMargin)
                    .padding(.bottom, 120)
                }
            }
        }
        // Sets the background and maps .primary/.secondary/.tertiary to
        // theme.textPrimary/Secondary/Tertiary for this whole screen.
        //
        // FIX: themedSurface() no longer takes `theme` as a parameter —
        // it reads ThemeManager via @EnvironmentObject internally now
        // (see ThemedSurface.swift). The old `.themedSurface(theme)` call
        // was passing `theme` positionally into the `ignoresSafeArea: Bool`
        // slot, which is what produced "Cannot convert value of type
        // 'ThemeManager' to expected argument type 'Bool'" and "Missing
        // argument label 'ignoresSafeArea:' in call" together.
        .themedSurface()
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

        // FIX: `calendar.range(of: .day, in: .month, for: Date())` hits
        // "None of the following candidates is applicable" — Skip's
        // Calendar shim doesn't fully implement this overload of
        // `range(of:in:for:)`. Compute the day count the same way
        // `estimatedCompletionDateValue` above already does successfully
        // — with `date(byAdding:)` and `dateComponents(_:from:to:)` —
        // instead of relying on `range(of:in:for:)`.
        let numberOfDays: Int = {
            guard let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: firstDay) else { return 30 }
            let diff = calendar.dateComponents([.day], from: firstDay, to: nextMonthStart)
            return diff.day ?? 30
        }()

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
