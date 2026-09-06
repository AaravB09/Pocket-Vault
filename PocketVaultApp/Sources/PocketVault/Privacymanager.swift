import SwiftUI
import Combine

/// App-wide "Privacy Mode": when on, dollar amounts across the app render
/// blurred until the user explicitly taps to reveal them. This is the
/// on-device piece of a "your numbers stay yours" philosophy — nobody
/// glancing at your screen on a train sees your balance unless you choose
/// to show it. Not namespaced per-account like GoalStore/BudgetManager —
/// it's a device-level UI preference, same treatment as ThemeManager.
@MainActor
final class PrivacyManager: ObservableObject {
    @Published var isPrivacyModeOn: Bool { didSet { defaults.set(isPrivacyModeOn, forKey: key) } }
    /// Momentary reveal while Privacy Mode is on. Deliberately NOT
    /// persisted — every fresh launch starts hidden again if Privacy
    /// Mode is enabled.
    @Published var isRevealed: Bool = false {
        didSet { if isRevealed { autoRehide() } }
    }

    private let defaults = UserDefaults.standard
    private let key = "pv_privacyModeOn_v1"
    private var rehideTask: Task<Void, Never>?

    init() {
        isPrivacyModeOn = defaults.bool(forKey: key)
    }

    var shouldMask: Bool { isPrivacyModeOn && !isRevealed }

    func reveal() {
        #if !SKIP
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        isRevealed = true
    }

    /// Reveals stay open for a short window rather than indefinitely —
    /// closer to how a lock-screen notification preview behaves than a
    /// toggle you have to remember to flip back.
    private func autoRehide() {
        rehideTask?.cancel()
        rehideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            self?.isRevealed = false
        }
    }
}

/// Drop-in overlay for any card whose content is currently blurred by
/// Privacy Mode. Tapping it reveals — same interaction everywhere in
/// the app so it never has to be re-explained.
struct PrivacyRevealOverlay: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var privacy: PrivacyManager

    public var body: some View {
        Button(action: { privacy.reveal() }) {
            VStack(spacing: 6) {
                Image.platformSymbol("eye.slash.fill", android: "lock.fill")
                    .font(theme.font(16, weight: Font.Weight.semibold))
                Text("Tap to reveal")
                    .font(theme.font(11, weight: Font.Weight.semibold))
            }
            #if !SKIP
            .foregroundStyle(HierarchicalShapeStyle.secondary)
            #else
            .foregroundStyle(Color.secondary)
            #endif
            .padding(14)
            // NOTE(skip): `.ultraThinMaterial` and `.clipShape` aren't
            // resolved by Skip's SwiftUI shim — iOS keeps the real
            // material + shape clip, Android gets a plain tinted
            // background + `.cornerRadius`, same pattern used everywhere
            // else in the app (LoginView, MainTabView, etc.).
            #if !SKIP
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            #else
            .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
            .cornerRadius(14)
            #endif
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.cardStroke, lineWidth: 1))
        }
    }
}

/// Small header button that only appears once Privacy Mode is turned on
/// (in Profile), for quickly flipping the current reveal state without
/// digging back into settings.
struct PrivacyQuickToggleButton: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var privacy: PrivacyManager

    public var body: some View {
        if privacy.isPrivacyModeOn {
            Button(action: {
                #if !SKIP
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                if privacy.isRevealed {
                    privacy.isRevealed = false
                } else {
                    privacy.reveal()
                }
            }) {
                Image.platformSymbol(privacy.shouldMask ? "eye.slash.fill" : "eye.fill", android: privacy.shouldMask ? "lock.fill" : "checkmark.circle")
                    .font(theme.font(14, weight: Font.Weight.medium))
                    #if !SKIP
                    .foregroundStyle(HierarchicalShapeStyle.secondary)
                    #else
                    .foregroundStyle(Color.secondary)
                    #endif
                    .frame(width: 36, height: 36)
                    // NOTE(skip): same `.ultraThinMaterial`/`.clipShape`
                    // gap as PrivacyRevealOverlay above. `.clipShape(Circle())`
                    // isn't resolved under Skip either, so Android gets
                    // `.cornerRadius` at half the frame's width/height,
                    // which renders as a circle on a square frame just
                    // like the real clip does.
                    #if !SKIP
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    #else
                    .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                    .cornerRadius(18)
                    #endif
                    .overlay(Circle().stroke(theme.cardStroke, lineWidth: 1))
            }
        }
    }
}
