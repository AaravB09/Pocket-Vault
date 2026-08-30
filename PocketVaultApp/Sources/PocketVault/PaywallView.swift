import SwiftUI

// MARK: - Feature Row Component (shared by both platforms)

private struct FeatureRow: View {
    @EnvironmentObject var theme: ThemeManager
    let icon: String
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

            VaultButton(
                variant: VaultButtonVariant.tertiary,
                isLoading: isRestoring,
                fontSize: 12.0,
                fontWeight: Font.Weight.medium,
                action: { Task { await restore() } },
                label: AnyView(
                    Text("Restore purchases")
                        .font(theme.font(12, weight: .medium))
                )
            )

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

    private var purchaseButton: some View {
        VaultButton(
            variant: VaultButtonVariant.primary,
            isLoading: isPurchasing,
            action: { Task { await purchase() } },
            label: AnyView(Text("Continue"))
        )
        .disabled(currentPackage == nil)
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
            VaultButton("Close", variant: VaultButtonVariant.secondary, height: 36.0, fontSize: 12.0, fontWeight: Font.Weight.bold, action: { dismiss() })
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
        VaultButton(
            variant: VaultButtonVariant.ghost,
            height: 130.0,
            fontSize: 13.0,
            fontWeight: Font.Weight.semibold,
            horizontalPadding: 0.0,
            fullWidth: false,
            action: onSelect,
            label: AnyView(
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
            )
        )
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

import SkipRevenue

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
        .foregroundStyle(theme.textPrimary)
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
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(.top, 28)

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
                    .foregroundStyle(.secondary)
            }

            VaultButton(
                variant: VaultButtonVariant.tertiary,
                isLoading: isRestoring,
                fontSize: 12.0,
                fontWeight: Font.Weight.medium,
                horizontalPadding: 0.0,
                height: 36.0,
                fullWidth: false,
                action: { Task { await restore() } },
                label: AnyView(
                    Text("Restore purchases")
                        .font(theme.font(12, weight: .medium))
                        .foregroundStyle(.secondary)
                )
            )

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
        VaultButton(
            variant: VaultButtonVariant.primary,
            isLoading: isPurchasing,
            action: { Task { await purchase() } },
            label: AnyView(Text("Continue"))
        )
        .disabled(currentPackage == nil)
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
                .foregroundStyle(theme.textPrimary)
            Text("This screen renders live from your RevenueCat Offering. Add an Offering with Packages in the RevenueCat dashboard (and matching products in the Google Play Console), then this screen will populate automatically.")
                .font(theme.font(13))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Layout.pageMargin)
            VaultButton("Close", variant: VaultButtonVariant.secondary, height: 36.0, fontSize: 12.0, fontWeight: Font.Weight.bold, action: { dismiss() })
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
        VaultButton(
            variant: VaultButtonVariant.ghost,
            height: 130.0,
            fontSize: 13.0,
            fontWeight: Font.Weight.semibold,
            horizontalPadding: 0.0,
            fullWidth: false,
            action: onSelect,
            label: AnyView(
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
                                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .padding(.horizontal, 14)
                .background(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(isSelected ? theme.accent : theme.cardStroke, lineWidth: isSelected ? 2.5 : 1.0)
                )
                .shadow(color: .black.opacity(isSelected ? 0.14 : 0.0), radius: 12, y: 5)
            )
        )
        .onAppear {
            guard anchorPrice != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                revealReal = true
            }
        }
    }
}
#endif
