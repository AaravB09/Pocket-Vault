import Foundation
#if !SKIP
import RevenueCat
#endif
import Combine

// iOS
#if !SKIP
@MainActor
final class EntitlementManager: NSObject, ObservableObject, PurchasesDelegate {
    @Published private var rawIsPro: Bool = false

    /// iOS: always `true` because the call site is gated by `#if DEBUG`.
    @MainActor
    static var isAndroidDevBuild: Bool { true }

    // Static backing store for the dev-tools override.
    @MainActor
    private static var _forceProOverride: Bool = false

    /// Dev-only paywall bypass, toggled from `ProfileView`'s dev section.
    /// Static so `ProfileView` can bind uniformly on iOS and Android
    /// without an `@EnvironmentObject` reference. On iOS the `#if DEBUG`
    /// blocks below strip the entire read/write path at compile time.
    #if DEBUG
    @MainActor
    static var forceProOverride: Bool {
        get { _forceProOverride }
        set { _forceProOverride = newValue }
    }
    #else
    @MainActor
    static var forceProOverride: Bool {
        get { false }
        set { }
    }
    #endif

    var isPro: Bool {
        #if DEBUG
        if EntitlementManager.forceProOverride { return true }
        #endif
        return rawIsPro
    }

    private let proEntitlementID = "pro"

    override init() {
        super.init()
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
            rawIsPro = true
            return
        }
        #endif
        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
        } catch {
            // Leave `isPro` at its last known value rather than assuming false.
        }
    }

    /// Debug-only: rotates RevenueCat to a brand-new anonymous test identity.
    func resetTestAccount() async {
        _ = try? await Purchases.shared.logOut()
        await refresh()
    }

    /// Static entry point for `ProfileView`'s dev section.
    @MainActor
    private static var sharedForDevTools: EntitlementManager = EntitlementManager()

    @MainActor
    static func resetTestAccountStatic() async {
        await sharedForDevTools.resetTestAccount()
    }

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.apply(customerInfo)
        }
    }

    private func apply(_ info: CustomerInfo) {
        let active = info.entitlements[proEntitlementID]?.isActive == true
        rawIsPro = active
        #if DEBUG
        if !active && !info.allPurchasedProductIdentifiers.isEmpty {
            print("WARN: EntitlementManager: purchased product(s) found but entitlement not active.")
        }
        #endif
    }
}

// Android (Skip) — second part appended below
#else
import SkipRevenue

// PLAY STORE RELEASE CHECKLIST - MUST READ BEFORE SHIPPING
// Skip (the SkipStone transpiler) ONLY respects `#if SKIP`.
// Unlike Xcode's `#if DEBUG`, Skip strips the OUTER `#if SKIP` guard
// itself - but NOT the code inside it. Code inside `#if SKIP` is
// unconditionally compiled into the Kotlin output.
//
// This means `androidDevBuildsOnly`, `forceProOverride`, and the
// `isPro` short-circuit below are NOT removed at compile time.
// They are runtime-gated by `androidDevBuildsOnly`, which defaults
// to `true`.
//
// BEFORE uploading to Play Store:
//   1. Set `androidDevBuildsOnly = false` below
//   2. Verify: grep -n "androidDevBuildsOnly = true" Entitlementmanager.swift
//      returns nothing
//   3. Build the release APK and confirm `isPro` in DEX reduces to
//      `return rawIsPro` with no override path
//
// TODO(before-release): Set androidDevBuildsOnly = false
// CHECK:  grep -n "androidDevBuildsOnly = true" Entitlementmanager.swift

@MainActor
final class EntitlementManager: NSObject, ObservableObject {
    @Published private var rawIsPro: Bool = false

    /// Set to `false` before any Play Store release.
    /// Skip does NOT strip code inside `#if SKIP` - only the `#if SKIP`
    /// guard itself - so this constant ships in the APK unless flipped.
    private let androidDevBuildsOnly: Bool = true

    /// Static read-only accessor for the dev-builds flag. Used by
    /// `ProfileView.shouldShowDevSection` to hide the dev toggle in the UI
    /// when `androidDevBuildsOnly = false`.
    @MainActor
    static var isAndroidDevBuild: Bool { true }

    /// Static so `ProfileView`'s dev section `Toggle` can bind it directly
    /// without needing an `@EnvironmentObject` reference - that reference
    /// would be gated by `#if DEBUG` (which Skip strips on Android).
    @MainActor
    static var forceProOverride: Bool = false

    var isPro: Bool {
        if androidDevBuildsOnly && EntitlementManager.forceProOverride {
            return true
        }
        return rawIsPro
    }

    private let proEntitlementID = "pro"

    override init() {
        super.init()
        // NOTE: We deliberately do NOT use Swift `assert()` here.
        // `assert()` is a no-op under -O (Release builds), which is the
        // exact build configuration that would ship to the Play Store,
        // so any `assert` on this path would be stripped from the
        // release binary and provide zero protection. The real safeguards
        // are the manual release checklist (see file-top banner) plus
        // post-build DEX inspection.
        //
        // The `let androidDevBuildsOnly = true` itself is a constant
        // baked at compile time, so the only meaningful guard is the
        // grep at release time. Keeping this init free of dead guards.
        Task { await refresh() }
    }

    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["POCKET_VAULT_FORCE_PRO"] == "1" {
            rawIsPro = true
            return
        }
        #endif
        do {
            let info = try await RevenueCatFuse.shared.getCustomerInfo()
            rawIsPro = info.isEntitlementActive(proEntitlementID)
        } catch {
            // Leave `isPro` at its last known value rather than assuming false.
        }
    }

    func resetTestAccount() async {
        _ = try? await RevenueCatFuse.shared.logoutUser()
        await refresh()
    }

    /// Static entry point for `ProfileView`'s dev section.
    @MainActor
    private static var sharedForDevTools: EntitlementManager = EntitlementManager()

    @MainActor
    static func resetTestAccountStatic() async {
        await sharedForDevTools.resetTestAccount()
    }
}
#endif
