import Foundation
import Network
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

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "PocketVault.NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
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
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(theme.cardStroke, lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
