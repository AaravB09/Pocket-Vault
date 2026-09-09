import SwiftUI

// MARK: - VaultButtonVariant

/// Visual style for a `VaultButton`.
public enum VaultButtonVariant {
    /// Solid accent fill with theme-aware text on top.
    case primary
    /// Tinted accent fill with accent text — no border.
    case secondary
    /// Solid danger-red fill with high-contrast text.
    case destructive
    /// Fully transparent with a subtle tinted fill on hover/press.
    case ghost
    /// Fully transparent text-only button — no fill, no stroke.
    /// Disabled/loading states are expressed through opacity alone.
    case tertiary
    /// Subtle tinted card fill, no border, with primary-colored
    /// text — used for OAuth-redirect sign-in buttons (Google, Apple on
    /// Android) where the provider's own brand fill/logo isn't rendered.
    case social
}

// MARK: - VaultButton

public struct VaultButton: View {

    // MARK: Public default values
    public static let defaultHeight: CGFloat = Layout.height
    public static let defaultHorizontalPadding: CGFloat = Layout.horizontalPadding

    // MARK: Injected dependencies

    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isEnabled) private var isEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    // MARK: Parameters

    private let variant: VaultButtonVariant
    private let action: () -> Void
    private var isLoading: Bool = false
    private var height: CGFloat = Layout.height
    private var fontSize: CGFloat = 15.0
    private var fontWeight: Font.Weight = .semibold
    private var horizontalPadding: CGFloat = Layout.horizontalPadding
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
        height: CGFloat = VaultButton.defaultHeight,
        fontSize: CGFloat = 15.0,
        fontWeight: Font.Weight = .semibold,
        horizontalPadding: CGFloat = VaultButton.defaultHorizontalPadding,
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
        height: CGFloat = VaultButton.defaultHeight,
        fontSize: CGFloat = 15.0,
        fontWeight: Font.Weight = .semibold,
        horizontalPadding: CGFloat = VaultButton.defaultHorizontalPadding,
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
        height: CGFloat = VaultButton.defaultHeight,
        fontSize: CGFloat = 15.0,
        fontWeight: Font.Weight = .semibold,
        horizontalPadding: CGFloat = VaultButton.defaultHorizontalPadding,
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
        case .social:
            return theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08)
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
        case .social:
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
        case .social:
            return theme.textPrimary
        }
    }

    private var neutralFillColor: Color {
        Color(white: 0.5).opacity(0.28)
    }

    private var neutralContentColor: Color {
        Color(white: 0.5)
    }

    private var shadowColor: Color {
        guard variant != .tertiary, variant != .social else { return Color.clear }
        return Color.black.opacity(isInteractive ? (isPressed ? 0.08 : 0.18) : 0.0)
    }

    private var shadowRadius: CGFloat {
        guard variant != .tertiary, variant != .social else { return 0.0 }
        return isPressed ? 4.0 : 14.0
    }

    private var shadowY: CGFloat {
        guard variant != .tertiary, variant != .social else { return 0.0 }
        return isPressed ? 2.0 : 6.0
    }

    // MARK: - Body

    public var body: some View {
        Button(action: performAction) {
            ZStack {
                label
                    .font(theme.font(fontSize, weight: fontWeight))
                    .foregroundStyle(contentColor)
                    .opacity(isLoading ? 0.0 : 1.0)
                    .animation(Animation.easeOut(duration: 0.18), value: isLoading)

                if isLoading {
                    ProgressView()
                        .tint(spinnerColor)
                }
            }
            .frame(height: height)
            .frame(maxWidth: fullWidth ? CGFloat.infinity : nil)
            .padding(Edge.Set.horizontal, horizontalPadding)
            .background {
                ZStack {
                    backgroundLayer
                    flashOverlay
                }
            }
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
        .animation(Animation.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .animation(Animation.easeOut(duration: 0.15), value: isEnabled)
        .animation(Animation.easeOut(duration: 0.2), value: isLoading)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var backgroundLayer: some View {
        RoundedRectangle(cornerRadius: Layout.controlRadius, style: RoundedCornerStyle.continuous)
            .fill(backgroundFillColor)
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                y: shadowY
            )
    }

    @ViewBuilder
    private var flashOverlay: some View {
        RoundedRectangle(cornerRadius: Layout.controlRadius, style: RoundedCornerStyle.continuous)
            .fill(flashFillColor)
            .opacity(isFlashing ? 0.18 : 0.0)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var focusRing: some View {
        RoundedRectangle(cornerRadius: Layout.controlRadius + 3.0, style: RoundedCornerStyle.continuous)
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
        case .social:
            return theme.textPrimary
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
        case .social:
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
        case .social:
            return theme.textPrimary
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
                withAnimation(Animation.easeOut(duration: 0.35)) {
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
