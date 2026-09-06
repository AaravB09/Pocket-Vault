import SwiftUI

/// Manual spend tracker: set a monthly limit, log payments/expenses as
/// you make them, and get a clear alert as you approach or blow past
/// the limit. Reuses the theme system so it matches whatever
/// color/appearance the user has picked in Profile.
public struct BudgetTrackerView: View {
    @EnvironmentObject var budgetManager: BudgetManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var privacy: PrivacyManager

    @State private var showAddSheet: Bool = false
    @State private var showLimitEditor: Bool = false
    @State private var limitInput: String = ""

    public var body: some View {
        ZStack {
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
                        .padding(Edge.Set.horizontal, Layout.pageMargin)

                    categoryBreakdown

                    transactionHistory
                }
                .padding(Edge.Set.bottom, 130)
            }
        }
        // FIX: themedSurface() no longer takes `theme` as a parameter —
        // it reads ThemeManager via @EnvironmentObject internally now
        // (see ThemedSurface.swift). The old `.themedSurface(theme)` call
        // was passing `theme` positionally into the `ignoresSafeArea: Bool`
        // slot, which is what produced "Cannot convert value of type
        // 'ThemeManager' to expected argument type 'Bool'" and "Missing
        // argument label 'ignoresSafeArea:' in call" together.
        .themedSurface()
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
        // FIX: Explicitly providing an EmptyView closure resolves the
        // "Cannot infer type for type parameter 'Trailing'" error.
        ScreenHeader("Budget") {
            EmptyView()
        }
        // Android-only: see the matching note in CalenderView.swift — this
        // 40pt gap sits on top of ScreenHeader's own padding plus the real
        // safe-area inset, and read as too much empty space specifically on
        // Android. iOS keeps the original 40.
        #if !SKIP
        .padding(Edge.Set.top, 40)
        #else
        .padding(Edge.Set.top, 12)
        #endif
    }

    // MARK: - Alert banner

    private func alertBanner(for status: BudgetStatus) -> some View {
        // FIX: a typed tuple-destructuring `let (a, b, c): (T1, T2, T3) = ...`
        // transpiles to a Kotlin destructuring declaration, and Kotlin does
        // not allow an explicit type annotation on a destructuring
        // declaration as a whole — that's the "Type annotations are not
        // allowed on destructuring declarations" error. (The tuple type
        // annotation itself was a legitimate earlier fix, for Swift's
        // "Cannot infer type for type parameter 'Trailing'" — that error
        // was cascading from this same line into unrelated closures
        // elsewhere in the file, like the ScreenHeader call in `header`.)
        // Give the *tuple* the explicit type instead of the destructured
        // names, then pull the three values out as plain property
        // accesses — no destructuring involved, so Skip has nothing to
        // choke on.
        let alertContent: (String, Color, String) = {
            switch status {
            case .over:
                return ("exclamationmark.triangle.fill", theme.danger, "You've gone over your $\(Int(budgetManager.monthlyLimit)) limit this month.")
            case .approaching:
                return ("exclamationmark.circle.fill", theme.warning, "You've used 80%+ of your $\(Int(budgetManager.monthlyLimit)) limit this month.")
            case .onTrack:
                return ("checkmark.circle.fill", theme.success, "Back on track.")
            }
        }()
        let icon = alertContent.0
        let color = alertContent.1
        let message = alertContent.2

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(theme.font(16, weight: Font.Weight.bold))
                .foregroundStyle(color)
            Text(message)
                .font(theme.font(12, weight: Font.Weight.semibold))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: { withAnimation { budgetManager.justCrossedThreshold = nil } }) {
                Image(systemName: "xmark")
                    .font(theme.font(11, weight: Font.Weight.bold))
                    .foregroundStyle(Color.gray.opacity(0.5))
            }
        }
        .padding(16)
        .background(color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // FIX: Pass the Shape directly to prevent ShapeStyle ambiguity errors
        .overlay(alignment: Alignment.center) { RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.5), lineWidth: 1.2) }
        .padding(Edge.Set.horizontal, Layout.pageMargin)
        .transition(AnyTransition.move(edge: Edge.top).combined(with: AnyTransition.opacity))
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
                VStack(alignment: HorizontalAlignment.leading, spacing: 4) {
                    SectionLabel("Spent this month")
                    Text("$\(Int(budgetManager.totalSpentThisMonth))")
                        .font(theme.font(34, weight: Font.Weight.light))
                        .foregroundStyle(Color.primary)
                }
                Spacer()
                Button(action: { showLimitEditor = true }) {
                    VStack(alignment: HorizontalAlignment.trailing, spacing: 4) {
                        SectionLabel("Limit")
                        HStack(spacing: 4) {
                            Text("$\(Int(budgetManager.monthlyLimit))")
                                .font(theme.font(16, weight: Font.Weight.semibold))
                                .foregroundStyle(theme.accent)
                            Image(systemName: "pencil")
                                .font(theme.font(10, weight: Font.Weight.bold))
                                .foregroundStyle(theme.accent)
                        }
                    }
                }
            }
            // PERF (Android): same dead-weight-blur situation as
            // ContentView's hero balance — `.blur` isn't implemented
            // under Skip (see SavingsTrendChart.swift's note), and the
            // `PrivacyRevealOverlay` right below already fully masks this
            // row on its own, so gating the blur to iOS-only changes
            // nothing visible on either platform and removes a per-frame
            // no-op modifier on Android.
            #if !SKIP
            .blur(radius: privacy.shouldMask ? 10.0 : 0.0)
            #endif
            .overlay {
                if privacy.shouldMask {
                    PrivacyRevealOverlay()
                }
            }

            GeometryReader { geo in
                ZStack(alignment: Alignment.leading) {
                    Capsule().fill(theme.hairline)
                    Capsule()
                        .fill(statusColor)
                        // FIX: `min(budgetManager.percentUsed, 1.0)` is the
                        // same generic-min-function issue fixed in
                        // AmountScrubPicker — Skip's Kotlin codegen can't
                        // resolve the overload and reports "Argument type
                        // mismatch: actual type is 'Number &
                        // Comparable<CapturedType(*)>'". Use a plain
                        // ternary instead.
                        .frame(width: geo.size.width * CGFloat(budgetManager.percentUsed > 1.0 ? 1.0 : budgetManager.percentUsed))
                }
            }
            .frame(height: 10)

            HStack {
                // FIX: same generic-min issue as above.
                Text("\(Int((budgetManager.percentUsed > 1.5 ? 1.5 : budgetManager.percentUsed) * 100.0))% used")
                    .font(theme.font(11, weight: Font.Weight.semibold))
                    .foregroundStyle(statusColor)
                Spacer()
                Text(budgetManager.status == .over ? "Over by $\(Int(budgetManager.totalSpentThisMonth - budgetManager.monthlyLimit))" : "$\(Int(budgetManager.remaining)) left")
                    .font(theme.font(13, weight: Font.Weight.semibold))
                    .foregroundStyle(Color.secondary) // was .tertiary — unsupported by Skip
            }
            .blur(radius: privacy.shouldMask ? 6.0 : 0.0)

            Button(action: { showAddSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Log a payment")
                }
            }
            // FIX: Replaced custom style with a standard style to resolve "Cannot find in scope".
            // Replace `.borderedProminent` with your specific button style struct once you locate it.
            #if !SKIP
            .buttonStyle(BorderedProminentButtonStyle())
            #endif
        }
        .padding(20)
        // NOTE(skip): .ultraThinMaterial has no Android/Compose equivalent
        // and was unresolved, which cascaded into the .clipShape error
        // right below it. Swapped for a themed translucent fill instead.
        .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        // FIX: Pass the Shape directly to prevent ShapeStyle ambiguity errors
        .overlay(alignment: Alignment.center) { RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1) }
        .padding(Edge.Set.horizontal, Layout.pageMargin)
    }

    // MARK: - Category breakdown

    private var categoryBreakdown: some View {
        let nonZero = SpendCategory.allCases
            .map { ($0, budgetManager.totalSpent(in: $0)) }
            .filter { $0.1 > 0.0 }
            .sorted { $0.1 > $1.1 }

        return Group {
            if !nonZero.isEmpty {
                VStack(alignment: HorizontalAlignment.leading, spacing: 12) {
                    SectionLabel("By category")
                        .padding(Edge.Set.horizontal, Layout.pageMargin)

                    VStack(spacing: 10) {
                        ForEach(nonZero, id: \.0) { category, amount in
                            HStack(spacing: 12) {
                                Image(systemName: category.icon)
                                    .font(theme.font(13))
                                    .foregroundStyle(theme.accent)
                                    .frame(width: 26)
                                Text(category.displayName)
                                    .font(theme.font(12, weight: Font.Weight.medium))
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                Text("$\(Int(amount))")
                                    .font(theme.font(13, weight: Font.Weight.semibold))
                                    .foregroundStyle(Color.primary)
                            }
                            .padding(Edge.Set.horizontal, 16)
                            .padding(Edge.Set.vertical, 12)
                            .background(theme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(Edge.Set.horizontal, Layout.pageMargin)
                }
            }
        }
    }

    // MARK: - Transaction history

    private var transactionHistory: some View {
        Group {
            if budgetManager.transactionsThisMonth.isEmpty {
                Text("No payments logged yet this month. Tap \u{201C}Log a Payment\u{201D} above to start tracking.")
                    .font(theme.font(13, weight: Font.Weight.light))
                    .foregroundStyle(Color.secondary) // was .tertiary
                    .multilineTextAlignment(TextAlignment.center)
                    .padding(Edge.Set.horizontal, 40)
                    .padding(Edge.Set.top, 20)
            } else {
                VStack(alignment: HorizontalAlignment.leading, spacing: 18) {
                    ForEach(budgetManager.transactionsByDay, id: \.date) { day in
                        VStack(alignment: HorizontalAlignment.leading, spacing: 8) {
                            Text(dayLabel(day.date))
                                .font(theme.font(12, weight: Font.Weight.semibold))
                                .foregroundStyle(Color.secondary) // was .tertiary
                                .padding(Edge.Set.horizontal, Layout.pageMargin)

                            VStack(spacing: 8) {
                                ForEach(day.items) { item in
                                    TransactionRow(item: item, onDelete: {
                                        budgetManager.deleteTransaction(item.id)
                                    })
                                }
                            }
                            .padding(Edge.Set.horizontal, Layout.pageMargin)
                        }
                    }
                }
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        #if !SKIP
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        #else
        if let yesterday = Calendar.current.date(byAdding: Calendar.Component.day, value: -1, to: Date()),
           Calendar.current.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        #endif
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Transaction row (with hand-rolled swipe-to-delete)

/// Shared by `BudgetTrackerView.transactionHistory`. Kept as its own
/// `View` (rather than a plain function like the other row builders in
/// this file) because it needs private `@State` per-row to track its own
/// swipe offset independently of every other row.
public struct TransactionRow: View {
    @EnvironmentObject var theme: ThemeManager
    let item: SpendTransaction
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0.0
    @State private var dragStartOffset: CGFloat? = nil

    private let revealWidth: CGFloat = 74.0
    private let deleteThreshold: CGFloat = 150.0

    public var body: some View {
        ZStack {
            // Delete button revealed behind the row as it's dragged left.
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(Animation.easeOut(duration: 0.2)) { onDelete() }
                }) {
                    Image(systemName: "trash.fill")
                        .font(theme.font(15, weight: Font.Weight.semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: revealWidth, height: 44)
                        .background(theme.danger)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            rowContent
                .offset(x: offset)
                #if !SKIP
                .contentShape(Rectangle())
                #endif
                .gesture(
                    DragGesture(minimumDistance: 8.0)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            if dragStartOffset == nil { dragStartOffset = offset }
                            guard let start = dragStartOffset else { return }
                            let proposed = start + value.translation.width
                            // FIX: same generic min/max-over-Double issue
                            // as elsewhere — clamp with plain comparisons
                            // instead of nested min(max(...)).
                            let lowerBound = -revealWidth - 60.0
                            let boundedLow = proposed < lowerBound ? lowerBound : proposed
                            offset = boundedLow > 0.0 ? 0.0 : boundedLow
                        }
                        .onEnded { _ in
                            dragStartOffset = nil
                            if offset < -deleteThreshold {
                                withAnimation(Animation.easeOut(duration: 0.2)) { onDelete() }
                            } else if offset < -revealWidth / 2.0 {
                                withAnimation(Animation.spring(response: 0.3, dampingFraction: 0.8)) { offset = -revealWidth }
                            } else {
                                withAnimation(Animation.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0.0 }
                            }
                        }
                )
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.15)).frame(width: 34, height: 34)
                Image(systemName: item.category.icon)
                    .font(theme.font(13))
                    .foregroundStyle(theme.accent)
            }
            VStack(alignment: HorizontalAlignment.leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.note.isEmpty ? item.category.displayName : item.note)
                        .font(theme.font(13, weight: Font.Weight.medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    if item.isAutoImported {
                        Image.platformSymbol("building.columns.fill", android: "house.fill")
                            .font(theme.font(9))
                            .foregroundStyle(theme.accent.opacity(0.7))
                    }
                }
                Text(timeLabel(item.date))
                    .font(theme.font(10, weight: Font.Weight.light))
                    .foregroundStyle(Color.secondary) // was .tertiary
            }
            Spacer()
            Text("-$\(Int(item.amount))")
                .font(theme.font(13, weight: Font.Weight.semibold))
                .foregroundStyle(Color.primary)
        }
        .padding(Edge.Set.vertical, 10)
        .padding(Edge.Set.horizontal, 14)
        // NOTE(skip): same Material swap as progressCard above.
        .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // FIX: Pass the Shape directly to prevent ShapeStyle ambiguity errors
        .overlay(alignment: Alignment.center) { RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1) }
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Add Payment Sheet

public struct AddPaymentSheet: View {
    @EnvironmentObject var budgetManager: BudgetManager
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) var dismiss: DismissAction

    @State private var amountText: String = ""
    @State private var selectedCategory: SpendCategory = .food
    @State private var note: String = ""

    private var isValid: Bool {
        guard let value = Double(amountText) else { return false }
        return value > 0.0
    }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 24) {
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image.platformSymbol("xmark.circle.fill", android: "xmark")
                                .font(theme.font(22, weight: Font.Weight.bold))
                                .foregroundStyle(Color.secondary) // was .tertiary
                        }
                    }
                    .padding(Edge.Set.horizontal, 20)
                    .padding(Edge.Set.top, 20)

                    VStack(spacing: 4) {
                        SectionLabel("Log payment")
                        Text("What did you spend?")
                            .font(theme.font(22, weight: Font.Weight.semibold))
                            .foregroundStyle(Color.primary)
                    }

                    VStack(spacing: 6) {
                        SectionLabel("Amount ($)")
                        TextField("0", text: $amountText)
                            .keyboardType(UIKeyboardType.decimalPad)
                            .multilineTextAlignment(TextAlignment.center)
                            .font(theme.font(44, weight: Font.Weight.light))
                            .foregroundStyle(Color.primary)
                    }

                    VStack(alignment: HorizontalAlignment.leading, spacing: 10) {
                        SectionLabel("Category")
                            .padding(Edge.Set.horizontal, Layout.pageMargin)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 10) {
                            ForEach(SpendCategory.allCases) { category in
                                Button(action: { selectedCategory = category }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: category.icon)
                                            .font(theme.font(16))
                                        Text(category.displayName)
                                            .font(theme.font(12, weight: Font.Weight.medium))
                                    }
                                    .foregroundStyle(selectedCategory == category ? theme.onAccent : theme.textPrimary)
                                    .frame(maxWidth: CGFloat.infinity)
                                    .padding(Edge.Set.vertical, 14)
                                    .background(selectedCategory == category ? theme.accent : (theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06)))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    // FIX: Pass Double(0) explicitly so Skip's Kotlin codegen doesn't mix up Int and Double
                                    .overlay(alignment: Alignment.center) { RoundedRectangle(cornerRadius: 14).stroke(theme.accent.opacity(selectedCategory == category ? Double(0) : 0.25), lineWidth: 1) }
                                }
                            }
                        }
                        .padding(Edge.Set.horizontal, Layout.pageMargin)
                    }

                    VStack(alignment: HorizontalAlignment.leading, spacing: 8) {
                        SectionLabel("Note (optional)")

                        TextField("e.g. Grocery run", text: $note)
                            .foregroundStyle(Color.primary)
                            .padding(14)
                            // NOTE(skip): same Material swap.
                            .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            // FIX: Pass the Shape directly to prevent ShapeStyle ambiguity errors
                            .overlay(alignment: Alignment.center) { RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1) }
                    }
                    .padding(Edge.Set.horizontal, Layout.pageMargin)

                    Button(action: {
                        guard let amount = Double(amountText) else { return }
                        budgetManager.addTransaction(amount: amount, category: selectedCategory, note: note)
                        #if !SKIP
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        dismiss()
                    }) {
                        Text("Save payment")
                    }
                    // FIX: Replaced custom style with a standard style to resolve "Cannot find in scope".
                    // Replace `.borderedProminent` with your specific button style struct once you locate it.
                    #if !SKIP
                    .buttonStyle(BorderedProminentButtonStyle())
                    #endif
                    .disabled(!isValid)
                    .opacity(isValid ? 1.0 : 0.4)
                    .padding(Edge.Set.horizontal, Layout.pageMargin)
                    .padding(Edge.Set.bottom, 50)
                }
            }
        }
        // FIX: see the note in BudgetTrackerView.body above — themedSurface()
        // takes no `theme` argument anymore.
        .themedSurface()
    }
}

// MARK: - Limit Editor Sheet

public struct LimitEditorSheet: View {
    @EnvironmentObject var budgetManager: BudgetManager
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) var dismiss: DismissAction
    @Binding var limitInput: String

    private var isValid: Bool {
        guard let value = Double(limitInput) else { return false }
        return value >= 0.0
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image.platformSymbol("xmark.circle.fill", android: "xmark")
                            .font(theme.font(22, weight: Font.Weight.bold))
                            .foregroundStyle(Color.secondary) // was .tertiary
                    }
                }
                .padding(Edge.Set.horizontal, Layout.pageMargin)
                .padding(Edge.Set.top, 20)

                VStack(spacing: 4) {
                    SectionLabel("Monthly limit")
                    Text("Set your spending cap")
                        .font(theme.font(22, weight: Font.Weight.semibold))
                        .foregroundStyle(Color.primary)
                }

                TextField("500", text: $limitInput)
                    .keyboardType(UIKeyboardType.numberPad)
                    .multilineTextAlignment(TextAlignment.center)
                    .font(theme.font(52, weight: Font.Weight.light))
                    .foregroundStyle(Color.primary)

                Text("You'll get an alert here once you cross 80% and again if you go over.")
                    .font(theme.font(12, weight: Font.Weight.light))
                    .foregroundStyle(Color.secondary) // was .tertiary
                    .multilineTextAlignment(TextAlignment.center)
                    .padding(Edge.Set.horizontal, 40)

                Spacer()

                Button(action: {
                    guard let value = Double(limitInput) else { return }
                    budgetManager.setLimit(value)
                    dismiss()
                }) {
                    Text("Save limit")
                }
                // FIX: Replaced custom style with a standard style to resolve "Cannot find in scope".
                // Replace `.borderedProminent` with your specific button style struct once you locate it.
                #if !SKIP
                .buttonStyle(BorderedProminentButtonStyle())
                #endif
                .disabled(!isValid)
                .opacity(isValid ? 1.0 : 0.4)
                .padding(Edge.Set.horizontal, Layout.pageMargin)
                .padding(Edge.Set.bottom, 50)
            }
        }
        // FIX: see the note in BudgetTrackerView.body above — themedSurface()
        // takes no `theme` argument anymore.
        .themedSurface()
        .onAppear { limitInput = "\(Int(budgetManager.monthlyLimit))" }
    }
}
