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
    var step: Double = 50.0
    
    // FIX: Replaced `ClosedRange` with explicit Doubles to prevent
    // Skip/Kotlin type-resolution failures during comparison.
    var minAmount: Double = 0.0
    var maxAmount: Double = 1_000_000.0

    @FocusState private var isTyping: Bool
    @State private var typedText: String = ""

    // FIX: @GestureState is unsupported in Skip, so we use a standard @State
    // and manually track the start of the drag in .onChanged and clear it in .onEnded.
    @State private var dragStartAmount: Double? = nil

    // Android-only: tracks whether a raw scrub gesture is currently active,
    // so the spring animation below (see `.animation(value: amount)`) can be
    // suspended for the duration of the drag — see that modifier for why.
    @State private var isDragging: Bool = false

    // Trail + pulse state — purely visual reinforcement of the same
    // "step" feedback the haptics give, since haptics never fire in the
    // Simulator (only on a real device) and are easy to miss even on
    // hardware during a fast scrub.
    @State private var trailWidth: CGFloat = 0.0
    @State private var trailSign: CGFloat = 1.0
    @State private var pointerGlow: CGFloat = 0.0
    @State private var lastDragTranslation: CGFloat = 0.0
    @State private var lastHapticStepIndex: Int?

    // Ruler geometry: fixed spacing per $step, independent of the view's
    // actual width, so the drag math and the tick layout always agree.
    private let tickPixelSpacing: CGFloat = 14.0
    private let visibleTickRadius: Int = 22
    private var pixelsPerDollar: CGFloat { tickPixelSpacing / CGFloat(step) }

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = NumberFormatter.Style.decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private func fmt(_ value: Double) -> String {
        // Casting natively using `as NSNumber` resolves Skip's disambiguation warning
        let intVal = Int(value.rounded())
        // FIX: `Self.formatter` doesn't transpile through Skip to Kotlin —
        // referencing a private static member via `Self` inside an instance
        // method breaks Skip's Kotlin codegen and cascades into unrelated
        // "None of the following candidates is applicable" errors further
        // down the file. Use the type name directly instead of `Self`.
        return AmountScrubPicker.formatter.string(from: intVal as NSNumber) ?? "\(intVal)"
    }

    // FIX: Swift's generic global `min`/`max` functions don't transpile
    // cleanly through Skip's Kotlin codegen when the arguments mix a
    // `ClosedRange<Double>` bound with an arithmetic expression (e.g.
    // `min(range.upperBound, amount + step)`). Skip's overload resolution
    // fails on these calls with "None of the following candidates is
    // applicable", and — same as the `Self.formatter` issue above — the
    // failure cascades into unrelated errors further down the file. Do the
    // clamping manually with plain comparisons instead of calling the
    // generic function.
    private func clamped(_ value: Double) -> Double {
        if value < minAmount { return minAmount }
        if value > maxAmount { return maxAmount }
        return value
    }

    private var neighborUp: Double { clamped(amount + step) }
    private var neighborDown: Double { clamped(amount - step) }

    var body: some View {
        VStack(spacing: 6.0) {
            ZStack {
                VStack(spacing: 2.0) {
                    Text(fmt(neighborUp))
                        .font(theme.font(15.0, weight: Font.Weight.light))
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .blur(radius: 2.5)
                    #if !SKIP
                        .contentTransition(.numericText(value: neighborUp))
                    #endif

                    // While scrubbing/idle: an animated Text so every ruler
                    // tick and every keystroke rolls the digits instead of
                    // jump-cutting. While typing: swap in a real TextField
                    // so exact entry still works (a live-editing TextField
                    // can't itself use .contentTransition).
                    ZStack {
                        HStack(spacing: 2.0) {
                            Text("$")
                                .font(theme.font(30.0, weight: Font.Weight.light))
                                .foregroundStyle(Color.gray.opacity(0.5))
                            Text(fmt(amount))
                                .font(theme.font(48.0, weight: Font.Weight.light))
                                .foregroundStyle(Color.primary)
                            #if !SKIP
                                .contentTransition(.numericText(value: amount))
                            #endif
                        }
                        .opacity(isTyping ? 0.0 : 1.0)

                        HStack(spacing: 2.0) {
                            Text("$")
                                .font(theme.font(30.0, weight: Font.Weight.light))
                                .foregroundStyle(Color.gray.opacity(0.5))
                            TextField("", text: $typedText)
                                .keyboardType(UIKeyboardType.numberPad)
                                .multilineTextAlignment(TextAlignment.center)
                                .font(theme.font(48.0, weight: Font.Weight.light))
                                .foregroundStyle(Color.primary)
                                .fixedSize()
                                .focused($isTyping)
                                .onChange(of: typedText) { newValue in
                                    // FIX: Use simple character comparison to satisfy Skip
                                    let digits = newValue.filter { $0 >= "0" && $0 <= "9" }
                                    if digits != newValue { typedText = digits }
                                    if let value = Double(digits) {
                                        amount = clamped(value)
                                    }
                                }
                        }
                        .opacity(isTyping ? 1.0 : 0.0)
                    }
                    .animation(Animation.spring(response: 0.3, dampingFraction: 0.75), value: amount)

                    Text(fmt(neighborDown))
                        .font(theme.font(15.0, weight: Font.Weight.light))
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .blur(radius: 2.5)
                    #if !SKIP
                        .contentTransition(.numericText(value: neighborDown))
                    #endif
                }
                .animation(Animation.spring(response: 0.3, dampingFraction: 0.75), value: amount)
            }
            .frame(height: 130.0)
            .overlay(alignment: Alignment.top) {
                LinearGradient(colors: [theme.background, theme.background.opacity(0.0)], startPoint: UnitPoint.top, endPoint: UnitPoint.bottom)
                    .frame(height: 36.0)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: Alignment.bottom) {
                LinearGradient(colors: [theme.background, theme.background.opacity(0.0)], startPoint: UnitPoint.bottom, endPoint: UnitPoint.top)
                    .frame(height: 36.0)
                    .allowsHitTesting(false)
            }
            #if !SKIP
            .contentShape(Rectangle())
            #endif
            .onTapGesture {
                typedText = amount > 0.0 ? "\(Int(amount.rounded()))" : ""
                isTyping = true
            }

            tickRuler
                .frame(height: 26.0)
                .padding(Edge.Set.top, 6.0)

            Text(isTyping ? "tap elsewhere to confirm" : "drag the ruler, tap ahead to jump, or tap the amount to type")
                .font(theme.font(9.0, weight: Font.Weight.medium))
                .tracking(0.5)
                .foregroundStyle(Color.gray.opacity(0.5))
                .padding(Edge.Set.top, 2.0)
        }
        .onAppear { typedText = amount > 0.0 ? "\(Int(amount.rounded()))" : "" }
        .onChange(of: amount) { newValue in
            // Keep the hidden text buffer in sync when the ruler (not the
            // keyboard) is what changed the value, so reopening the
            // keyboard later starts from the right digits.
            if !isTyping { typedText = newValue > 0.0 ? "\(Int(newValue.rounded()))" : "" }
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
            let centerX = geo.size.width / 2.0
            let centerY = geo.size.height / 2.0
            let centerIndex = Int((amount / step).rounded())

            ZStack {
                ForEach(-visibleTickRadius...visibleTickRadius, id: \.self) { offset in
                    let idx = centerIndex + offset
                    let tickValue = Double(idx) * step
                    if tickValue >= minAmount && tickValue <= maxAmount {
                        let dx = CGFloat(tickValue - amount) * pixelsPerDollar
                        let isMajor = idx % 5 == 0
                        Rectangle()
                            .fill(theme.textTertiary.opacity(isMajor ? 0.5 : 0.22))
                            .frame(width: 1.0, height: isMajor ? 12.0 : 7.0)
                            .position(x: centerX + dx, y: centerY)
                    }
                }

                // Gold trail streaking off the pointer in the direction of
                // recent movement — a comet-tail glow that grows with drag
                // speed and fades back to nothing once you stop.
                //
                // FIX: startPoint/endPoint were swapped, so the capsule was
                // fully opaque at its far tip and transparent right where it
                // met the pointer — the opposite of "streaking off the
                // pointer". The bright end of the gradient now sits at the
                // edge touching the pointer (x: centerX) and fades to
                // nothing at the tip (x: centerX ± trailWidth), matching
                // the `.position` math below for both trailSign cases.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [theme.accent.opacity(0.55), theme.accent.opacity(0.0)],
                            startPoint: trailSign > 0.0 ? UnitPoint.trailing : UnitPoint.leading,
                            endPoint: trailSign > 0.0 ? UnitPoint.leading : UnitPoint.trailing
                        )
                    )
                    .frame(width: trailWidth, height: 14.0)
                    .blur(radius: 4.0)
                    .position(x: centerX - (trailSign * trailWidth / 2.0), y: centerY)
                    .blendMode(BlendMode.plusLighter)
                    .allowsHitTesting(false)

                // Soft halo behind the pointer that flashes brighter each
                // time a $step boundary is crossed — a visible echo of the
                // haptic tick.
                Circle()
                    .fill(theme.accent.opacity(0.5))
                    .frame(width: 26.0, height: 26.0)
                    .blur(radius: 5.0)
                    .scaleEffect(1.0 + pointerGlow)
                    .opacity(Double(pointerGlow))
                    .position(x: centerX, y: centerY)
                    .allowsHitTesting(false)

                // Fixed pointer — always at center, reads off whatever
                // value the ruler has currently scrolled underneath it.
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 2.0, height: 20.0)
                    .position(x: centerX, y: centerY)
            }
            // Ambient animation for every path that isn't the raw live
            // drag (typing, tap-jump, end-of-drag settle) — short and
            // snappy so ticks still feel tightly tied to a real drag
            // rather than visibly lagging behind the finger.
            //
            // FIX(Android lag/oscillation): this comment describes the
            // intent, but the modifier below was previously unconditional
            // — it animated `amount` on EVERY change, including the raw
            // per-frame updates from onChanged during an active drag. Real
            // SwiftUI's interactive spring coalesces smoothly with an
            // in-flight gesture on iOS, but SkipUI's Compose-backed
            // animation doesn't retarget cleanly mid-flight: each rapid
            // reassignment of `amount` mid-drag restarts a new spring
            // toward the new target while the previous one is still
            // settling, which is exactly the "1900 -> 1905 -> 1900" flicker
            // — two overlapping springs chasing each other. Suspending the
            // animation for the actual duration of the drag (only on
            // Android; iOS's behavior here was already correct) removes
            // the competing springs; the value still animates normally for
            // typing, tap-to-jump, and the settle-on-release below.
            #if !SKIP
            .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.86, blendDuration: 0.1), value: amount)
            #else
            .animation(isDragging ? nil : Animation.interactiveSpring(response: 0.15, dampingFraction: 0.86, blendDuration: 0.1), value: amount)
            #endif
            #if !SKIP
            .contentShape(Rectangle())
            #endif
            .gesture(
                DragGesture(minimumDistance: 0.0)
                    .onChanged { value in
                        if dragStartAmount == nil {
                            dragStartAmount = amount
                            isDragging = true
                        }
                        guard let start = dragStartAmount else { return }

                        // 1:1 with the finger — dragging left slides bigger
                        // values in from the right, exactly like pulling a
                        // ruler strip past a fixed pointer.
                        let deltaDollars = -Double(value.translation.width) / Double(pixelsPerDollar)
                        let proposed = start + deltaDollars
                        let clampedValue = clamped(proposed).rounded()

                        // Trail reacts to raw per-frame finger speed, not
                        // to whether the value actually changed — keeps it
                        // feeling continuous even between $1 increments.
                        let frameDelta = value.translation.width - lastDragTranslation
                        lastDragTranslation = value.translation.width
                        if abs(frameDelta) > 0.3 {
                            trailSign = frameDelta > 0.0 ? -1.0 : 1.0
                            // FIX: same generic min/max overload-resolution
                            // problem as `clamped(_:)` above — replaced
                            // with a plain comparison instead of
                            // `min(50.0, ...)`.
                            let proposedTrailWidth = abs(frameDelta) * 5.0 + 12.0
                            withAnimation(Animation.easeOut(duration: 0.1)) {
                                trailWidth = proposedTrailWidth > 50.0 ? 50.0 : proposedTrailWidth
                            }
                        }

                        if clampedValue != amount {
                            amount = clampedValue
                            // Throttle haptics (and the glow pulse) to
                            // every $step crossing rather than every whole
                            // dollar — firing on every $1 would buzz
                            // constantly on a real device during a fast
                            // drag.
                            let stepIndex = Int((clampedValue / step).rounded())
                            if stepIndex != lastHapticStepIndex {
                                lastHapticStepIndex = stepIndex
                                #if !SKIP
                                UISelectionFeedbackGenerator().selectionChanged()
                                #endif
                                withAnimation(Animation.easeOut(duration: 0.08)) {
                                    pointerGlow = 1.0
                                }
                                withAnimation(Animation.easeOut(duration: 0.3).delay(0.06)) {
                                    pointerGlow = 0.0
                                }
                            }
                        }
                    }
                    .onEnded { value in
                        dragStartAmount = nil
                        isDragging = false
                        let moved = abs(value.translation.width) > 4.0 || abs(value.translation.height) > 4.0
                        lastDragTranslation = 0.0
                        withAnimation(Animation.easeOut(duration: 0.35)) {
                            trailWidth = 0.0
                        }
                        if !moved {
                            // Tap-to-jump: read off whichever tick sits at
                            // the tapped position and animate there.
                            let tapDX = value.location.x - centerX
                            let jumpDollars = Double(tapDX) / Double(pixelsPerDollar)
                            let target = clamped(amount + jumpDollars)
                            #if !SKIP
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(Animation.spring(response: 0.35, dampingFraction: 0.75)) {
                                amount = (target / step).rounded() * step
                                pointerGlow = 1.0
                            }
                            withAnimation(Animation.easeOut(duration: 0.4).delay(0.1)) {
                                pointerGlow = 0.0
                            }
                        } else {
                            // Settle to a clean $step value on release.
                            withAnimation(Animation.spring(response: 0.3, dampingFraction: 0.8)) {
                                amount = (amount / step).rounded() * step
                            }
                        }
                    }
            )
        }
    }
}
