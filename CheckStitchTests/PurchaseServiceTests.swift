import CheckStitchCore
import Foundation
import Testing

@MainActor
struct PurchaseServiceTests {
    @Test
    func purchaseFlipsLockedToUnlocked() async {
        let provider = SpyPurchaseProvider()
        provider.entitlement = false
        let service = PurchaseService(provider: provider)

        await service.start()
        #expect(service.entitlement == .locked)

        provider.purchaseResult = true
        await service.purchase()

        #expect(service.entitlement == .unlocked)
        #expect(service.lastError == nil)
    }

    @Test
    func providerThrowLeavesLockedAndRecordsError() async {
        let provider = SpyPurchaseProvider()
        let service = PurchaseService(provider: provider)

        provider.purchaseError = TestError.boom
        await service.purchase()

        #expect(!service.isUnlocked, "a thrown purchase never unlocks")
        #expect(service.lastError != nil)
    }

    @Test
    func observerCallbackUpdatesEntitlement() async {
        let provider = SpyPurchaseProvider()
        let service = PurchaseService(provider: provider)

        await service.start()
        provider.fireChange(true)

        #expect(service.entitlement == .unlocked)
    }

    @Test
    func offerLoadsFromTheProvider() async {
        let provider = SpyPurchaseProvider()
        let service = PurchaseService(provider: provider)

        await service.loadOffer()

        #expect(service.offer?.displayPrice == "$4.99")
    }
}
