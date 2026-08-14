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
    func themedSurface(_ theme: ThemeManager, ignoresSafeArea: Bool = true) -> some View {
        self
            .foregroundStyle(theme.textPrimary, theme.textSecondary, theme.textTertiary)
            .background {
                if ignoresSafeArea {
                    theme.background.ignoresSafeArea()
                } else {
                    theme.background
                }
            }
    }
}
