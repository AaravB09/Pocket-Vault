import SwiftUI
#if !SKIP
import Charts
#endif

/// Time window for the trend chart. Mirrors the range picker pattern from
/// portfolio-tracking apps (1W/1M/3M/6M/ALL) — a fixed set of zoom levels
/// over the same underlying history rather than a free-form date picker.
public enum TrendRange: String, CaseIterable, Identifiable {
    case week = "1W"
    case month = "1M"
    case threeMonth = "3M"
    case sixMonth = "6M"
    case all = "ALL"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .threeMonth: return 90
        case .sixMonth: return 182
        case .all: return nil
        }
    }
}

/// A gradient-filled line chart of a goal's balance over time, with a
/// scrub-to-inspect gesture — tap or drag anywhere on the line to see the
/// exact balance and date at that point, the same interaction pattern
/// Wealthfolio's net-worth chart uses. Reads straight from `Goal.history`,
/// so it stays in sync automatically as deposits come in.
public struct SavingsTrendChart: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var privacy: PrivacyManager
    let history: [SavingsSnapshot]
    let targetAmount: Double

    @State private var selectedRange: TrendRange = .month
    @State private var scrubbedPoint: SavingsSnapshot?

    private var sortedHistory: [SavingsSnapshot] {
        history.sorted { $0.date < $1.date }
    }

    private var visiblePoints: [SavingsSnapshot] {
        guard let days = selectedRange.days,
              let cutoff = Calendar.current.date(byAdding: Calendar.Component.day, value: -days, to: Date()) else {
            return sortedHistory
        }
        let inWindow = sortedHistory.filter { $0.date >= cutoff }
        // Carry the last point before the window in as the starting
        // value, so a range like "1W" doesn't render a flat/empty chart
        // just because the most recent deposit happened 10 days ago.
        if let anchor = sortedHistory.last(where: { $0.date < cutoff }), !inWindow.isEmpty {
            return [anchor] + inWindow
        }
        return inWindow.isEmpty ? sortedHistory.suffix(1).map { $0 } : inWindow
    }

    private var latest: SavingsSnapshot? { sortedHistory.last }
    private var earliestVisible: SavingsSnapshot? { visiblePoints.first }

    /// Change over the visible window, for the small delta readout under
    /// the balance — the number people actually look at first.
    private var windowDelta: Double {
        guard let first = earliestVisible, let last = latest else { return 0 }
        return last.amount - first.amount
    }

    private var isPositive: Bool { windowDelta >= 0 }

    private var displayPoint: SavingsSnapshot? { scrubbedPoint ?? latest }

    private var yBounds: (min: Double, max: Double) {
        let values = visiblePoints.map { $0.amount } + [targetAmount]
        // NOTE(skip): bare Int literals (`0`, `1`) mixed with Double
        // values through `?? `/`min`/`max` don't unify the way they do in
        // Swift — Skip's Kotlin codegen needs the Double literals spelled
        // out explicitly. Also: Swift's `max(_:_:_:)` has a 3-argument
        // overload; Kotlin's `max` only takes two, so the third argument
        // needs nesting into a second `max` call.
        let lo = min(values.min() ?? 0.0, 0.0)
        let hi = max(max(values.max() ?? targetAmount, targetAmount), 1.0)
        let pad = (hi - lo) * 0.12
        return (max(lo - pad, 0), hi + pad)
    }

    var body: some View {
        VStack(alignment: Alignment.leading, spacing: 16) {
            header

            if visiblePoints.count >= 2 {
                chart
                    // FIX (Android: fits without scrolling) — see the
                    // matching note in ContentView.swift on the Deposit
                    // button ScrollView fix. Same chart on both
                    // platforms, just less tall on Android to help this
                    // whole screen fit in the shorter effective viewport
                    // (before this, the inset bug alone was already
                    // eating the height difference several times over).
                    #if !SKIP
                    .frame(height: 150)
                    #else
                    .frame(height: 110)
                    #endif

                rangePicker
            } else {
                emptyState
            }
        }
        .padding(Layout.cardPadding)
        // NOTE(skip): `.ultraThinMaterial` and `.clipShape` aren't
        // resolved by Skip's SwiftUI shim — iOS keeps the real material +
        // shape clip, Android gets a plain tinted background +
        // `.cornerRadius`, same pattern used everywhere else in the app.
        #if !SKIP
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius))
        #else
        .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
        .cornerRadius(Layout.cardRadius)
        #endif
        .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius).stroke(theme.cardStroke, lineWidth: 1))
        .padding(Edge.Set.horizontal, Layout.pageMargin)
        // NOTE(skip): `.blur` isn't implemented under Skip at all. The
        // PrivacyRevealOverlay below already covers the content when
        // masked, so Android just skips the blur and goes straight to
        // the overlay.
        #if !SKIP
        .blur(radius: privacy.shouldMask ? 14 : 0)
        #endif
        .overlay {
            if privacy.shouldMask {
                PrivacyRevealOverlay()
                    .padding(Edge.Set.horizontal, Layout.pageMargin)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: Alignment.top) {
            VStack(alignment: Alignment.leading, spacing: 4) {
                Text("Savings trend")
                    .font(theme.font(12, weight: Font.Weight.semibold))
                    .foregroundStyle(theme.textTertiary)

                Text("$\(Int(displayPoint?.amount ?? 0))")
                    .font(theme.font(26, weight: Font.Weight.light))
                    .foregroundStyle(Color.primary)
                    #if !SKIP
                    .contentTransition(.numericText())
                    #endif
                    .animation(Animation.easeOut(duration: 0.15), value: displayPoint?.amount)

                if let date = displayPoint?.date {
                    Text(scrubbedPoint == nil ? "Today" : formatted(date))
                        .font(theme.font(11, weight: Font.Weight.medium))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            Spacer()

            if visiblePoints.count >= 2 {
                HStack(spacing: 4) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(theme.font(10, weight: Font.Weight.bold))
                    Text("\(isPositive ? "+" : "-")$\(Int(abs(windowDelta)))")
                        .font(theme.font(12, weight: Font.Weight.semibold))
                }
                .foregroundStyle(isPositive ? theme.success : theme.danger)
                .padding(Edge.Set.horizontal, 10)
                .padding(Edge.Set.vertical, 6)
                .background((isPositive ? theme.success : theme.danger).opacity(0.14))
                // NOTE(skip): same clipShape-only fix as the main card —
                // background here is already theme-agnostic.
                #if !SKIP
                .clipShape(Capsule())
                #else
                .cornerRadius(100)
                #endif
            }
        }
    }

    // MARK: - Chart

    #if !SKIP
    private var chart: some View {
        Chart {
            ForEach(visiblePoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Floor", yBounds.min),
                    yEnd: .value("Balance", point.amount)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            theme.accent.opacity(0.30),
                            theme.accent.opacity(0.10),
                            theme.accent.opacity(0.0)
                        ],
                        startPoint: UnitPoint.top, endPoint: UnitPoint.bottom
                    )
                )

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Balance", point.amount)
                )
                // Monotone instead of Catmull-Rom: it still draws a
                // smooth curve through every point, but never overshoots
                // past them. Catmull-Rom's overshoot is exactly what
                // made a sharp, single-day jump (several deposits logged
                // within minutes of each other) render as a wild bulging
                // hook instead of a clean rise — monotone tracks the
                // real values, the same "no fake bumps" approach
                // Wealthfolio's net-worth chart uses.
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: CGLineCap.round, lineJoin: CGLineJoin.round))
                .foregroundStyle(theme.accent)
            }

            RuleMark(y: .value("Target", targetAmount))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4.0, 4.0]))
                .foregroundStyle(theme.textTertiary.opacity(0.6))
                .annotation(position: .top, alignment: Alignment.trailing) {
                    Text("Goal")
                        .font(theme.font(10, weight: Font.Weight.semibold))
                        .foregroundStyle(theme.textTertiary)
                }

            // "Today" marker — a small filled dot pinned to the latest
            // point whenever the user isn't actively scrubbing, so the
            // line always has a clear, deliberate endpoint (the
            // Wealthfolio/Wealthfront convention) instead of just
            // trailing off into the edge of the card.
            if scrubbedPoint == nil, let latest = visiblePoints.last {
                PointMark(
                    x: .value("Date", latest.date),
                    y: .value("Balance", latest.amount)
                )
                .symbolSize(60)
                .foregroundStyle(theme.accent)

                PointMark(
                    x: .value("Date", latest.date),
                    y: .value("Balance", latest.amount)
                )
                .symbolSize(22)
                .foregroundStyle(theme.onAccent)
            }

            if let scrubbed = scrubbedPoint {
                RuleMark(x: .value("Date", scrubbed.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(theme.textTertiary.opacity(0.5))

                PointMark(
                    x: .value("Date", scrubbed.date),
                    y: .value("Balance", scrubbed.amount)
                )
                .symbolSize(70)
                .foregroundStyle(theme.accent)
            }
        }
        .chartYScale(domain: yBounds.min...yBounds.max)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateScrub(at: value.location, proxy: proxy, geo: geo)
                            }
                            .onEnded { _ in
                                withAnimation(Animation.easeOut(duration: 0.2)) { scrubbedPoint = nil }
                            }
                    )
            }
        }
    }

    private func updateScrub(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geo[plotFrame].origin
        let xInPlot = location.x - origin.x
        guard let date: Date = proxy.value(atX: xInPlot) else { return }

        // Nearest snapshot to the scrub position — Wealthfolio-style
        // "snap to the actual data point" rather than an interpolated
        // in-between value, so the number shown always matches a real deposit.
        let nearest = visiblePoints.min { a, b in
            abs(a.date.timeIntervalSince(date)) < abs(b.date.timeIntervalSince(date))
        }
        if nearest != scrubbedPoint {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        scrubbedPoint = nearest
    }
    #else
    // MARK: - Chart (Android fallback)
    //
    // Apple's Charts framework isn't available under Skip, so this draws
    // the same gradient-filled line + target rule + scrub-to-inspect
    // interaction with plain SwiftUI Path/Shape drawing, which Skip does
    // support. Keeps the same visible behavior as the iOS Chart above:
    // smooth-ish line through every point, a dashed "Goal" line, a dot on
    // the latest value, and drag-to-scrub with a snap-to-nearest-point.
    private var chart: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = visiblePoints
            let bounds = yBounds

            // NOTE(skip): these were previously local `func`s. Swift lets
            // you reference a local function by name as a first-class
            // closure value (as `xPos: xPos` below does), but Skip's
            // transpiler doesn't — it tries to *call* the function where
            // a `Function1<SavingsSnapshot, Double>` value was expected,
            // producing "Argument type mismatch: actual type is 'Double'"
            // and "Function invocation 'xPos(...)' expected". Declaring
            // them as `let` closures instead makes them first-class
            // values on both platforms.
            let xPos: (SavingsSnapshot) -> CGFloat = { point in
                guard let first = points.first, let last = points.last,
                      last.date != first.date else { return size.width / 2 }
                let total = last.date.timeIntervalSince(first.date)
                let offset = point.date.timeIntervalSince(first.date)
                return size.width * CGFloat(total > 0 ? offset / total : 0)
            }

            let yPos: (Double) -> CGFloat = { amount in
                let range = bounds.max - bounds.min
                guard range > 0 else { return size.height / 2 }
                let ratio = (amount - bounds.min) / range
                return size.height * (1 - CGFloat(ratio))
            }

            ZStack {
                if points.count >= 2 {
                    // Gradient area under the line
                    Path { path in
                        path.move(to: CGPoint(x: xPos(points[0]), y: size.height))
                        for point in points {
                            path.addLine(to: CGPoint(x: xPos(point), y: yPos(point.amount)))
                        }
                        path.addLine(to: CGPoint(x: xPos(points[points.count - 1]), y: size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.accent.opacity(0.30),
                                theme.accent.opacity(0.10),
                                theme.accent.opacity(0.0)
                            ],
                            startPoint: UnitPoint.top, endPoint: UnitPoint.bottom
                        )
                    )

                    // Line through every point
                    Path { path in
                        path.move(to: CGPoint(x: xPos(points[0]), y: yPos(points[0].amount)))
                        for point in points.dropFirst() {
                            path.addLine(to: CGPoint(x: xPos(point), y: yPos(point.amount)))
                        }
                    }
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: CGLineCap.round, lineJoin: CGLineJoin.round))

                    // Target goal rule
                    Path { path in
                        let y = yPos(targetAmount)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    .stroke(theme.textTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4.0, 4.0]))

                    Text("Goal")
                        .font(theme.font(10, weight: Font.Weight.semibold))
                        .foregroundStyle(theme.textTertiary)
                        .position(x: size.width - 18, y: max(yPos(targetAmount) - 10, 10))

                    // Today marker, unless actively scrubbing
                    if scrubbedPoint == nil, let latest = points.last {
                        let p = CGPoint(x: xPos(latest), y: yPos(latest.amount))
                        Circle().fill(theme.accent).frame(width: 12, height: 12).position(p)
                        Circle().fill(theme.onAccent).frame(width: 5, height: 5).position(p)
                    }

                    // Scrub marker
                    if let scrubbed = scrubbedPoint {
                        let x = xPos(scrubbed)
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        .stroke(theme.textTertiary.opacity(0.5), lineWidth: 1)

                        Circle()
                            .fill(theme.accent)
                            .frame(width: 14, height: 14)
                            .position(x: x, y: yPos(scrubbed.amount))
                    }
                }

                Rectangle()
                    .fill(Color.clear)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateScrubAndroid(at: value.location, points: points, xPos: xPos)
                            }
                            .onEnded { _ in
                                withAnimation(Animation.easeOut(duration: 0.2)) { scrubbedPoint = nil }
                            }
                    )
            }
        }
    }

    private func updateScrubAndroid(at location: CGPoint, points: [SavingsSnapshot], xPos: (SavingsSnapshot) -> CGFloat) {
        guard !points.isEmpty else { return }
        let nearest = points.min { a, b in
            abs(xPos(a) - location.x) < abs(xPos(b) - location.x)
        }
        // NOTE(skip): this is the Android-only scrub path (see the #else
        // above) — UIImpactFeedbackGenerator crashes at runtime under
        // Skip, so unlike the iOS version above it's simply skipped here
        // rather than called.
        scrubbedPoint = nearest
    }
    #endif

    // MARK: - Range picker

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(TrendRange.allCases) { range in
                Button(action: {
                    #if !SKIP
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(Animation.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedRange = range
                    }
                }) {
                    Text(range.rawValue)
                        .font(theme.font(10, weight: Font.Weight.bold))
                        .tracking(0.5)
                        .foregroundStyle(selectedRange == range ? theme.onAccent : theme.textSecondary)
                        .frame(maxWidth: CGFloat.infinity)
                        .padding(Edge.Set.vertical, 8)
                        .background(selectedRange == range ? theme.accent : Color.clear)
                        // NOTE(skip): same clipShape-only fix as elsewhere
                        // in this file — background is already
                        // theme-agnostic.
                        #if !SKIP
                        .clipShape(Capsule())
                        #else
                        .cornerRadius(100)
                        #endif
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image.platformSymbol("chart.line.uptrend.xyaxis", android: "arrow.forward")
                .font(theme.font(20))
                .foregroundStyle(theme.textTertiary)
            Text("Make a couple deposits to see your trend take shape.")
                .font(theme.font(11, weight: Font.Weight.medium))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(TextAlignment.center)
        }
        .frame(maxWidth: CGFloat.infinity)
        .padding(Edge.Set.vertical, 24)
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}
