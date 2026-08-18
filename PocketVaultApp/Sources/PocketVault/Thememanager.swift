import SwiftUI
import Combine

// MARK: - Color Theme

enum AppColorTheme: String, CaseIterable, Identifiable, Codable {
    case champagneGold
    case ivoryWhite
    case obsidianBlack
    case emeraldGreen
    case sapphireBlue
    case crimsonRed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .champagneGold: return "Champagne Gold"
        case .ivoryWhite: return "Ivory White"
        case .obsidianBlack: return "Obsidian Black"
        case .emeraldGreen: return "Emerald Green"
        case .sapphireBlue: return "Sapphire Blue"
        case .crimsonRed: return "Crimson"
        }
    }

    /// Raw components behind `accent`, kept alongside it (rather than
    /// re-deriving from the `Color` at use sites) so both the SwiftUI
    /// `Color` and the perceptual-luminance check below come from the
    /// exact same numbers — no UIColor component introspection needed,
    /// which Skip doesn't support on Android.
    var accentComponents: (r: Double, g: Double, b: Double) {
        switch self {
        case .champagneGold: return (0.82, 0.72, 0.52)
        case .ivoryWhite: return (0.15, 0.15, 0.16)
        case .obsidianBlack: return (0.80, 0.80, 0.84)
        case .emeraldGreen: return (0.30, 0.78, 0.55)
        case .sapphireBlue: return (0.36, 0.60, 0.96)
        case .crimsonRed: return (0.85, 0.30, 0.34)
        }
    }

    var accent: Color {
        let c = accentComponents
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// A deeper, more saturated take on `accent`, used only in light
    /// appearance mode. `accent` above was tuned to pop against the
    /// app's near-black dark background — several of those values
    /// (obsidianBlack's pale gray especially, champagneGold and
    /// emeraldGreen/sapphireBlue to a lesser degree) have very little
    /// luminance contrast against the light background and read as
    /// faint or nearly invisible there. This keeps each theme's hue
    /// identity but pulls luminance down so every theme stays legible
    /// in light mode too, without touching how anything looks in dark
    /// mode (`accent` itself is unchanged).
    var lightAccentComponents: (r: Double, g: Double, b: Double) {
        switch self {
        case .champagneGold: return (0.60, 0.47, 0.24)
        case .ivoryWhite: return accentComponents // already dark — reads great on a light background as-is
        case .obsidianBlack: return (0.20, 0.20, 0.24)
        case .emeraldGreen: return (0.10, 0.55, 0.35)
        case .sapphireBlue: return (0.15, 0.35, 0.75)
        case .crimsonRed: return (0.72, 0.16, 0.20)
        }
    }

    var lightAccent: Color {
        let c = lightAccentComponents
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// Standard relative-luminance check so button/pill text automatically
    /// flips between black and white depending on how light the
    /// background color actually is, instead of assuming every accent
    /// color is light like champagneGold was.
    private static func isPerceptuallyLight(_ c: (r: Double, g: Double, b: Double)) -> Bool {
        (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.6
    }

    /// Contrast color for content drawn ON TOP OF this swatch specifically
    /// (e.g. the selection checkmark in ThemePickerSection) — computed
    /// the same way ThemeManager.onAccent is, so every swatch stays
    /// readable, including ivoryWhite's near-black accent where a fixed
    /// `.black` checkmark would disappear.
    var onSwatch: Color {
        Self.isPerceptuallyLight(accentComponents) ? .black : .white
    }

    /// Same contrast check as `onSwatch`, but against whichever accent
    /// (`accent` or `lightAccent`) is actually resolved for the current
    /// appearance — see `ThemeManager.onAccent`.
    fileprivate func isAccentPerceptuallyLight(resolvedIsLight: Bool) -> Bool {
        Self.isPerceptuallyLight(resolvedIsLight ? lightAccentComponents : accentComponents)
    }
}

// MARK: - Appearance (Light / Dark / System)

/// Replaces the old "isLight per color theme" approach. Appearance is now
/// its own independent setting — any accent color can be paired with
/// light, dark, or "follow iOS Settings" — instead of light mode being
/// tied to one specific color theme (ivoryWhite).
enum AppAppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Match iOS Settings"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// nil tells SwiftUI's `.preferredColorScheme` to defer to the
    /// system setting instead of forcing one.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - ThemeManager

/// App-wide appearance preference: an accent color plus a light/dark/
/// system mode. Font is fixed app-wide to Inter — not user-selectable —
/// so `theme.font(_:weight:)` below is the ONLY place a font is chosen.
///
/// IMPORTANT — usage rule to actually get the accent color everywhere:
/// every screen must read `theme.accent` / `theme.font(...)` from this
/// object (injected via `.environmentObject(themeManager)`) instead of
/// hardcoding `Color(red: 0.82, green: 0.72, blue: 0.52)` or
/// `.system(..., design: .serif)` directly. Any view that hardcodes its
/// own color/font locally will NOT update when the user changes theme.
@MainActor
final class ThemeManager: ObservableObject {
    @Published var colorTheme: AppColorTheme {
        didSet { defaults.set(colorTheme.rawValue, forKey: colorKey) }
    }
    @Published var appearanceMode: AppAppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: appearanceKey) }
    }

    private let defaults = UserDefaults.standard
    private let colorKey = "pv_theme_color_v2"
    private let appearanceKey = "pv_theme_appearance_v1"

    init() {
        if let raw = defaults.string(forKey: colorKey), let theme = AppColorTheme(rawValue: raw) {
            colorTheme = theme
        } else {
            colorTheme = .champagneGold
        }
        if let raw = defaults.string(forKey: appearanceKey), let mode = AppAppearanceMode(rawValue: raw) {
            appearanceMode = mode
        } else {
            appearanceMode = .system
        }
    }

    // MARK: Derived tokens

    var accent: Color { resolvedIsLight ? colorTheme.lightAccent : colorTheme.accent }

    /// Same resolution `accent` does (light/dark-aware), but as raw RGB
    /// instead of a `Color` — for call sites that need to build a
    /// `UIColor` (e.g. BuildStudioView's 3D trim pieces). Go through
    /// this instead of trying to pull components back out of `accent`
    /// itself: neither `UIColor(Color)` nor `Color.resolve(in:)` is
    /// implemented by Skip's Android shim, so both fail there. These
    /// components are the same numbers `accent`/`lightAccent` are built
    /// from, just exposed before they're wrapped in a `Color`.
    var accentRGB: (r: Double, g: Double, b: Double) {
        resolvedIsLight ? colorTheme.lightAccentComponents : colorTheme.accentComponents
    }

    /// Resolved at the SwiftUI environment level via `.preferredColorScheme`
    /// (see Pocket_VaultApp.swift) — this flag just lets views that need to
    /// branch on light/dark read the CURRENT resolved value. For system
    /// mode this reflects the environment's actual scheme, updated below.
    @Published var resolvedIsLight: Bool = false

    var background: Color { resolvedIsLight ? Color(red: 0.97, green: 0.965, blue: 0.95) : Color(red: 0.06, green: 0.07, blue: 0.09) }
    var textPrimary: Color { resolvedIsLight ? Color.black.opacity(0.95) : .white }
    var textSecondary: Color { resolvedIsLight ? Color.black.opacity(0.62) : .white.opacity(0.68) }
    var textTertiary: Color { resolvedIsLight ? Color.black.opacity(0.42) : .white.opacity(0.42) }
    var hairline: Color { resolvedIsLight ? Color.black.opacity(0.12) : Color.white.opacity(0.1) }
    var cardStroke: Color { resolvedIsLight ? Color.black.opacity(0.1) : Color.white.opacity(0.1) }
    var isLight: Bool { resolvedIsLight }

    /// The text/icon color to use ON TOP of `accent` (e.g. CTA button
    /// labels). Computed from accent's perceptual luminance rather than
    /// hardcoded to black — champagneGold/emeraldGreen/sapphireBlue are
    /// light enough for black text, but obsidianBlack's accent is a pale
    /// gray and ivoryWhite's accent is near-black, so a fixed `.black`
    /// silently produces unreadable buttons for those two themes.
    var onAccent: Color {
        colorTheme.isAccentPerceptuallyLight(resolvedIsLight: resolvedIsLight) ? .black : .white
    }

    // Same "dark values unchanged, light values deepened for contrast"
    // treatment as `accent` above — these are used as direct icon/text
    // colors (budget alerts, streak deltas, etc.), so a pale warning
    // orange or minty green that's fine on a near-black background
    // becomes hard to read against the light one.
    var success: Color { resolvedIsLight ? Color(red: 0.16, green: 0.5, blue: 0.28) : Color(red: 0.35, green: 0.78, blue: 0.5) }
    var warning: Color { resolvedIsLight ? Color(red: 0.72, green: 0.45, blue: 0.08) : Color(red: 0.92, green: 0.68, blue: 0.3) }
    var danger: Color { resolvedIsLight ? Color(red: 0.74, green: 0.18, blue: 0.18) : Color(red: 0.86, green: 0.32, blue: 0.32) }

    // MARK: Font — fixed to Inter app-wide, not user-configurable.
    // Requires Inter-Regular.ttf / Inter-Medium.ttf / Inter-SemiBold.ttf /
    // Inter-Bold.ttf added to the target and registered in Info.plist
    // under "Fonts provided by application" (UIAppFonts). See SETUP_NOTES.md.
    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let postscriptName: String
        switch weight {
        case .bold, .heavy, .black: postscriptName = "Inter-Bold"
        case .semibold: postscriptName = "Inter-SemiBold"
        case .medium: postscriptName = "Inter-Medium"
        default: postscriptName = "Inter-Regular"
        }
        return .custom(postscriptName, size: size)
    }

    /// Call from the top-level view's `.onChange(of: colorScheme)` so
    /// `resolvedIsLight` tracks reality even in `.system` mode.
    func updateResolvedScheme(_ scheme: ColorScheme) {
        resolvedIsLight = (scheme == .light)
    }
}

// MARK: - Layout tokens
//
// One shared spacing/radius scale so every screen's outer padding, card
// radius, and CTA width line up with each other and with the floating
// dock — instead of screens picking their own one-off numbers (e.g. a
// full-width CTA at `.padding(.horizontal, Layout.pageMargin)` sitting above a dock at
// `.padding(.horizontal, 14)`, which is what made the two look like they
// belonged to different apps).
//
// NOTE: literals below are written as `20.0` rather than `20` — Swift
// happily infers an Int literal as CGFloat, but Skip's Kotlin
// transpilation does not do that implicit widening, so every literal
// that ends up in a CGFloat/Double slot in this file is spelled out
// explicitly (same reasoning applies to every `.padding`, `.frame`,
// `.cornerRadius`, `theme.font(...)`, spacing, and shadow value below).
enum Layout {
    /// Standard left/right screen margin. Use this — not a bespoke
    /// number — for page content, section cards, and full-width CTAs so
    /// they all share one edge and visually line up with the dock below.
    static let pageMargin: CGFloat = 20.0
    static let cardRadius: CGFloat = 20.0
    static let controlRadius: CGFloat = 16.0
    static let sectionSpacing: CGFloat = 24.0
    static let cardPadding: CGFloat = 18.0
}

// MARK: - Shared CTA styles
//
// SwiftUI's `ButtonStyle` protocol — where you conform a type to it and
// implement `makeBody(configuration:)`, reading `configuration.label` /
// `.isPressed` — isn't supported by Skip. That mismatch is exactly what
// produced the whole error cluster on the old structs here: "This type
// is final, so it cannot be extended" (Skip's ButtonStyle isn't an open
// protocol you can add conformances to), "Explicit 'this' or 'super'
// call is required" and "Property must be initialized" (the generated
// Kotlin class has no matching constructor), and "Unresolved reference
// 'Configuration' / 'label' / 'isPressed'" (that associated type isn't
// modeled at all). Skip only supports the built-in styles (`.plain`,
// `.bordered`, etc.), not custom ones.
//
// These three replace the old ButtonStyle structs with plain views that
// wrap `Button` directly and track their own pressed state with a
// zero-distance `DragGesture` — same look, same spring/opacity behavior,
// no protocol conformance for Skip to choke on.
//
// Sentence case, not all-caps tracked text — reserve letter-spacing for
// cases that actually need it (rare). A single neutral shadow instead of
// a color-matched glow, so the button reads as "the thing to tap next",
// not as a light source. Radius/height come from `Layout`.

struct PrimaryCTAButton<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    var accent: Color
    var onAccent: Color = .black
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            label()
                .font(Font.custom("Inter-SemiBold", size: 16.0))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17.0)
                .background(accent)
                .foregroundColor(onAccent)
                .cornerRadius(Layout.controlRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.controlRadius)
                        .stroke(onAccent.opacity(isPressed ? 0.06 : 0.12), lineWidth: 1.0)
                )
                .shadow(
                    color: Color.black.opacity(isEnabled ? (isPressed ? 0.08 : 0.18) : 0.0),
                    radius: isPressed ? 4.0 : 14.0,
                    y: isPressed ? 2.0 : 6.0
                )
                .opacity(isEnabled ? 1.0 : 0.4)
                .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}

struct SecondaryCTAButton<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    var accent: Color
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            label()
                .font(Font.custom("Inter-SemiBold", size: 15.0))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15.0)
                .background(accent.opacity(isPressed ? 0.2 : 0.12))
                .foregroundColor(accent)
                .cornerRadius(Layout.controlRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.controlRadius)
                        .stroke(accent.opacity(0.5), lineWidth: 1.2)
                )
                .opacity(isEnabled ? 1.0 : 0.4)
                .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}

/// For the one action on a screen that shouldn't compete visually with
/// the primary CTA — no fill, no stroke, just text. Use this instead of
/// giving a tertiary action its own bordered/uppercase button treatment.
struct TertiaryCTAButton<Label: View>: View {
    var color: Color
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            label()
                .font(Font.custom("Inter-Medium", size: 15.0))
                .foregroundColor(color)
                .opacity(isPressed ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Screen Header
//
// One consistent anchor at the top of every multi-step / tab screen: a
// real title (not a small floating uppercase label) plus a stable spot
// for a settings/profile action on the trailing edge. Screens that skip
// this are the ones that feel "haphazard" — the eye has nowhere
// consistent to land first.
struct ScreenHeader<Trailing: View>: View {
    @EnvironmentObject var theme: ThemeManager
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: Trailing

    /// NOTE: no default value on `trailing`, and no `Trailing ==
    /// EmptyView` convenience init either — both were tried and both
    /// fail under Skip, for two different reasons:
    /// - A default like `{ EmptyView() }` on a @ViewBuilder closure
    ///   typed to a generic `Trailing` works in plain Swift (the
    ///   compiler specializes `Trailing` per call site), but Skip's
    ///   Kotlin transpiler doesn't do that specialization, producing
    ///   "Return type mismatch: expected 'Trailing'... got 'EmptyView'".
    /// - A `where Trailing == EmptyView` constrained extension avoids
    ///   that, but Skip can't merge a generically-constrained extension
    ///   into the Kotlin class it generates for `ScreenHeader`, producing
    ///   "This extension cannot be merged into its extended Kotlin type
    ///   definition because it has generic constraints".
    ///
    /// So: `trailing` is just always required. At call sites with no
    /// trailing content, write `ScreenHeader("Title") { EmptyView() }`
    /// explicitly instead of relying on a default or an overload.
    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4.0) {
                Text(title)
                    .font(theme.font(28.0, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(theme.font(14.0, weight: .regular))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, Layout.pageMargin)
        .padding(.top, 8.0)
        .padding(.bottom, 4.0)
    }
}

/// Small circular icon button used in a `ScreenHeader`'s trailing slot
/// (settings, profile, close). Kept as one shared shape so every header
/// action looks the same everywhere it appears.
struct HeaderIconButton: View {
    @EnvironmentObject var theme: ThemeManager
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(theme.font(15.0, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 38.0, height: 38.0)
                .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                .cornerRadius(19.0)
        }
    }
}

// MARK: - Section label
//
// Replaces the ad hoc "uppercase, tracked, tertiary" label that was
// hand-copied at every call site. Sentence case reads faster and looks
// intentional rather than stamped; kept small and secondary so it still
// functions as a quiet section eyebrow, not a heading.
struct SectionLabel: View {
    @EnvironmentObject var theme: ThemeManager
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(theme.font(12.0, weight: .semibold))
            .foregroundStyle(theme.textSecondary)
    }
}

// MARK: - Badge
//
// One reusable pill for short status/meta labels (PRO, streak counts,
// category tags, "over budget", etc.) — sentence case, soft tinted
// fill instead of an all-caps outline, so badges read as gentle status
// chips instead of shouting for attention.
struct Badge: View {
    @EnvironmentObject var theme: ThemeManager
    let text: String
    var icon: String? = nil
    var tint: Color? = nil
    var prominent: Bool = false

    var body: some View {
        let color = tint ?? theme.accent
        HStack(spacing: 4.0) {
            if let icon {
                Image(systemName: icon).font(theme.font(11.0, weight: .semibold))
            }
            Text(text).font(theme.font(12.0, weight: .semibold))
        }
        .foregroundStyle(prominent ? theme.onAccent : color)
        .padding(.horizontal, 10.0)
        .padding(.vertical, 5.0)
        .background(prominent ? color : color.opacity(0.14))
        // A large fixed radius reads as a capsule regardless of the
        // pill's actual height — SwiftUI/Compose both clamp the corner
        // radius to half the shorter side, so this can't overshoot.
        .cornerRadius(999.0)
    }
}

// MARK: - Appearance Picker (embed in ProfileView, replaces ThemePickerSection)

struct ThemePickerSection: View {
    @EnvironmentObject var theme: ThemeManager

    /// Cross-platform stand-in for `.ultraThinMaterial` — see
    /// SharedBudgetView.swift for why materials don't transpile.
    private var cardFill: Color { theme.cardStroke.opacity(0.35) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16.0) {
            SectionLabel("Appearance")

            VStack(alignment: .leading, spacing: 10.0) {
                SectionLabel("Accent color")

                HStack(spacing: 14.0) {
                    ForEach(AppColorTheme.allCases) { option in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                theme.colorTheme = option
                            }
                        }) {
                            ZStack {
                                Circle().fill(option.accent).frame(width: 38.0, height: 38.0)
                                // Selection ring still needs the exact resolved
                                // color (it's animating an opacity, not just
                                // "the primary text color"), so this one stays
                                // as theme.textPrimary rather than .primary.
                                Circle()
                                    .stroke(theme.textPrimary.opacity(option == theme.colorTheme ? 0.9 : 0.0), lineWidth: 2.0)
                                    .frame(width: 46.0, height: 46.0)
                                if option == theme.colorTheme {
                                    Image(systemName: "checkmark").font(theme.font(12.0, weight: .black)).foregroundStyle(option.onSwatch)
                                }
                            }
                        }
                        .accessibilityLabel(option.displayName)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10.0) {
                SectionLabel("Appearance mode")

                VStack(spacing: 8.0) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            theme.appearanceMode = mode
                        }) {
                            HStack {
                                Image(systemName: mode.icon).foregroundStyle(theme.accent).frame(width: 18.0)
                                // No explicit foregroundStyle — falls back to
                                // .primary automatically, which resolves to
                                // theme.textPrimary via themedSurface(_:).
                                Text(mode.displayName).font(theme.font(13.0, weight: .medium))
                                Spacer()
                                Image(systemName: mode == theme.appearanceMode ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(mode == theme.appearanceMode ? theme.accent : theme.textTertiary)
                            }
                            .padding(14.0)
                            .background(theme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.05))
                            .cornerRadius(12.0)
                            .overlay(RoundedRectangle(cornerRadius: 12.0).stroke(theme.cardStroke, lineWidth: 1.0))
                        }
                    }
                }
            }
        }
        .padding(20.0)
        .background(cardFill)
        .cornerRadius(20.0)
        .overlay(RoundedRectangle(cornerRadius: 20.0).stroke(theme.cardStroke, lineWidth: 1.0))
        .padding(.horizontal, Layout.pageMargin)
        // This section is embedded inside ProfileView, which already calls
        // .themedSurface() at its own root — so this nested call isn't
        // strictly required here. It's included so ThemePickerSection also
        // renders correctly if you ever preview or reuse it standalone,
        // outside ProfileView's tree.
        //
        // No `theme` argument here — themedSurface() now reads ThemeManager
        // via @EnvironmentObject internally instead of taking it as a
        // parameter (see ThemedSurface.swift).
        .themedSurface(ignoresSafeArea: false)
    }
}
