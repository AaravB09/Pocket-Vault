import SwiftUI

// MARK: - VaultButtonVariant

/// Visual style for a `VaultButton`.
public enum VaultButtonVariant {
    /// Solid accent fill with theme-aware text on top.
    case primary
    /// Outlined with accent border and accent text.
    case secondary
    /// Solid danger-red fill with high-contrast text.
    case destructive
    /// Fully transparent with a subtle tinted fill on hover/press.
    case ghost
    /// Fully transparent text-only button — no fill, no stroke.
    /// Disabled/loading states are expressed through opacity alone.
    case tertiary
}

// MARK: - VaultButton

public struct VaultButton: View {

    // MARK: Injected dependencies

    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Parameters

    private let variant: VaultButtonVariant
    private let action: () -> Void
    private var isLoading: Bool = false
    private var height: CGFloat = 50.0
    private var fontSize: CGFloat = 15.0
    private var fontWeight: Font.Weight = .semibold
    private var horizontalPadding: CGFloat = 20.0
    private var fullWidth: Bool = true
    private let label: AnyView

    // MARK: Internal state

    @State private var isPressed = false
    @State private var isFlashing = false
    @FocusState private var isFocused: Bool

    #if !SKIP
    @State private var isHovering = false
    #endif

    // MARK: - String Convenience Initializer (Cross-Platform / Skip Compatible)

    public init(
        _ title: String,
        variant: VaultButtonVariant = .primary,
        isLoading: Bool = false,
        height: CGFloat = 50.0,
        fontSize: CGFloat = 15.0,
        fontWeight: Font.Weight = .semibold,
        horizontalPadding: CGFloat = 20.0,
        fullWidth: Bool = true,
        action: @escaping () -> Void
    ) {
        self.variant = variant
        self.isLoading = isLoading
        self.height = height
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.horizontalPadding = horizontalPadding
        self.fullWidth = fullWidth
        self.action = action
        self.label = AnyView(Text(title))
    }

    // MARK: - AnyView Initializer (Cross-Platform / Skip Compatible)

    public init(
        variant: VaultButtonVariant = .primary,
        isLoading: Bool = false,
        height: CGFloat = 50.0,
        fontSize: CGFloat = 15.0,
        fontWeight: Font.Weight = .semibold,
        horizontalPadding: CGFloat = 20.0,
        fullWidth: Bool = true,
        action: @escaping () -> Void,
        label: AnyView
    ) {
        self.variant = variant
        self.isLoading = isLoading
        self.height = height
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.horizontalPadding = horizontalPadding
        self.fullWidth = fullWidth
        self.action = action
        self.label = label
    }

    // MARK: - Generic ViewBuilder Initializer (iOS/Swift Only, Guarded from Skip)

    #if !SKIP
    public init<V: View>(
        variant: VaultButtonVariant = .primary,
        isLoading: Bool = false,
        height: CGFloat = 50.0,
        fontSize: CGFloat = 15.0,
        fontWeight: Font.Weight = .semibold,
        horizontalPadding: CGFloat = 20.0,
        fullWidth: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> V
    ) {
        self.init(
            variant: variant,
            isLoading: isLoading,
            height: height,
            fontSize: fontSize,
            fontWeight: fontWeight,
            horizontalPadding: horizontalPadding,
            fullWidth: fullWidth,
            action: action,
            label: AnyView(label())
        )
    }
    #endif

    // MARK: - Computed properties

    private var isInteractive: Bool {
        isEnabled && !isLoading
    }

    private var fillColor: Color {
        guard isInteractive else {
            return neutralFillColor
        }
        switch variant {
        case .primary:
            return theme.accent.opacity(isPressed ? 0.85 : 1.0)
        case .secondary:
            return theme.accent.opacity(isPressed ? 0.18 : 0.10)
        case .destructive:
            return theme.danger.opacity(isPressed ? 0.85 : 1.0)
        case .ghost:
            return Color.clear
        case .tertiary:
            return Color.clear
        }
    }

    private var backgroundFillColor: Color {
        guard isInteractive else {
            return neutralFillColor
        }
        switch variant {
        case .primary:
            return fillColor
        case .secondary:
            return theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08)
        case .destructive:
            return fillColor
        case .ghost:
            return fillColor
        case .tertiary:
            return fillColor
        }
    }

    private var contentColor: Color {
        guard isInteractive else {
            return neutralContentColor
        }
        switch variant {
        case .primary:
            return theme.onAccent
        case .secondary:
            return theme.accent
        case .destructive:
            return theme.onAccent
        case .ghost:
            return theme.textPrimary
        case .tertiary:
            return theme.textSecondary
        }
    }

    private var neutralFillColor: Color {
        Color(white: 0.5).opacity(0.28)
    }

    private var neutralContentColor: Color {
        Color(white: 0.5)
    }

    private var strokeColor: Color {
        guard isInteractive else {
            return neutralContentColor.opacity(0.4)
        }
        switch variant {
        case .primary:
            return (isPressed ? theme.onAccent.opacity(0.06) : theme.onAccent.opacity(0.12))
        case .secondary:
            return theme.accent.opacity(isPressed ? 0.5 : 0.7)
        case .destructive:
            return theme.onAccent.opacity(isPressed ? 0.06 : 0.12)
        case .ghost:
            return Color.clear
        case .tertiary:
            return Color.clear
        }
    }

    private var shadowColor: Color {
        // Tertiary has no shadow — it's a pure text button.
        guard variant != .tertiary else { return Color.clear }
        return Color.black.opacity(isInteractive ? (isPressed ? 0.08 : 0.18) : 0.0)
    }

    private var shadowRadius: CGFloat {
        // Tertiary has no shadow.
        guard variant != .tertiary else { return 0.0 }
        return isPressed ? 4.0 : 14.0
    }

    private var shadowY: CGFloat {
        // Tertiary has no shadow.
        guard variant != .tertiary else { return 0.0 }
        return isPressed ? 2.0 : 6.0
    }

    // MARK: - Body

    public var body: some View {
        Button(action: performAction) {
            ZStack {
                backgroundLayer
                flashOverlay
                ZStack {
                    label
                        .font(theme.font(fontSize, weight: fontWeight))
                        .foregroundStyle(contentColor)
                        .opacity(isLoading ? 0.0 : 1.0)
                        .animation(.easeOut(duration: 0.18), value: isLoading)

                    if isLoading {
                        ProgressView()
                            .tint(spinnerColor)
                    }
                }
            }
            .frame(height: height)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, horizontalPadding)
            .overlay(focusRing, alignment: .center)
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .focused($isFocused)
        .simultaneousGesture(pressGesture)
        #if !SKIP
        .onHover { newValue in
            isHovering = isInteractive && newValue
        }
        #endif
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .animation(.easeOut(duration: 0.15), value: isEnabled)
        .animation(.easeOut(duration: 0.2), value: isLoading)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var backgroundLayer: some View {
        RoundedRectangle(cornerRadius: Layout.controlRadius)
            .fill(backgroundFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: Layout.controlRadius)
                    .stroke(strokeColor, lineWidth: 1.0)
            )
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                y: shadowY
            )
    }

    @ViewBuilder
    private var flashOverlay: some View {
        RoundedRectangle(cornerRadius: Layout.controlRadius)
            .fill(flashFillColor)
            .opacity(isFlashing ? 0.18 : 0.0)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var focusRing: some View {
        RoundedRectangle(cornerRadius: Layout.controlRadius + 3.0)
            .stroke(focusRingColor, lineWidth: isFocused ? 3.0 : 0.0)
            .padding(-3.0)
    }

    // MARK: - Color helpers

    private var flashFillColor: Color {
        switch variant {
        case .primary:
            return theme.onAccent
        case .secondary:
            return theme.accent
        case .destructive:
            return theme.onAccent
        case .ghost:
            return theme.textPrimary
        case .tertiary:
            return theme.accent
        }
    }

    private var focusRingColor: Color {
        switch variant {
        case .primary, .secondary, .ghost:
            return theme.accent
        case .destructive:
            return theme.danger
        case .tertiary:
            return theme.accent
        }
    }

    private var spinnerColor: Color {
        switch variant {
        case .primary, .destructive:
            return theme.onAccent
        case .secondary, .ghost:
            return theme.accent
        case .tertiary:
            return theme.textSecondary
        }
    }

    // MARK: - Gesture

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if isInteractive {
                    isPressed = true
                }
            }
            .onEnded { _ in
                guard isPressed else { return }
                isPressed = false
                guard isInteractive, !reduceMotion else { return }
                isFlashing = true
                withAnimation(.easeOut(duration: 0.35)) {
                    isFlashing = false
                }
            }
    }

    // MARK: - Action

    private func performAction() {
        guard isInteractive else { return }
        action()
    }
}
