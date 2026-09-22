@testable import CheckStitch
import CheckStitchCore
import SwiftUI
import Testing

/// Render/state coverage for the Settings purchase subscreen. `PurchaseService`
/// state is driven through `SpyPurchaseProvider` before the view is built,
/// since `ImageRenderer` does not run `.task`.
@MainActor
struct PurchaseSettingsViewTests {
    @Test
    func rendersLockedOffer() async {
        let service = await purchaseService()
        await service.loadOffer()

        #expect(renders(NavigationStack { PurchaseSettingsView(purchases: service) }))
    }

    @Test
    func rendersUnlockedState() async {
        let service = await purchaseService(entitlement: true)
        #expect(service.isUnlocked)

        #expect(renders(NavigationStack { PurchaseSettingsView(purchases: service) }))
    }

    @Test
    func rendersLoadingBeforeTheOfferArrives() async {
        let service = await purchaseService()

        #expect(renders(NavigationStack { PurchaseSettingsView(purchases: service) }))
    }

    @Test
    func lockedViewOffersBuyAndRestore() async {
        let service = await purchaseService()
        await service.loadOffer()
        let body = String(describing: PurchaseSettingsView(purchases: service).body)

        #expect(body.contains("Restore Purchases"))
        #expect(body.contains("$4.99"), "the offer price drives the buy button")
    }

    @Test
    func unlockedViewHidesTheUnlockControls() async {
        let service = await purchaseService(entitlement: true)
        let body = String(describing: PurchaseSettingsView(purchases: service).body)

        #expect(body.contains("You're all set! 🎉"))
        #expect(!body.contains("Restore Purchases"))
    }

    /// Builds a service whose entitlement is settled, so the view never depends
    /// on a live StoreKit response.
    private func purchaseService(entitlement: Bool = false) async -> PurchaseService {
        let provider = SpyPurchaseProvider()
        provider.entitlement = entitlement
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))
        await service.start()
        return service
    }

    private func renders(_ view: some View) -> Bool {
        #if os(macOS)
            return ImageRenderer(content: view).nsImage != nil
        #else
            return ImageRenderer(content: view).uiImage != nil
        #endif
    }
}