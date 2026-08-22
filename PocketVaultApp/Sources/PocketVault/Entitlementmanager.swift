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
        // Purchases.configure() now runs in AppDelegate.didFinishLaunching
        // (see Pocket_VaultApp.swift) specifically so this is always safe
        // by the time EntitlementManager exists. This guard is just a
        // safety net against a future call-site ordering regression —
        // it fails soft (isPro stays false) instead of crashing.
        guard Purchases.isConfigured else {
            assertionFailure("EntitlementManager created before Purchases.configure() ran")
            return
        }
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
import SkipRevenue

/// Android build: RevenueCat's native SDK isn't linked here (it's an
/// iOS-only import above), but SkipRevenue is — see Package.swift — so
/// Pro is real here too now, via `RevenueCatFuse` instead of `Purchases`.
/// Same public API (`isPro`, `refresh()`, `resetTestAccount()`) every
/// view already depends on, so nothing else needed to change.
@MainActor
final class EntitlementManager: NSObject, ObservableObject {
    @Published var isPro: Bool = false

    private let proEntitlementID = "pro"

    override init() {
        super.init()
        // RevenueCatFuse.shared.configure(apiKey:) runs once at app
        // startup — see PocketVaultAppDelegate.onInit() in
        // PocketVaultApp.swift — same "configure before anything touches
        // .shared" ordering requirement as iOS's Purchases.configure(),
        // just on Android's own startup hook instead of
        // applicationDidFinishLaunching.
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
            let info = try await RevenueCatFuse.shared.getCustomerInfo()
            isPro = info.isEntitlementActive(proEntitlementID)
        } catch {
            // Leave isPro at its last known value rather than assuming false.
        }
    }

    func resetTestAccount() async {
        _ = try? await RevenueCatFuse.shared.logoutUser()
        await refresh()
    }
}
#endif
