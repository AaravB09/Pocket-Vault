import SwiftUI

// MARK: - Feature Row Component (shared by both platforms)

private struct FeatureRow: View {
    @EnvironmentObject var theme: ThemeManager
    let icon: String
    // FIX: `icon` used to be handed straight to `Image(systemName:)`
    // below, unwrapped. "sparkles", "target", and "person.2.fill" (3 of
    // the 4 paywall feature icons) are outside Skip's Android fallback
    // table — see the matching note on GoalKind.androidDisplayIcon in
    // Goalbuildmodels.swift — so most of the feature list on this
    // upgrade screen was showing "symbol not found" warning triangles
    // instead of its icons on Android. Defaults to `icon` so existing
    // call sites (none currently) wouldn't be forced to change, but
    // every call site below now passes an explicit Android-safe name.
    var androidIcon: String? = nil
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image.platformSymbol(icon, android: androidIcon ?? icon)
                .font(theme.font(14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 20, height: 20)
                .padding(4)
                .background(theme.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.font(12, weight: .bold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(theme.font(10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private var pocketVaultFeatureList: some View {
    VStack(alignment: .leading, spacing: 16) {
        FeatureRow(
            icon: "sparkles",
            androidIcon: "star.fill",
            title: "Personalized AI Savings Coach",
            description: "Get custom daily insights tailored to your target dates"
        )

        FeatureRow(
            icon: "target",
            androidIcon: "mappin.circle.fill",
            title: "Unlimited Goal Vaults",
            description: "Track flights, big purchases, and emergency funds all in one place"
        )

        FeatureRow(
            icon: "bolt.fill",
            title: "Instant AI Recommendations",
            description: "Chat anytime with your coach to optimize your spending"
        )

        FeatureRow(
            icon: "person.2.fill",
            androidIcon: "person.fill",
            title: "Shared Budgeting & Streaks",
            description: "Sync goals with friends and keep each other accountable"
        )
    }
}

// MARK: - Shared price formatting helper

private func formattedPrice(_ value: Double, currencyCode: String?) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    if let currencyCode {
        formatter.currencyCode = currencyCode
    }
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
}

#if !SKIP
import RevenueCat

/// A fully custom paywall showing both plans side by side, each with a
/// dramatic "was $X, now $Y" price-drop reveal animation on appear.
/// On successful purchase, hands off to SavingsCoachView so the user
/// immediately gets a tailored plan for their current goal.
struct CustomPaywallView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var entitlementManager: EntitlementManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var theme: ThemeManager

    let goalTitle: String
    let targetGoal: Double
    let currentSavings: Double
    @Binding var chatMessages: [ChatMessage]
    @Binding var selectedTab: Int

    @State private var packages: [Package] = []
    @State private var selectedIndex: Int = 0
    @State private var isLoading: Bool = true
    @State private var loadErrorMessage: String?
    @State private var isPurchasing: Bool = false
    @State private var isRestoring: Bool = false
    @State private var showCoach: Bool = false
    // Guests must create a real account before subscribing — a purchase
    // tied only to a local, deletable guest identity has nowhere
    // reliable to attach an entitlement to on a new device.
    @State private var showAccountRequired: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.background, theme.background.opacity(0.92)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if isLoading {
                ProgressView().tint(theme.accent)
            } else if packages.isEmpty {
                notConfiguredState
            } else {
                paywallContent
            }
        }
        // Background here is a custom gradient (not the flat theme.background
        // surface), so we apply just the foregroundStyle cascade rather than
        // the full .themedSurface(theme) — that would also inject a redundant
        // flat background layer underneath the gradient.
        .foregroundStyle(theme.textPrimary, theme.textSecondary, theme.textTertiary)
        .task { await loadOfferings() }
        .fullScreenCover(isPresented: $showCoach) {
            SavingsCoachView(
                goalTitle: goalTitle,
                targetAmount: targetGoal,
                currentSavings: currentSavings,
                goalTargetDate: Date(),
                chatMessages: $chatMessages,
                selectedTab: $selectedTab
            )
            .onDisappear { dismiss() }
        }
        .sheet(isPresented: $showAccountRequired) {
            LoginView(hideGuestOption: true)
        }
    }

    // MARK: - Loaded state

    private var paywallContent: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("POCKET VAULT")
                    .font(theme.font(10, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(theme.accent)
                Text("Unlock Pro")
                    .font(theme.font(26, weight: .light))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 28)

            // MARK: Plan cards — side-by-side with price-drop reveal
            if packages.count >= 2 {
                HStack(spacing: 12) {
                    ForEach(Array(packages.enumerated()), id: \.offset) { index, package in
                        PlanCard(
                            package: package,
                            isSelected: index == selectedIndex,
                            anchorPrice: anchorPrice(for: package),
                            periodLabel: periodLabel(for: package),
                            onSelect: {
                                UISelectionFeedbackGenerator().selectionChanged()
                                selectedIndex = index
                            }
                        )
                    }
                }
                .padding(.horizontal, Layout.pageMargin)
            } else if let only = packages.first {
                PlanCard(
                    package: only,
                    isSelected: true,
                    anchorPrice: anchorPrice(for: only),
                    periodLabel: periodLabel(for: only),
                    onSelect: {}
                )
                .padding(.horizontal, 40)
            }

            // MARK: - Pro Features List
            pocketVaultFeatureList
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
                .padding(.horizontal, 28)
                .padding(.vertical, 8)

            purchaseButton

            if authManager.isGuest {
                Text("You'll create a free account on the next step")
                    .font(theme.font(10, weight: .light))
                    .foregroundStyle(.tertiary)
            }

            Button(action: { Task { await restore() } }) {
                HStack(spacing: 6) {
                    if isRestoring { ProgressView().tint(theme.textSecondary) }
                    Text(isRestoring ? "Restoring…" : "Restore purchases")
                }
                .font(theme.font(12, weight: .medium))
                .foregroundStyle(.tertiary)
            }
            .disabled(isRestoring)

            if let loadErrorMessage {
                Text(loadErrorMessage)
                    .font(theme.font(11))
                    .foregroundStyle(theme.danger.opacity(0.9))
                    .padding(.horizontal, Layout.pageMargin)
            }

            Spacer()
        }
    }

    // MARK: - Price anchoring per plan

    private let monthlyMarketingDiscount = 0.25

    private func isYearly(_ package: Package) -> Bool {
        package.storeProduct.productIdentifier.localizedCaseInsensitiveContains("year")
    }

    private func anchorPrice(for package: Package) -> Double? {
        let realPrice = (package.storeProduct.price as NSDecimalNumber).doubleValue
        if isYearly(package), let monthly = packages.first(where: { !isYearly($0) }) {
            return (monthly.storeProduct.price as NSDecimalNumber).doubleValue * 12
        }
        if !isYearly(package) {
            return realPrice / (1 - monthlyMarketingDiscount)
        }
        return nil
    }

    private func periodLabel(for package: Package) -> String {
        switch package.packageType {
        case .monthly: return "Per month"
        case .annual: return "Per year"
        case .weekly: return "Per week"
        case .lifetime: return "One-time"
        default: return ""
        }
    }

    // FIX: `.buttonStyle(.primaryCTA(theme))` referenced a custom
    // ButtonStyle static member that no longer exists — same leftover
    // migration gap as BuildStudioView/AccountRequiredGateView/
    // SetupGoalView: custom ButtonStyle conformance isn't supported by
    // Skip, so those styles were all replaced app-wide with plain
    // wrapper views (see PrimaryCTAButton in ThemeManager.swift). Use
    // the wrapper directly instead of a Button + buttonStyle pair.
    private var purchaseButton: some View {
        PrimaryCTAButton(accent: theme.accent, onAccent: theme.onAccent, action: { Task { await purchase() } }) {
            HStack {
                if isPurchasing { ProgressView().tint(theme.onAccent) }
                Text(isPurchasing ? "Processing…" : "Continue")
            }
        }
        .disabled(isPurchasing || currentPackage == nil)
        .padding(.horizontal, Layout.pageMargin)
    }

    // MARK: - Fallback (offerings not configured)

    private var notConfiguredState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(theme.font(34, weight: .bold))
                .foregroundStyle(theme.accent)
            Text("Pro plans aren't set up yet")
                .font(theme.font(16, weight: .semibold))
                .foregroundStyle(.primary)
            Text("This screen renders live from your RevenueCat Offering. Add an Offering with Packages in the RevenueCat dashboard (and matching products in App Store Connect), then this screen will populate automatically.")
                .font(theme.font(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Layout.pageMargin)
            Button("Close") { dismiss() }
                .font(theme.font(12, weight: .bold))
                .foregroundStyle(theme.accent)
                .padding(.top, 8)
        }
        .padding()
    }

    // MARK: - Data + purchase logic

    private var currentPackage: Package? {
        guard packages.indices.contains(selectedIndex) else { return nil }
        return packages[selectedIndex]
    }

    private func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            if let current = offerings.current, !current.availablePackages.isEmpty {
                packages = current.availablePackages
            } else {
                packages = []
            }
        } catch {
            loadErrorMessage = "Couldn't load offerings: \(error.localizedDescription)"
            packages = []
        }
        isLoading = false
    }

    private func purchase() async {
        guard let package = currentPackage else { return }
        guard !authManager.isGuest else {
            showAccountRequired = true
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled {
                await entitlementManager.refresh()
                showCoach = true
            }
        } catch {
            loadErrorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    private func restore() async {
        isRestoring = true
        loadErrorMessage = nil
        defer { isRestoring = false }
        do {
            _ = try await Purchases.shared.restorePurchases()
            await entitlementManager.refresh()
            if entitlementManager.isPro {
                dismiss()
            } else {
                // Previously this dismissed unconditionally even when
                // nothing was found, which is exactly why it looked like
                // "restore doesn't work" — it silently closed the paywall
                // either way with no indication of what happened.
                loadErrorMessage = "No previous purchases were found for this account."
            }
        } catch {
            loadErrorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Plan Card with price-drop reveal animation

private struct PlanCard: View {
    @EnvironmentObject var theme: ThemeManager
    let package: Package
    let isSelected: Bool
    let anchorPrice: Double?
    let periodLabel: String
    let onSelect: () -> Void

    @State private var revealReal = false

    private var realPrice: Double { (package.storeProduct.price as NSDecimalNumber).doubleValue }

    private func fmt(_ value: Double) -> String {
        package.storeProduct.priceFormatter?.string(from: NSNumber(value: value))
            ?? formattedPrice(value, currencyCode: package.storeProduct.currencyCode)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Text(package.storeProduct.localizedTitle)
                    .font(theme.font(13, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                ZStack {
                    if let anchorPrice, !revealReal {
                        Text(fmt(anchorPrice))
                            .font(theme.font(34, weight: .black))
                            .foregroundStyle(.primary)
                            .transition(.scale.combined(with: .opacity))
                    }

                    if revealReal {
                        VStack(spacing: 2) {
                            Text(fmt(realPrice))
                                .font(theme.font(30, weight: .light))
                                .foregroundStyle(theme.accent)
                            if let anchorPrice {
                                Text(fmt(anchorPrice))
                                    .font(theme.font(12, weight: .light))
                                    .foregroundStyle(.tertiary)
                                    .strikethrough(color: theme.textTertiary)
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 56)
                .animation(.spring(response: 0.55, dampingFraction: 0.7), value: revealReal)

                Text(periodLabel)
                    .font(theme.font(11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, 14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? theme.accent : theme.cardStroke, lineWidth: isSelected ? 2.5 : 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.14 : 0), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .onAppear {
            guard anchorPrice != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                revealReal = true
            }
        }
    }
}

#else
// MARK: - Android paywall (SkipRevenue's RevenueCat integration)
//
// Rebuilt to match the iOS card-based design exactly, rather than the
// dashboard-configured RCFusePaywallView template. That template was
// showing a blank white screen because it renders whatever Paywall is
// published in the RevenueCat dashboard for the offering — if none is
// configured there, it has nothing to draw. Building against
// skip-revenue's own RCFuseOffering/RCFusePackage/RCFuseStoreProduct
// types (via RevenueCatFuse) instead means this screen — like the iOS
// one — always renders from the Offering's Packages directly, with no
// dashboard paywall template required.
import SkipRevenue

/// Mirrors the iOS CustomPaywallView above: same header, same
/// side-by-side price-drop-reveal PlanCards, same feature list and
/// purchase/restore flow — built against SkipRevenue's RCFuse* types
/// instead of RevenueCat's native iOS types.
struct CustomPaywallView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var entitlementManager: EntitlementManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var theme: ThemeManager

    let goalTitle: String
    let targetGoal: Double
    let currentSavings: Double
    @Binding var chatMessages: [ChatMessage]
    @Binding var selectedTab: Int

    @State private var packages: [RCFusePackage] = []
    @State private var selectedIndex: Int = 0
    @State private var isLoading: Bool = true
    @State private var loadErrorMessage: String?
    @State private var isPurchasing: Bool = false
    @State private var isRestoring: Bool = false
    @State private var showCoach: Bool = false
    // Guests must create a real account before subscribing — a purchase
    // tied only to a local, deletable guest identity has nowhere
    // reliable to attach an entitlement to on a new device.
    @State private var showAccountRequired: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.background, theme.background.opacity(0.92)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if isLoading {
                ProgressView().tint(theme.accent)
            } else if packages.isEmpty {
                notConfiguredState
            } else {
                paywallContent
            }
        }
        .task { await loadOfferings() }
        .fullScreenCover(isPresented: $showCoach) {
            SavingsCoachView(
                goalTitle: goalTitle,
                targetAmount: targetGoal,
                currentSavings: currentSavings,
                goalTargetDate: Date(),
                chatMessages: $chatMessages,
                selectedTab: $selectedTab
            )
            .onDisappear { dismiss() }
        }
        .sheet(isPresented: $showAccountRequired) {
            LoginView(hideGuestOption: true)
        }
    }

    // MARK: - Loaded state

    private var paywallContent: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("POCKET VAULT")
                    .font(theme.font(10, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(theme.accent)
                Text("Unlock Pro")
                    .font(theme.font(26, weight: .light))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 28)

            // MARK: Plan cards — side-by-side with price-drop reveal
            if packages.count >= 2 {
                HStack(spacing: 12) {
                    ForEach(Array(packages.enumerated()), id: \.offset) { index, pkg in
                        PlanCard(
                            pkg: pkg,
                            isSelected: index == selectedIndex,
                            anchorPrice: anchorPrice(for: pkg),
                            periodLabel: periodLabel(for: pkg),
                            onSelect: {
                                selectedIndex = index
                            }
                        )
                    }
                }
                .padding(.horizontal, Layout.pageMargin)
            } else if let only = packages.first {
                PlanCard(
                    pkg: only,
                    isSelected: true,
                    anchorPrice: anchorPrice(for: only),
                    periodLabel: periodLabel(for: only),
                    onSelect: {}
                )
                .padding(.horizontal, 40)
            }

            // MARK: - Pro Features List
            // NOTE(skip): only `.ultraThinMaterial` is unresolved by
            // Skip's SwiftUI shim — `.clipShape` resolves fine once it
            // isn't cascading from that broken symbol right above it
            // (see Networkmonitor.swift for the same pattern).
            pocketVaultFeatureList
                .padding(20)
                .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
                .padding(.horizontal, 28)
                .padding(.vertical, 8)

            purchaseButton

            if authManager.isGuest {
                Text("You'll create a free account on the next step")
                    .font(theme.font(10, weight: .light))
                    .foregroundStyle(.secondary) // was .tertiary — unsupported by Skip
            }

            Button(action: { Task { await restore() } }) {
                HStack(spacing: 6) {
                    if isRestoring { ProgressView().tint(theme.textSecondary) }
                    Text(isRestoring ? "Restoring…" : "Restore purchases")
                }
                .font(theme.font(12, weight: .medium))
                .foregroundStyle(.secondary) // was .tertiary — unsupported by Skip
            }
            .disabled(isRestoring)

            if let loadErrorMessage {
                Text(loadErrorMessage)
                    .font(theme.font(11))
                    .foregroundStyle(theme.danger.opacity(0.9))
                    .padding(.horizontal, Layout.pageMargin)
            }

            Spacer()
        }
    }

    // MARK: - Price anchoring per plan

    private let monthlyMarketingDiscount = 0.25

    private func isYearly(_ pkg: RCFusePackage) -> Bool {
        pkg.storeProduct.productIdentifier.lowercased().contains("year")
    }

    private func anchorPrice(for pkg: RCFusePackage) -> Double? {
        let realPrice = pkg.storeProduct.price
        if isYearly(pkg), let monthly = packages.first(where: { !isYearly($0) }) {
            return monthly.storeProduct.price * 12
        }
        if !isYearly(pkg) {
            return realPrice / (1 - monthlyMarketingDiscount)
        }
        return nil
    }

    private func periodLabel(for pkg: RCFusePackage) -> String {
        switch pkg.packageType {
        case .monthly: return "Per month"
        case .annual: return "Per year"
        case .weekly: return "Per week"
        case .lifetime: return "One-time"
        default: return ""
        }
    }

    private var purchaseButton: some View {
        PrimaryCTAButton(accent: theme.accent, onAccent: theme.onAccent, action: { Task { await purchase() } }) {
            HStack {
                if isPurchasing { ProgressView().tint(theme.onAccent) }
                Text(isPurchasing ? "Processing…" : "Continue")
            }
        }
        .disabled(isPurchasing || currentPackage == nil)
        .padding(.horizontal, Layout.pageMargin)
    }

    // MARK: - Fallback (offerings not configured)

    private var notConfiguredState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(theme.font(34, weight: .bold))
                .foregroundStyle(theme.accent)
            Text("Pro plans aren't set up yet")
                .font(theme.font(16, weight: .semibold))
                .foregroundStyle(.primary)
            Text("This screen renders live from your RevenueCat Offering. Add an Offering with Packages in the RevenueCat dashboard (and matching products in the Google Play Console), then this screen will populate automatically.")
                .font(theme.font(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Layout.pageMargin)
            Button("Close") { dismiss() }
                .font(theme.font(12, weight: .bold))
                .foregroundStyle(theme.accent)
                .padding(.top, 8)
        }
        .padding()
    }

    // MARK: - Data + purchase logic

    private var currentPackage: RCFusePackage? {
        guard packages.indices.contains(selectedIndex) else { return nil }
        return packages[selectedIndex]
    }

    private func loadOfferings() async {
        do {
            let offerings = try await RevenueCatFuse.shared.loadOfferings()
            if let current = offerings.current, !current.availablePackages.isEmpty {
                packages = current.availablePackages
            } else {
                packages = []
            }
        } catch {
            loadErrorMessage = "Couldn't load offerings: \(error.localizedDescription)"
            packages = []
        }
        isLoading = false
    }

    private func purchase() async {
        guard let pkg = currentPackage else { return }
        guard !authManager.isGuest else {
            showAccountRequired = true
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            _ = try await RevenueCatFuse.shared.purchase(
                package: pkg,
                activity: UIApplication.shared.androidActivity as! RCFuseAndroidActivity
            )
            await entitlementManager.refresh()
            showCoach = true
        } catch {
            // Kotlin doesn't support `catch ... where` clauses, so the
            // cancellation check happens inside a plain catch instead —
            // silent on cancel, same as the iOS `result.userCancelled`
            // early return.
            if let storeError = error as? StoreError, storeError == .userCancelled {
                // no-op
            } else {
                loadErrorMessage = "Purchase failed: \(error.localizedDescription)"
            }
        }
    }

    private func restore() async {
        isRestoring = true
        loadErrorMessage = nil
        defer { isRestoring = false }
        do {
            _ = try await RevenueCatFuse.shared.restorePurchases()
            await entitlementManager.refresh()
            if entitlementManager.isPro {
                dismiss()
            } else {
                loadErrorMessage = "No previous purchases were found for this account."
            }
        } catch {
            // Same Kotlin `catch ... where` limitation as purchase() above.
            if let storeError = error as? StoreError, storeError == .noPurchasesFound {
                loadErrorMessage = "No previous purchases were found for this account."
            } else {
                loadErrorMessage = "Restore failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Plan Card with price-drop reveal animation

private struct PlanCard: View {
    @EnvironmentObject var theme: ThemeManager
    let pkg: RCFusePackage
    let isSelected: Bool
    let anchorPrice: Double?
    let periodLabel: String
    let onSelect: () -> Void

    @State private var revealReal = false

    private var realPrice: Double { pkg.storeProduct.price }

    private func fmt(_ value: Double) -> String {
        formattedPrice(value, currencyCode: pkg.storeProduct.currencyCode)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Text(pkg.storeProduct.localizedTitle)
                    .font(theme.font(13, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                ZStack {
                    if let anchorPrice, !revealReal {
                        Text(fmt(anchorPrice))
                            .font(theme.font(34, weight: .black))
                            .foregroundStyle(.primary)
                            .transition(.scale.combined(with: .opacity))
                    }

                    if revealReal {
                        VStack(spacing: 2) {
                            Text(fmt(realPrice))
                                .font(theme.font(30, weight: .light))
                                .foregroundStyle(theme.accent)
                            if let anchorPrice {
                                Text(fmt(anchorPrice))
                                    .font(theme.font(12, weight: .light))
                                    .foregroundStyle(.secondary) // was .tertiary — unsupported by Skip
                                    .strikethrough(color: theme.textTertiary)
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 56)
                .animation(.spring(response: 0.55, dampingFraction: 0.7), value: revealReal)

                Text(periodLabel)
                    .font(theme.font(11, weight: .medium))
                    .foregroundStyle(.secondary) // was .tertiary — unsupported by Skip
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, 14)
            // NOTE(skip): same .ultraThinMaterial swap as paywallContent
            // above — .clipShape itself is fine, only the material isn't.
            .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? theme.accent : theme.cardStroke, lineWidth: isSelected ? 2.5 : 1.0)
            )
            .shadow(color: .black.opacity(isSelected ? 0.14 : 0.0), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .onAppear {
            guard anchorPrice != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                revealReal = true
            }
        }
    }
}
#endif
