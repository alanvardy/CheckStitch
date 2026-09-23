import CheckStitchCore
import Foundation
import Testing

@MainActor
struct PurchaseServiceTests {
    @Test
    func purchaseFlipsLockedToUnlocked() async {
        let provider = SpyPurchaseProvider()
        provider.entitlement = false
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))

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
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))

        provider.purchaseError = TestError.boom
        await service.purchase()

        #expect(!service.isUnlocked, "a thrown purchase never unlocks")
        #expect(service.lastError != nil)
    }

    @Test
    func observerCallbackUpdatesEntitlement() async {
        let provider = SpyPurchaseProvider()
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))

        await service.start()
        provider.fireChange(true)

        #expect(service.entitlement == .unlocked)
    }

    @Test
    func offerLoadsFromTheProvider() async {
        let provider = SpyPurchaseProvider()
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))

        await service.loadOffer()

        #expect(service.offer?.displayPrice == "$4.99")
    }

    @Test
    func restoreUnlocks() async {
        let provider = SpyPurchaseProvider()
        provider.entitlement = false
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))
        await service.start()
        #expect(service.entitlement == .locked)

        provider.restoreResult = true
        await service.restore()

        #expect(service.entitlement == .unlocked)
    }

    @Test
    func restoreFailureStaysLocked() async {
        let provider = SpyPurchaseProvider()
        provider.restoreError = TestError.boom
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))

        await service.restore()

        #expect(!service.isUnlocked, "a thrown restore never unlocks")
        #expect(service.lastError != nil)
        #expect(provider.restoreCount == 1)
    }

    @Test
    func cachedVerifiedEntitlementIsUnlockedBeforeResolution() async {
        let cache = PurchaseEntitlementCache(defaults: makeIsolatedDefaults())
        cache.setVerified(true)
        let provider = SpyPurchaseProvider()
        let service = PurchaseService(provider: provider, cache: cache)

        // Before start() resolves, the cache bridges the cold launch so the
        // paywall never flashes for a paid user.
        #expect(service.entitlement == .unlocked)
    }

    @Test
    func verifiedRevocationClearsTheCacheAndLocks() async {
        let cache = PurchaseEntitlementCache(defaults: makeIsolatedDefaults())
        cache.setVerified(true)
        let provider = SpyPurchaseProvider()
        provider.entitlement = false
        let service = PurchaseService(provider: provider, cache: cache)

        await service.start()

        #expect(service.entitlement == .locked, "a definitive false must not fail open")
        #expect(!cache.isVerified, "the stale verified flag is cleared")
    }

    @Test
    func unknownAtLimitReportsLocked() async {
        let provider = SpyPurchaseProvider()
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))

        // No start(): the fresh cache is unverified and entitlement is unknown,
        // so `isUnlocked` is false — the gate shows the paywall, never a silent unlock.
        #expect(service.entitlement == .unknown)
        #expect(!service.isUnlocked)
    }

    @Test
    func concurrentPurchaseIsIgnored() async {
        let provider = SpyPurchaseProvider()
        provider.suspendNextPurchase = true
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))

        let first = Task { await service.purchase() }
        await Task.yield()                       // let the first purchase reach its suspension
        await service.purchase()                 // isPurchasing is true → ignored
        provider.resumePurchase()
        await first.value

        #expect(provider.purchaseCount == 1, "a second purchase while one is in flight must not fire")
    }

    @Test
    func offerStaysNilOnFailure() async {
        let provider = SpyPurchaseProvider()
        provider.offer = nil
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))

        await service.loadOffer()

        #expect(service.offer == nil)
        #expect(!service.isLoadingOffer)
    }

    @Test
    func missingProductIsReportedAsNotListed() async {
        let provider = SpyPurchaseProvider()
        provider.offer = nil
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))

        await service.loadOffer()

        #expect(service.offerFailure == .productNotListed,
                "an empty product list is a store configuration problem, not connectivity")
    }

    @Test
    func thrownLookupIsReportedAsStoreUnreachable() async {
        let provider = SpyPurchaseProvider()
        provider.offerOutcome = .storeUnreachable
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))

        await service.loadOffer()

        #expect(service.offerFailure == .storeUnreachable,
                "a StoreKit throw must not be blamed on the product configuration")
        #expect(service.offer == nil)
    }

    @Test
    func offerFailureClearsWhenTheOfferLoads() async {
        let provider = SpyPurchaseProvider()
        provider.offerOutcome = .storeUnreachable
        let service = PurchaseService(
            provider: provider,
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))
        await service.loadOffer()
        #expect(service.offerFailure == .storeUnreachable)

        provider.offerOutcome = .offer(PurchaseOffer(id: "license",
                                                     displayName: "CheckStitch License",
                                                     displayPrice: "$4.99"))
        await service.loadOffer()

        #expect(service.offerFailure == nil)
        #expect(service.offer?.displayPrice == "$4.99")
    }
}
