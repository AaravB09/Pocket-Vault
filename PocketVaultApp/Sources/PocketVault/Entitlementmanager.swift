import Foundation
#if !SKIP
import RevenueCat
#endif
import Combine

#if !SKIP
@MainActor
final class EntitlementManager: NSObject, ObservableObject, PurchasesDelegate {
    @Published var isPro: Bool = false

    private let proEntitlementID = "pro"

    override init() {
        super.init()
        Purchases.shared.delegate = self
        Task { await refresh() }
    }

    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["POCKET_VAULT_FORCE_PRO"] == "1" {
            isPro = true
            return
        }
        #endif

        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
        } catch {
            // Leave isPro at its last known value rather than assuming false.
        }
    }

    /// Debug-only: rotates RevenueCat to a brand-new anonymous test
    /// identity so a fresh purchase flow can be re-run from scratch.
    func resetTestAccount() async {
        _ = try? await Purchases.shared.logOut()
        await refresh()
    }

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.apply(customerInfo)
        }
    }

    private func apply(_ info: CustomerInfo) {
        let active = info.entitlements[proEntitlementID]?.isActive == true
        isPro = active

        #if DEBUG
        if !active && !info.allPurchasedProductIdentifiers.isEmpty {
            print("⚠️ EntitlementManager: purchased product(s) \(info.allPurchasedProductIdentifiers) found, but entitlement '\(proEntitlementID)' is not active. In RevenueCat → Entitlements, confirm '\(proEntitlementID)' is attached to that product.")
        }
        #endif
    }
}
#else
/// Android build: RevenueCat's SDK isn't linked here (it's an
/// iOS-only import above), so Pro purchases aren't wired up on this
/// platform yet. This keeps the same public API (`isPro`, `refresh()`,
/// `resetTestAccount()`) every view already depends on, so nothing else
/// has to know the difference — it just reports "not Pro" instead of
/// crashing or silently pretending to be entitled.
///
/// To make Pro real on Android, add RevenueCat's Skip-compatible
/// package (see github.com/skiptools/skip-revenue) and swap the calls
/// above back in for the Android branch.
@MainActor
final class EntitlementManager: NSObject, ObservableObject {
    @Published var isPro: Bool = false

    override init() {
        super.init()
        Task { await refresh() }
    }

    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["POCKET_VAULT_FORCE_PRO"] == "1" {
            isPro = true
        }
        #endif
    }

    func resetTestAccount() async {
        await refresh()
    }
}
#endif
