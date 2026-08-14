import SwiftUI
import Charts

/// Time window for the trend chart. Mirrors the range picker pattern from
/// portfolio-tracking apps (1W/1M/3M/6M/ALL) — a fixed set of zoom levels
/// over the same underlying history rather than a free-form date picker.
enum TrendRange: String, CaseIterable, Identifiable {
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
struct SavingsTrendChart: View {
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
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
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
        let lo = min(values.min() ?? 0, 0)
        let hi = max(values.max() ?? targetAmount, targetAmount, 1)
        let pad = (hi - lo) * 0.12
        return (max(lo - pad, 0), hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if visiblePoints.count >= 2 {
                chart
                    .frame(height: 150)

                rangePicker
            } else {
                emptyState
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1))
        .padding(.horizontal, 24)
        .blur(radius: privacy.shouldMask ? 14 : 0)
        .overlay {
            if privacy.shouldMask {
                PrivacyRevealOverlay()
                    .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SAVINGS TREND")
                    .font(theme.font(9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.tertiary)

                Text("$\(Int(displayPoint?.amount ?? 0))")
                    .font(theme.font(26, weight: .light))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: displayPoint?.amount)

                if let date = displayPoint?.date {
                    Text(scrubbedPoint == nil ? "Today" : formatted(date))
                        .font(theme.font(11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if visiblePoints.count >= 2 {
                HStack(spacing: 4) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(theme.font(10, weight: .bold))
                    Text("\(isPositive ? "+" : "-")$\(Int(abs(windowDelta)))")
                        .font(theme.font(12, weight: .semibold))
                }
                .foregroundStyle(isPositive ? theme.success : theme.danger)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((isPositive ? theme.success : theme.danger).opacity(0.14))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(visiblePoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Floor", yBounds.min),
                    yEnd: .value("Balance", point.amount)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [theme.accent.opacity(0.32), theme.accent.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Balance", point.amount)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(theme.accent)
            }

            RuleMark(y: .value("Target", targetAmount))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(theme.textTertiary.opacity(0.6))
                .annotation(position: .top, alignment: .trailing) {
                    Text("GOAL")
                        .font(theme.font(8, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.tertiary)
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
                                withAnimation(.easeOut(duration: 0.2)) { scrubbedPoint = nil }
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

    // MARK: - Range picker

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(TrendRange.allCases) { range in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedRange = range
                    }
                }) {
                    Text(range.rawValue)
                        .font(theme.font(10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(selectedRange == range ? theme.onAccent : theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedRange == range ? theme.accent : Color.clear)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(theme.font(20))
                .foregroundStyle(.tertiary)
            Text("Make a couple deposits to see your trend take shape.")
                .font(theme.font(11, weight: .medium))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}
