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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    var body: some View {
        Button(action: { privacy.reveal() }) {
            VStack(spacing: 6) {
                Image(systemName: "eye.slash.fill")
                    .font(theme.font(16, weight: .semibold))
                Text("TAP TO REVEAL")
                    .font(theme.font(9, weight: .bold))
                    .tracking(2)
            }
            .foregroundStyle(.secondary)
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
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

    var body: some View {
        if privacy.isPrivacyModeOn {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if privacy.isRevealed {
                    privacy.isRevealed = false
                } else {
                    privacy.reveal()
                }
            }) {
                Image(systemName: privacy.shouldMask ? "eye.slash.fill" : "eye.fill")
                    .font(theme.font(14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(theme.cardStroke, lineWidth: 1))
            }
        }
    }
}
