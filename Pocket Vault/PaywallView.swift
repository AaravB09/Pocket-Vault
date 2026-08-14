import SwiftUI
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
                .padding(.horizontal, 20)
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
            featureList
                .padding(.horizontal, 28)
                .padding(.vertical, 8)

            purchaseButton

            if authManager.isGuest {
                Text("You'll create a free account on the next step")
                    .font(theme.font(10, weight: .light))
                    .foregroundStyle(theme.textTertiary)
            }

            Button(action: { Task { await restore() } }) {
                HStack(spacing: 6) {
                    if isRestoring { ProgressView().tint(theme.textSecondary) }
                    Text(isRestoring ? "RESTORING…" : "Restore Purchases")
                }
                .font(theme.font(10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(theme.textTertiary)
            }
            .disabled(isRestoring)

            if let loadErrorMessage {
                Text(loadErrorMessage)
                    .font(theme.font(11))
                    .foregroundStyle(theme.danger.opacity(0.9))
                    .padding(.horizontal, 30)
            }

            Spacer()
        }
    }

    // MARK: - Feature List View

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 16) {
            FeatureRow(
                icon: "sparkles",
                title: "Personalized AI Savings Coach",
                description: "Get custom daily insights tailored to your target dates"
            )
            
            FeatureRow(
                icon: "target",
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
                title: "Shared Budgeting & Streaks",
                description: "Sync goals with friends and keep each other accountable"
            )
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(theme.cardStroke, lineWidth: 1)
        )
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
        case .monthly: return "PER MONTH"
        case .annual: return "PER YEAR"
        case .weekly: return "PER WEEK"
        case .lifetime: return "ONE-TIME"
        default: return ""
        }
    }

    private var purchaseButton: some View {
        Button(action: { Task { await purchase() } }) {
            HStack {
                if isPurchasing { ProgressView().tint(theme.onAccent) }
                Text(isPurchasing ? "PROCESSING…" : "CONTINUE")
                    .font(theme.font(13, weight: .bold))
                    .tracking(3.2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(theme.accent)
            .foregroundColor(theme.onAccent)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(theme.onAccent.opacity(0.16), lineWidth: 1))
            .shadow(color: theme.accent.opacity(0.55), radius: 20, y: 9)
        }
        .disabled(isPurchasing || currentPackage == nil)
        .padding(.horizontal, 30)
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
            Text("This screen renders live from your RevenueCat Offering. Add an Offering with Packages in the RevenueCat dashboard (and matching products in App Store Connect), then this screen will populate automatically.")
                .font(theme.font(13))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
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

// MARK: - Feature Row Component

private struct FeatureRow: View {
    @EnvironmentObject var theme: ThemeManager
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(theme.font(14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 20, height: 20)
                .padding(4)
                .background(theme.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.font(12, weight: .bold))
                    .foregroundStyle(theme.textPrimary)

                Text(description)
                    .font(theme.font(10, weight: .regular))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }
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
    private var formatter: NumberFormatter? { package.storeProduct.priceFormatter }

    private func fmt(_ value: Double) -> String {
        formatter?.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Text(package.storeProduct.localizedTitle.uppercased())
                    .font(theme.font(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                ZStack {
                    if let anchorPrice, !revealReal {
                        Text(fmt(anchorPrice))
                            .font(theme.font(34, weight: .black))
                            .foregroundStyle(theme.textPrimary)
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
                                    .foregroundStyle(theme.textTertiary)
                                    .strikethrough(color: theme.textTertiary)
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 56)
                .animation(.spring(response: 0.55, dampingFraction: 0.7), value: revealReal)

                Text(periodLabel)
                    .font(theme.font(9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(theme.textTertiary)
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
            .shadow(color: theme.accent.opacity(isSelected ? 0.3 : 0), radius: 14, y: 6)
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
