import SwiftUI

// MARK: - Platform Symbol
//
// Skip's Android renderer has no access to Apple's real SF Symbols. It only
// maps a small curated list of names to Compose Material icons (see
// https://skip.tools/docs/modules/skip-ui/#fallback-symbols); anything
// outside that list silently falls back to a warning-triangle glyph. That's
// the "caution marker" showing up throughout the app on Android — it's not
// an error state, it's Image(systemName:) rendering "symbol not found."
//
// For names with no reasonable Material equivalent (cpu, car.side, shield,
// cube.fill, hammer.fill, target, chart.pie.fill, person.2.fill, sparkles,
// etc.) use `Image.platformSymbol(_:android:)` below to keep the exact,
// correct SF Symbol on iOS while substituting a supported stand-in on
// Android. For names where Skip's fallback table already contains a
// visually-equivalent REAL SF Symbol (e.g. "arrow.right" -> "arrow.forward"),
// just rename the call site directly instead — no split needed.
//
// This is a stand-in, not a long-term fix: the proper fix per Skip's docs is
// exporting the real symbol as an SVG from Apple's SF Symbols app into
// Module.xcassets and loading it with Image("name", bundle: .module), which
// renders the exact original icon on Android too. That requires the SF
// Symbols desktop app, so it isn't done here — this keeps both platforms
// looking correct in the meantime.
extension Image {
    static func platformSymbol(_ iosName: String, android androidName: String) -> Image {
        #if SKIP
        return Image(systemName: androidName)
        #else
        return Image(systemName: iosName)
        #endif
    }
}
