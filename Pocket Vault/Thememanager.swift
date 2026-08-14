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

    var accent: Color {
        switch self {
        case .champagneGold: return Color(red: 0.82, green: 0.72, blue: 0.52)
        case .ivoryWhite: return Color(red: 0.15, green: 0.15, blue: 0.16)
        case .obsidianBlack: return Color(red: 0.80, green: 0.80, blue: 0.84)
        case .emeraldGreen: return Color(red: 0.30, green: 0.78, blue: 0.55)
        case .sapphireBlue: return Color(red: 0.36, green: 0.60, blue: 0.96)
        case .crimsonRed: return Color(red: 0.85, green: 0.30, blue: 0.34)
        }
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
    var lightAccent: Color {
        switch self {
        case .champagneGold: return Color(red: 0.60, green: 0.47, blue: 0.24)
        case .ivoryWhite: return accent // already dark — reads great on a light background as-is
        case .obsidianBlack: return Color(red: 0.20, green: 0.20, blue: 0.24)
        case .emeraldGreen: return Color(red: 0.10, green: 0.55, blue: 0.35)
        case .sapphireBlue: return Color(red: 0.15, green: 0.35, blue: 0.75)
        case .crimsonRed: return Color(red: 0.72, green: 0.16, blue: 0.20)
        }
    }

    /// Contrast color for content drawn ON TOP OF this swatch specifically
    /// (e.g. the selection checkmark in ThemePickerSection) — computed
    /// the same way ThemeManager.onAccent is, so every swatch stays
    /// readable, including ivoryWhite's near-black accent where a fixed
    /// `.black` checkmark would disappear.
    var onSwatch: Color {
        UIColor(accent).isPerceptuallyLight ? .black : .white
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
        UIColor(accent).isPerceptuallyLight ? .black : .white
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

// MARK: - Luminance helper (used by ThemeManager.onAccent)

private extension UIColor {
    /// Standard relative-luminance check so button/pill text automatically
    /// flips between black and white depending on how light the
    /// background color actually is, instead of assuming every accent
    /// color is light like champagneGold was.
    var isPerceptuallyLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.6
    }
}

// MARK: - Shared CTA styles (unchanged behavior, now theme-driven only)

struct PrimaryCTAButtonStyle: ButtonStyle {
    var accent: Color
    var onAccent: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Inter-Bold", size: 13))
            .tracking(2.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(accent)
            .foregroundColor(onAccent)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(onAccent.opacity(configuration.isPressed ? 0.08 : 0.16), lineWidth: 1)
            )
            .shadow(
                color: accent.opacity(configuration.isPressed ? 0.18 : 0.65),
                radius: configuration.isPressed ? 6 : 22,
                y: configuration.isPressed ? 2 : 10
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct SecondaryCTAButtonStyle: ButtonStyle {
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Inter-Bold", size: 12))
            .tracking(2.2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(accent.opacity(configuration.isPressed ? 0.22 : 0.13))
            .foregroundColor(accent)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(accent.opacity(0.7), lineWidth: 1.6))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryCTAButtonStyle {
    static func primaryCTA(_ theme: ThemeManager) -> PrimaryCTAButtonStyle {
        PrimaryCTAButtonStyle(accent: theme.accent, onAccent: theme.onAccent)
    }
}

extension ButtonStyle where Self == SecondaryCTAButtonStyle {
    static func secondaryCTA(_ theme: ThemeManager) -> SecondaryCTAButtonStyle {
        SecondaryCTAButtonStyle(accent: theme.accent)
    }
}

// MARK: - Appearance Picker (embed in ProfileView, replaces ThemePickerSection)

struct ThemePickerSection: View {
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // No .foregroundStyle needed here at all — plain Text defaults
            // to .primary, which themedSurface(_:) below has already mapped
            // to theme.textPrimary for this whole subtree.
            Text("APPEARANCE")
                .font(theme.font(9, weight: .bold))
                .tracking(2)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 10) {
                Text("ACCENT COLOR")
                    .font(theme.font(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 14) {
                    ForEach(AppColorTheme.allCases) { option in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                theme.colorTheme = option
                            }
                        }) {
                            ZStack {
                                Circle().fill(option.accent).frame(width: 38, height: 38)
                                // Selection ring still needs the exact resolved
                                // color (it's animating an opacity, not just
                                // "the primary text color"), so this one stays
                                // as theme.textPrimary rather than .primary.
                                Circle()
                                    .stroke(theme.textPrimary.opacity(option == theme.colorTheme ? 0.9 : 0), lineWidth: 2)
                                    .frame(width: 46, height: 46)
                                if option == theme.colorTheme {
                                    Image(systemName: "checkmark").font(theme.font(12, weight: .black)).foregroundStyle(option.onSwatch)
                                }
                            }
                        }
                        .accessibilityLabel(option.displayName)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("APPEARANCE MODE")
                    .font(theme.font(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.tertiary)

                VStack(spacing: 8) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            theme.appearanceMode = mode
                        }) {
                            HStack {
                                Image(systemName: mode.icon).foregroundStyle(theme.accent).frame(width: 18)
                                // No explicit foregroundStyle — falls back to
                                // .primary automatically, which resolves to
                                // theme.textPrimary via themedSurface(_:).
                                Text(mode.displayName).font(theme.font(13, weight: .medium))
                                Spacer()
                                Image(systemName: mode == theme.appearanceMode ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(mode == theme.appearanceMode ? theme.accent : theme.textTertiary)
                            }
                            .padding(14)
                            .background(theme.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.cardStroke, lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.cardStroke, lineWidth: 1))
        .padding(.horizontal, 24)
        // This section is embedded inside ProfileView, which already calls
        // .themedSurface(theme) at its own root — so this nested call isn't
        // strictly required here. It's included so ThemePickerSection also
        // renders correctly if you ever preview or reuse it standalone,
        // outside ProfileView's tree.
        .themedSurface(theme, ignoresSafeArea: false)
    }
}
