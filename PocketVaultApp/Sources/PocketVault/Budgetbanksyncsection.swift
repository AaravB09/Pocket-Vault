import SwiftUI
#if !SKIP
import LinkKit
#endif

/// Drop this into your Budget tab (wherever BudgetManager's UI lives).
/// Bank sync is a Pro feature — same lockedState pattern AIChatView uses
/// for Ask AI — so free/guest users see an upsell card instead of the
/// Connect Bank button, and can't trigger a Plaid Link session at all.
struct BudgetBankSyncSection: View {
    @EnvironmentObject var entitlementManager: EntitlementManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var leaderboardManager: LeaderboardManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @ObservedObject var budgetManager: BudgetManager
    @StateObject private var plaid = PlaidConnectionManager()

    @State private var showPaywall = false
    
    // 1. Hide the Apple-only presenter variable from Android
    #if !SKIP
    @State private var linkPresenter = PlaidLinkPresenter()
    #endif

    var body: some View {
        Group {
            if entitlementManager.isPro {
                connectedState
            } else {
                lockedState
            }
        }
        .task {
            // Only worth checking/syncing for Pro users with a connection
            // — avoids a pointless network call for everyone else, and
            // for anyone offline, on every appear. Guests have no real
            // session (authManager.accessToken is nil for them), so
            // syncTransactions no-ops for them rather than hitting the
            // backend with an unverifiable identity.
            if entitlementManager.isPro && networkMonitor.isOnline {
                await plaid.syncTransactions(accessToken: authManager.accessToken, into: budgetManager)
            }
        }
    }

    // MARK: - Pro: real Connect Bank flow
    private var connectedState: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "building.columns.fill")
                    .font(theme.font(15))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BANK SYNC")
                        .font(theme.font(10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(theme.textPrimary)
                    Text(plaid.isConnected ? "Connected — new transactions import automatically" : "Connect a bank to auto-log spending")
                        .font(theme.font(11, weight: .light))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
            }

            Button(action: {
                Task {
                    if plaid.isConnected {
                        await plaid.syncTransactions(accessToken: authManager.accessToken, into: budgetManager)
                    } else {
                        // 2. Hide the Apple-only presentation logic from Android
                        #if !SKIP
                        await plaid.startConnection(accessToken: authManager.accessToken) { config in
                            linkPresenter.present(config: config)
                        }
                        #endif
                    }
                }
            }) {
                HStack {
                    if plaid.isConnecting || plaid.isSyncing { ProgressView().tint(theme.onAccent) }
                    Text(plaid.isConnected ? "SYNC NOW" : "CONNECT BANK")
                        .font(theme.font(12, weight: .bold))
                        .tracking(2.4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(theme.accent)
                .foregroundColor(theme.onAccent)
                .clipShape(Capsule())
                .shadow(color: theme.accent.opacity(0.4), radius: 14, y: 6)
            }
            .disabled(plaid.isConnecting || plaid.isSyncing || !networkMonitor.isOnline)
            .opacity(networkMonitor.isOnline ? 1 : 0.5)

            if !networkMonitor.isOnline {
                Text("Bank sync needs a connection — log payments by hand until you're back online.")
                    .font(theme.font(11))
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
            } else if let errorMessage = plaid.errorMessage {
                Text(errorMessage)
                    .font(theme.font(11))
                    .foregroundStyle(theme.danger.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.cardStroke, lineWidth: 1))
    }

    // MARK: - Free/guest: upsell card, no Plaid session possible
    private var lockedState: some View {
        Button(action: { showPaywall = true }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(theme.accent.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: "lock.fill").font(theme.font(13)).foregroundStyle(theme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("BANK SYNC — PRO")
                        .font(theme.font(10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(theme.textPrimary)
                    Text("Auto-import spending instead of logging by hand")
                        .font(theme.font(11, weight: .light))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(theme.font(11, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.cardStroke, lineWidth: 1))
        }
        .sheet(isPresented: $showPaywall) {
            // 3. Make the Binding type explicit so Skip understands it
            CustomPaywallView(
                goalTitle: "",
                targetGoal: 0,
                currentSavings: 0,
                chatMessages: Binding.constant([]),
                selectedTab: Binding.constant(0)
            )
        }
    }
}

// 4. Wrap the entire UIKit-dependent class in !SKIP
#if !SKIP
/// Thin wrapper around LinkKit's Handler so PlaidConnectionManager (a
/// plain ObservableObject) doesn't need to know about UIKit presentation.
@MainActor
final class PlaidLinkPresenter {
    private var session: PlaidLinkSession?

    func present(config: LinkTokenConfiguration) {
        do {
            let session = try Plaid.createPlaidLinkSession(configuration: config)
            self.session = session

            guard let root = Self.topViewController() else { return }
            session.open(using: .viewController(root))
        } catch {
            print("Plaid Link creation failed:", error)
        }
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
#endif
