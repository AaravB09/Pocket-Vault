import SwiftUI

/// A tactile numeric entry for dollar amounts: a large center value with
/// blurred, faded neighbor values above and below (like a spinning wheel
/// caught mid-motion), plus a horizontal tick-mark ruler you can drag to
/// scrub the amount up or down in fixed increments.
///
/// Inspired by Clucky's alarm-time picker, adapted for a context where
/// exact figures matter: the big number is a real `TextField`, so typing
/// an exact amount always works — the ruler below is a bonus, faster way
/// to nudge the value without touching the keyboard, not a replacement
/// for precise entry.
struct AmountScrubPicker: View {
    @EnvironmentObject var theme: ThemeManager
    @Binding var amount: Double

    /// How much one ruler "tick" is worth, and one drag-step.
    var step: Double = 50
    var range: ClosedRange<Double> = 0...1_000_000

    @FocusState private var isTyping: Bool
    @State private var typedText: String = ""
    @GestureState private var gestureStartAmount: Double?

    // Trail + pulse state — purely visual reinforcement of the same
    // "step" feedback the haptics give, since haptics never fire in the
    // Simulator (only on a real device) and are easy to miss even on
    // hardware during a fast scrub.
    @State private var trailWidth: CGFloat = 0
    @State private var trailSign: CGFloat = 1
    @State private var pointerGlow: CGFloat = 0
    @State private var lastDragTranslation: CGFloat = 0
    @State private var lastHapticStepIndex: Int?

    // Ruler geometry: fixed spacing per $step, independent of the view's
    // actual width, so the drag math and the tick layout always agree.
    private let tickPixelSpacing: CGFloat = 14
    private let visibleTickRadius = 22
    private var pixelsPerDollar: CGFloat { tickPixelSpacing / CGFloat(step) }

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private func fmt(_ value: Double) -> String {
        Self.formatter.string(from: NSNumber(value: Int(value.rounded()))) ?? "\(Int(value))"
    }

    private var neighborUp: Double { min(range.upperBound, amount + step) }
    private var neighborDown: Double { max(range.lowerBound, amount - step) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                VStack(spacing: 2) {
                    Text(fmt(neighborUp))
                        .font(theme.font(15, weight: .light))
                        .foregroundStyle(.tertiary)
                        .blur(radius: 2.5)
                        .contentTransition(.numericText(value: neighborUp))

                    // While scrubbing/idle: an animated Text so every ruler
                    // tick and every keystroke rolls the digits instead of
                    // jump-cutting. While typing: swap in a real TextField
                    // so exact entry still works (a live-editing TextField
                    // can't itself use .contentTransition).
                    ZStack {
                        HStack(spacing: 2) {
                            Text("$")
                                .font(theme.font(30, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text(fmt(amount))
                                .font(theme.font(48, weight: .light))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText(value: amount))
                        }
                        .opacity(isTyping ? 0 : 1)

                        HStack(spacing: 2) {
                            Text("$")
                                .font(theme.font(30, weight: .light))
                                .foregroundStyle(.tertiary)
                            TextField("", text: $typedText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(theme.font(48, weight: .light))
                                .foregroundStyle(.primary)
                                .fixedSize()
                                .focused($isTyping)
                                .onChange(of: typedText) { _, newValue in
                                    let digits = newValue.filter(\.isNumber)
                                    if digits != newValue { typedText = digits }
                                    if let value = Double(digits) {
                                        amount = min(range.upperBound, max(range.lowerBound, value))
                                    }
                                }
                        }
                        .opacity(isTyping ? 1 : 0)
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: amount)

                    Text(fmt(neighborDown))
                        .font(theme.font(15, weight: .light))
                        .foregroundStyle(.tertiary)
                        .blur(radius: 2.5)
                        .contentTransition(.numericText(value: neighborDown))
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: amount)
            }
            .frame(height: 130)
            .overlay(alignment: .top) {
                LinearGradient(colors: [theme.background, theme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 36)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [theme.background, theme.background.opacity(0)], startPoint: .bottom, endPoint: .top)
                    .frame(height: 36)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                typedText = amount > 0 ? "\(Int(amount.rounded()))" : ""
                isTyping = true
            }

            tickRuler
                .frame(height: 26)
                .padding(.top, 6)

            Text(isTyping ? "tap elsewhere to confirm" : "drag the ruler, tap ahead to jump, or tap the amount to type")
                .font(theme.font(9, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .onAppear { typedText = amount > 0 ? "\(Int(amount.rounded()))" : "" }
        .onChange(of: amount) { _, newValue in
            // Keep the hidden text buffer in sync when the ruler (not the
            // keyboard) is what changed the value, so reopening the
            // keyboard later starts from the right digits.
            if !isTyping { typedText = newValue > 0 ? "\(Int(newValue.rounded()))" : "" }
        }
    }

    // A real ruler: ticks are positioned by their actual dollar distance
    // from `amount`, so as the value changes the strip visibly slides —
    // physically, like pulling a tape measure past a fixed pointer, not
    // just a marker pulsing in place. Dragging left brings bigger numbers
    // (further right on the ruler) into the center, same as dragging a
    // strip of paper toward you; tapping anywhere on the ruler reads off
    // whichever value currently sits at that position and jumps there.
    private var tickRuler: some View {
        GeometryReader { geo in
            let centerX = geo.size.width / 2
            let centerY = geo.size.height / 2
            let centerIndex = Int((amount / step).rounded())

            ZStack {
                ForEach(-visibleTickRadius...visibleTickRadius, id: \.self) { offset in
                    let idx = centerIndex + offset
                    let tickValue = Double(idx) * step
                    if tickValue >= range.lowerBound && tickValue <= range.upperBound {
                        let dx = CGFloat((tickValue - amount)) * pixelsPerDollar
                        let isMajor = idx % 5 == 0
                        Rectangle()
                            .fill(theme.textTertiary.opacity(isMajor ? 0.5 : 0.22))
                            .frame(width: 1, height: isMajor ? 12 : 7)
                            .position(x: centerX + dx, y: centerY)
                    }
                }

                // Gold trail streaking off the pointer in the direction of
                // recent movement — a comet-tail glow that grows with drag
                // speed and fades back to nothing once you stop.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [theme.accent.opacity(0.55), theme.accent.opacity(0)],
                            startPoint: trailSign > 0 ? .leading : .trailing,
                            endPoint: trailSign > 0 ? .trailing : .leading
                        )
                    )
                    .frame(width: trailWidth, height: 14)
                    .blur(radius: 4)
                    .position(x: centerX - (trailSign * trailWidth / 2), y: centerY)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)

                // Soft halo behind the pointer that flashes brighter each
                // time a $step boundary is crossed — a visible echo of the
                // haptic tick.
                Circle()
                    .fill(theme.accent.opacity(0.5))
                    .frame(width: 26, height: 26)
                    .blur(radius: 5)
                    .scaleEffect(1 + pointerGlow)
                    .opacity(Double(pointerGlow))
                    .position(x: centerX, y: centerY)
                    .allowsHitTesting(false)

                // Fixed pointer — always at center, reads off whatever
                // value the ruler has currently scrolled underneath it.
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 2, height: 20)
                    .position(x: centerX, y: centerY)
            }
            // Ambient animation for every path that isn't the raw live
            // drag (typing, tap-jump, end-of-drag settle) — short and
            // snappy so ticks still feel tightly tied to a real drag
            // rather than visibly lagging behind the finger.
            .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.86, blendDuration: 0.1), value: amount)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($gestureStartAmount) { _, state, _ in
                        if state == nil { state = amount }
                    }
                    .onChanged { value in
                        guard let start = gestureStartAmount else { return }
                        // 1:1 with the finger — dragging left slides bigger
                        // values in from the right, exactly like pulling a
                        // ruler strip past a fixed pointer.
                        let deltaDollars = -Double(value.translation.width) / pixelsPerDollar
                        let proposed = start + deltaDollars
                        let clamped = min(range.upperBound, max(range.lowerBound, proposed)).rounded()

                        // Trail reacts to raw per-frame finger speed, not
                        // to whether the value actually changed — keeps it
                        // feeling continuous even between $1 increments.
                        let frameDelta = value.translation.width - lastDragTranslation
                        lastDragTranslation = value.translation.width
                        if abs(frameDelta) > 0.3 {
                            trailSign = frameDelta > 0 ? -1 : 1
                            withAnimation(.easeOut(duration: 0.1)) {
                                trailWidth = min(50, abs(frameDelta) * 5 + 12)
                            }
                        }

                        if clamped != amount {
                            amount = clamped
                            // Throttle haptics (and the glow pulse) to
                            // every $step crossing rather than every whole
                            // dollar — firing on every $1 would buzz
                            // constantly on a real device during a fast
                            // drag.
                            let stepIndex = Int((clamped / step).rounded())
                            if stepIndex != lastHapticStepIndex {
                                lastHapticStepIndex = stepIndex
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.easeOut(duration: 0.08)) {
                                    pointerGlow = 1
                                }
                                withAnimation(.easeOut(duration: 0.3).delay(0.06)) {
                                    pointerGlow = 0
                                }
                            }
                        }
                    }
                    .onEnded { value in
                        let moved = abs(value.translation.width) > 4 || abs(value.translation.height) > 4
                        lastDragTranslation = 0
                        withAnimation(.easeOut(duration: 0.35)) {
                            trailWidth = 0
                        }
                        if !moved {
                            // Tap-to-jump: read off whichever tick sits at
                            // the tapped position and animate there.
                            let tapDX = value.location.x - centerX
                            let jumpDollars = Double(tapDX) / pixelsPerDollar
                            let target = min(range.upperBound, max(range.lowerBound, amount + jumpDollars))
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                amount = (target / step).rounded() * step
                                pointerGlow = 1
                            }
                            withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                                pointerGlow = 0
                            }
                        } else {
                            // Settle to a clean $step value on release.
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                amount = (amount / step).rounded() * step
                            }
                        }
                    }
            )
        }
    }
}
