import Foundation
#if !SKIP
import Network
#endif
import Combine
import SwiftUI

/// Tracks whether the device currently has a network path. Core Pocket
/// Vault data (goals, budget, savings history) already lives entirely in
/// UserDefaults via GoalStore/BudgetManager, so none of that needs this —
/// it's purely for the few features that genuinely require a connection
/// (bank sync, Ask AI, leaderboard), so they can say "you're offline"
/// up front instead of spinning or timing out.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnline: Bool = true

    #if !SKIP
    private let monitor: NWPathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "PocketVault.NetworkMonitor")
    #endif

    init() {
        #if !SKIP
        monitor.pathUpdateHandler = { [weak self] path in
            // Explicitly defining NWPath.Status for clarity, though #if !SKIP
            // already protects it from Kotlin's strict type checker.
            let online = path.status == NWPath.Status.satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
        #endif
    }

    deinit {
        #if !SKIP
        monitor.cancel()
        #endif
    }
}

/// A slim, dismiss-on-reconnect banner reminding the user that core
/// tracking still works — meant to reassure, not alarm, since going
/// offline in this app costs you nothing but a couple of sync features.
struct OfflineBanner: View {
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(theme.font(11, weight: .bold))
            Text("Offline — goals & budget still editable")
                .font(theme.font(12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // NOTE(skip): .ultraThinMaterial has no Android/Compose equivalent
        // and was unresolved — which was cascading into the .clipShape
        // right below it too. Only the material itself needs branching;
        // .clipShape(Capsule()) resolves fine on Skip once it isn't
        // chained directly after a broken symbol (see MainTabView's tab
        // bar, which does exactly this).
        #if !SKIP
        .background(.ultraThinMaterial)
        #else
        .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
        #endif
        .clipShape(Capsule())
        .overlay(Capsule().stroke(theme.cardStroke, lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
