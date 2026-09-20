import CheckStitchCore
import SwiftUI

/// Blocking unlock surface, presented when a run is refused at the free limit.
/// iOS and macOS share it; watchOS has no purchase surface.
struct PaywallView: View {
    @Environment(PurchaseService.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Unlock CheckStitch")
                .font(.title2.bold())
            Text("You've run \(RunGate.freeRunLimit) checklists. Buy once to keep creating reminders.")
                .multilineTextAlignment(.center)
            Button {
                Task { await purchases.purchase() }
            } label: {
                Text(purchases.isPurchasing ? "Purchasing…" : "Buy")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(purchases.isPurchasing)
            .accessibilityIdentifier("paywallBuyButton")
            if let offer = purchases.offer {
                Text(offer.displayName).font(.headline)
                Text(offer.displayPrice).font(.subheadline)
            }
            Button("Not now") { dismiss() }
                .accessibilityIdentifier("paywallDismissButton")
            if let error = purchases.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding()
        .accessibilityIdentifier("paywallView")
        .task { await purchases.loadOffer() }
        .onChange(of: purchases.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }
}