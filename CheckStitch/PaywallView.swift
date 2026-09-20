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
            Button("Buy") {}          // Phase 2 wires the purchase
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("paywallBuyButton")
            Button("Not now") { dismiss() }
                .accessibilityIdentifier("paywallDismissButton")
        }
        .padding()
        .accessibilityIdentifier("paywallView")
    }
}