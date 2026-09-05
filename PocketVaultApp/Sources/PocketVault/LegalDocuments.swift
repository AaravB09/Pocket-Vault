import SwiftUI

// These are working drafts, not attorney-reviewed documents — accurate to
// what Pocket Vault actually does (Supabase for auth/data, Plaid for bank
// linking, RevenueCat for subscriptions, Apple/Google for sign-in), but
// written by an AI assistant, not a lawyer. Fine for an early launch;
// worth a paid review once there's real user volume/revenue, especially
// given the bank-linking (Plaid) surface. Replace [CONTACT EMAIL] and
// [COMPANY/DEVELOPER NAME] before shipping, and re-check this against
// whatever's actually enabled in Supabase Auth (which social providers,
// whether email confirmation is required, etc.) since that can drift
// from what's written here without this file knowing.

enum LegalDocument {
    static let lastUpdated = "August 2026"

    static let privacyPolicyMarkdown = """
    # Privacy Policy

    *Last updated: \(lastUpdated)*

    Pocket Vault ("we", "us") helps you save toward goals, track spending, \
    and optionally connect a bank account for automatic transaction \
    tracking. This policy explains what we collect, why, and what you can \
    do about it.

    ## What we collect

    **Account info.** If you sign up with email, we (via Supabase, our \
    backend provider) store your email and a securely hashed password. If \
    you continue with Apple or Google, we receive your email and a stable \
    identifier from that provider instead — we never see your Apple or \
    Google password.

    **Financial data, if you connect a bank.** Bank linking uses Plaid. We \
    never see or store your bank login credentials — Plaid handles that \
    directly. We do store the transactions Plaid syncs (merchant, amount, \
    date, category) so Budget and your goals can use them. Plaid's own \
    handling of your bank credentials is governed by Plaid's privacy \
    policy, not this one.

    **Goals, savings, and streak data.** Whatever you create in the app — \
    goal names, target amounts, progress, streaks — is stored against \
    your account so it syncs across devices.

    **Guest mode.** If you use Pocket Vault without an account, your data \
    stays on your device only. Nothing is sent to our servers. Uninstalling \
    the app or clearing app data deletes it permanently — we have no copy \
    to restore.

    **Subscription info.** Purchases are handled by RevenueCat and the \
    App Store / Google Play. We receive whether you have an active \
    subscription, not your payment card details — we never see those.

    **Diagnostic info.** Standard technical data (crash logs, rough \
    performance metrics) may be collected to keep the app working \
    reliably.

    ## What we don't do

    We don't sell your data. We don't share your financial data with \
    advertisers. We don't use your transaction data to show you ads.

    ## Your choices

    - **Privacy Mode** blurs dollar amounts on-screen until you tap to \
    reveal them — a display setting, not a server-side control.
    - **Export your data** anytime from Profile → Privacy & data, as CSV \
    or JSON.
    - **Delete your account** by contacting [CONTACT EMAIL] — we'll \
    delete your stored goals, transactions, and account record. Deleting \
    your bank connection separately through Plaid's own removal flow may \
    also be necessary to fully revoke access.
    - **Disconnect your bank** anytime from Budget → bank settings, which \
    revokes Pocket Vault's access via Plaid.

    ## Third parties we use

    - **Supabase** — authentication and database hosting.
    - **Plaid** — bank account linking and transaction data.
    - **RevenueCat** — subscription management.
    - **Apple / Google** — optional sign-in, and app store payment \
    processing.

    Each of these has its own privacy policy governing how they handle \
    data on their end.

    ## Children

    Pocket Vault is not directed at children under 13, and we don't \
    knowingly collect data from them.

    ## Changes

    If this policy changes materially, we'll update the "Last updated" \
    date above and, for significant changes, notify you in-app.

    ## Contact

    Questions about this policy or your data: aarav09bansal@gmail.com
    """

    static let termsOfServiceMarkdown = """
    # Terms of Service

    *Last updated: \(lastUpdated)*

    By using Pocket Vault, you agree to these terms.

    ## The service

    Pocket Vault is a personal savings and budgeting tool. It is not a \
    bank, is not FDIC-insured, and does not hold or move your money. \
    Bank-linking (via Plaid) is read-only transaction visibility — Pocket \
    Vault cannot initiate transfers, payments, or withdrawals from any \
    account you connect.

    ## Your account

    You're responsible for keeping your login credentials secure and for \
    all activity under your account. You must be at least 13 years old to \
    use Pocket Vault (or the minimum age required in your country for a \
    social media/financial app of this kind, if higher).

    ## Subscriptions

    Some features require a paid subscription ("Pro"), billed through the \
    App Store or Google Play. Subscriptions auto-renew unless cancelled \
    at least 24 hours before the current period ends. Manage or cancel \
    your subscription through your Apple ID or Google Play account \
    settings — we cannot cancel it for you directly, and don't process \
    refunds ourselves (that goes through Apple/Google's own refund \
    process).

    ## Bank connections

    You're responsible for the accuracy of any bank account you connect. \
    We rely on Plaid to retrieve transaction data and aren't responsible \
    for delays, inaccuracies, or interruptions caused by Plaid or your \
    bank.

    ## Acceptable use

    Don't use Pocket Vault to violate any law, attempt to access other \
    users' data, or interfere with the service's normal operation.

    ## No financial advice

    Nothing in Pocket Vault (including the AI savings coach, if you use \
    it) is financial, investment, tax, or legal advice. It's a budgeting \
    tool, not a substitute for professional advice about your specific \
    situation.

    ## Disclaimer of warranties

    Pocket Vault is provided "as is." We don't guarantee it will be \
    error-free, uninterrupted, or perfectly accurate, particularly for \
    data synced from third parties (Plaid, RevenueCat, Apple, Google).

    ## Limitation of liability

    To the maximum extent permitted by law, [COMPANY/DEVELOPER NAME] \
    isn't liable for indirect, incidental, or consequential damages \
    arising from your use of Pocket Vault.

    ## Termination

    You can stop using Pocket Vault and delete your account anytime. We \
    may suspend or terminate accounts that violate these terms.

    ## Changes to these terms

    We may update these terms as the app evolves; continued use after an \
    update means you accept the revised terms.

    ## Contact

    Questions about these terms: [CONTACT EMAIL]
    """
}

public struct LegalDocumentView: View {
    enum Kind {
        case privacy, terms
        var title: String { self == .privacy ? "Privacy Policy" : "Terms of Service" }
        var markdown: String { self == .privacy ? LegalDocument.privacyPolicyMarkdown : LegalDocument.termsOfServiceMarkdown }
    }

    let kind: Kind
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) var dismiss: DismissAction

    public var body: some View {
        // `NavigationView` isn't implemented by Skip's SwiftUI shim (it's
        // also deprecated in real SwiftUI since iOS 16) — `NavigationStack`
        // is the direct replacement and needs no other changes here since
        // this view doesn't use any NavigationView-only modifiers like
        // `.navigationViewStyle`.
        NavigationStack {
            ScrollView {
                // NOTE(skip): Text(markdown:) with full block-level Markdown
                // (headers, lists) isn't guaranteed to render identically
                // under Skip's SwiftUI shim — worth a quick visual check on
                // Android specifically for this view once built.
                Text(kind.markdown)
                    .font(theme.font(14, weight: Font.Weight.light))
                    .foregroundStyle(theme.textPrimary)
                    .padding(20)
            }
            .navigationTitle(kind.title)
            .themedSurface(ignoresSafeArea: true)
            .toolbar {
                ToolbarItem(placement: ToolbarItemPlacement.confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Tappable "Terms of Service" / "Privacy Policy" fine print — drop this
/// anywhere consent needs to be visible (LoginView, ProfileView).
public struct LegalFinePrint: View {
    @EnvironmentObject var theme: ThemeManager
    @State private var presented: LegalDocumentView.Kind?

    public var body: some View {
        HStack(spacing: 4) {
            Text("By continuing, you agree to our")
            Button("Terms") { presented = .terms }
            Text("and")
            Button("Privacy Policy") { presented = .privacy }
        }
        .font(theme.font(10, weight: Font.Weight.light))
        .foregroundStyle(theme.textTertiary)
        .buttonStyle(ButtonStyle.plain)
        .tint(theme.accent)
        .multilineTextAlignment(TextAlignment.center)
        .sheet(item: Binding(
            get: { presented.map { IdentifiableKind(kind: $0) } },
            set: { presented = $0?.kind }
        )) { wrapped in
            LegalDocumentView(kind: wrapped.kind)
        }
    }
}

private struct IdentifiableKind: Identifiable {
    let kind: LegalDocumentView.Kind
    var id: String { kind == .privacy ? "privacy" : "terms" }
}
