import CheckStitchCore
import SwiftUI

// MARK: - PurchaseSettingsView

/// Settings subscreen for the one-time unlock: loads the store offer, shows a
/// localized price with a Buy button, offers Restore Purchases, and reflects
/// the purchased state. Mirrors `PaywallView` (the refusal-path sheet) but is
/// navigable from Settings, so a user can buy or restore before ever hitting
/// the free limit.
struct PurchaseSettingsView: View {
    // MARK: Internal

    let purchases: PurchaseService

    var body: some View {
        Form {
            Section {
                if purchases.isUnlocked {
                    Label("You're all set! 🎉", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    purchaseContent
                }
            } header: {
                Text("Unlock CheckStitch")
            } footer: {
                if purchases.isUnlocked {
                    Text("Thank you for your support! You can run as many checklists as you like.")
                } else if let failure = loadFailure {
                    Text(failure.advice)
                        .foregroundStyle(.red)
                } else {
                    Text("A one-time purchase unlocks unlimited checklist runs forever.")
                }
            }

            if !purchases.isUnlocked {
                Section {
                    Button {
                        Task { await purchases.restore() }
                    } label: {
                        HStack {
                            Text("Restore Purchases")
                            Spacer()
                        }
                    }
                    .disabled(purchases.isPurchasing)
                    .accessibilityIdentifier("purchaseRestoreButton")
                } footer: {
                    Text("If you've already purchased CheckStitch on another device, restore it here.")
                }
            }
        }
        .navigationTitle("Unlock CheckStitch")
        .settingsSubscreenLayout()
        .task {
            await purchases.start()
            await purchases.loadOffer()
            hasAttemptedLoad = true
        }
    }

    // MARK: Private

    /// Distinguishes "not loaded yet" from "load failed": the offer is `nil` in
    /// both, but only the latter should show the error footer and retry.
    @State private var hasAttemptedLoad = false

    private var loadFailure: PurchaseService.OfferFailure? {
        guard hasAttemptedLoad, !purchases.isLoadingOffer else { return nil }
        return purchases.offerFailure
    }

    @ViewBuilder private var purchaseContent: some View {
        if let product = purchases.offer {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.displayName)
                            .font(.headline)
                        Text(product.displayPrice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await purchases.purchase() }
                    } label: {
                        if purchases.isPurchasing {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text(product.displayPrice)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(purchases.isPurchasing)
                    .accessibilityLabel("Buy")
                    .accessibilityIdentifier("purchaseBuyButton")
                }
                if let error = purchases.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(minHeight: 66)
        } else if purchases.isLoadingOffer || !hasAttemptedLoad {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 66)
            .frame(maxWidth: .infinity)
        } else {
            Button("Try Again") {
                Task {
                    await purchases.loadOffer()
                    hasAttemptedLoad = true
                }
            }
            .accessibilityIdentifier("purchaseRetryButton")
            .frame(minHeight: 66)
        }
    }
}

// MARK: - Previews

#Preview("Locked") {
    NavigationStack {
        PurchaseSettingsView(purchases: PurchaseEnvironment.service)
    }
}