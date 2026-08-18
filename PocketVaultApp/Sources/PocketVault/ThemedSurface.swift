import SwiftUI

// MARK: - Themed Surface

extension View {
    /// Applies the current theme to this subtree in one call.
    ///
    /// This does two things:
    /// 1. Sets `theme.background` as this view's background.
    /// 2. Calls `.foregroundStyle(primary, secondary, tertiary)`, which makes
    ///    `.foregroundStyle(.primary)` / `.secondary` / `.tertiary` — AND the
    ///    default color SwiftUI gives a plain `Text`/`Image` when you set no
    ///    style at all — resolve to `theme.textPrimary` / `.textSecondary` /
    ///    `.textTertiary` for every descendant view, automatically.
    ///
    /// Apply this ONCE near the root of each screen (the outermost
    /// ZStack/VStack in that screen's `body`) instead of threading
    /// `theme.textPrimary` etc. down to every individual Text. Nested
    /// views still take `theme` as an `@EnvironmentObject` when they need
    /// tokens beyond plain text color — `theme.accent`, `theme.font(...)`,
    /// `theme.cardStroke`, and so on aren't covered by this, only the
    /// primary/secondary/tertiary text-color plumbing and the background.
    ///
    /// Sheets, full-screen covers, and other presented content inherit
    /// environment values (including foreground style) from the view that
    /// presents them, so you generally don't need to call this again
    /// inside a `.sheet { ... }` closure — but DO call it again at the
    /// root of any screen that can be reached WITHOUT going through a
    /// parent that already called it (e.g. a screen pushed onto its own
    /// NavigationStack, or anything previewed standalone).
    ///
    /// - Parameter ignoresSafeArea: pass `false` if this screen's background
    ///   should stop at the safe area instead of bleeding under it (rare —
    ///   most full-screen views want the default `true`).
    ///
    /// NOTE: this reads `ThemeManager` via `@EnvironmentObject` inside
    /// `ThemedSurfaceModifier` rather than taking it as a parameter here.
    /// That keeps `ThemeManager` out of this function's signature, so it
    /// can stay `internal` even though this extension itself has to be
    /// `public` to be callable across the package boundary (Swift won't
    /// let a `public` function expose an `internal` parameter type —
    /// that's the "'public' function exposes its 'internal' parameter
    /// type" error). Requires `ThemeManager` to already be injected
    /// higher up via `.environmentObject(theme)` before this is called.
    public func themedSurface(ignoresSafeArea: Bool = true) -> some View {
        modifier(ThemedSurfaceModifier(ignoresSafeArea: ignoresSafeArea))
    }
}

private struct ThemedSurfaceModifier: ViewModifier {
    @EnvironmentObject private var theme: ThemeManager
    let ignoresSafeArea: Bool

    func body(content: Content) -> some View {
        content
            // The 3-argument hierarchical .foregroundStyle(primary:secondary:tertiary:)
            // isn't implemented by Skip, so Android falls back to just the
            // primary color here — screens that need the secondary/tertiary
            // distinction already reference those tokens explicitly (see
            // the doc comment above).
            #if !SKIP
            .foregroundStyle(theme.textPrimary, theme.textSecondary, theme.textTertiary)
            #else
            .foregroundStyle(theme.textPrimary)
            #endif
            .background {
                if ignoresSafeArea {
                    theme.background.ignoresSafeArea()
                } else {
                    theme.background
                }
            }
    }
}
