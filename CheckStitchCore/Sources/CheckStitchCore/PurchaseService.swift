import Foundation
import Observation

/// Durable cache of a *verified* entitlement, so a paid user is unlocked the
/// instant the app launches (before StoreKit's async resolution finishes) and so
/// a cold launch does not flash the paywall. StoreKit remains the source of
/// truth: a definitive `false` (including a revoked/refunded transaction)
/// clears the cache.
public struct PurchaseEntitlementCache {
    public init(defaults: UserDefaults, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public static let defaultsKey = "purchase.verified.v1"

    public var isVerified: Bool { defaults.bool(forKey: key) }
    public func setVerified(_ verified: Bool) { defaults.set(verified, forKey: key) }

    private let defaults: UserDefaults
    private let key: String
}

/// Entitlement source for the run gate. Resolves StoreKit entitlement and
/// drives the paywall's offer/purchase flow.
@MainActor
@Observable
public final class PurchaseService {
    public enum EntitlementState: Equatable, Sendable { case unknown, locked, unlocked }

    /// Why a store offer could not be loaded. The UI gives different advice for
    /// each: an unreachable store is a connectivity problem, while a store that
    /// answered without the product is a configuration problem the user cannot
    /// fix by retrying their network.
    public enum OfferFailure: Equatable, Sendable { case storeUnreachable, productNotListed }

    public init(provider: any PurchaseProviding,
                cache: PurchaseEntitlementCache = PurchaseEntitlementCache(defaults: .standard)) {
        self.provider = provider
        self.cache = cache
        self.entitlement = cache.isVerified ? .unlocked : .unknown
    }

    public private(set) var entitlement: EntitlementState = .unknown
    public private(set) var offerOutcome: OfferLoadOutcome?
    public private(set) var isLoadingOffer = false
    public private(set) var isPurchasing = false
    public private(set) var lastError: String?

    public var isUnlocked: Bool { entitlement == .unlocked }

    /// The loaded license offer, if any.
    public var offer: PurchaseOffer? {
        if case .offer(let offer) = offerOutcome { offer } else { nil }
    }

    /// Why the offer could not be loaded — `nil` while loading or once loaded.
    public var offerFailure: OfferFailure? {
        switch offerOutcome {
        case .storeUnreachable: .storeUnreachable
        case .productNotListed: .productNotListed
        case .offer, nil: nil
        }
    }

    /// Resolve entitlement and subscribe to `Transaction.updates`. Idempotent.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        provider.startObserving { [weak self] unlocked in
            self?.apply(unlocked)
        }
        apply(await provider.currentEntitlement())
    }

    public func loadOffer() async {
        guard offer == nil, !isLoadingOffer else { return }
        isLoadingOffer = true
        defer { isLoadingOffer = false }
        offerOutcome = await provider.offer()
    }

    public func purchase() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }
        do {
            if try await provider.purchase() { apply(true) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func restore() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }
        do {
            apply(try await provider.restore())
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Apply a just-resolved entitlement. A verified unlock is cached; a
    /// definitive `false` (no entitlement, revocation or refund) clears the
    /// cache and locks, so store state always wins over a stale local flag.
    private func apply(_ verifiedUnlocked: Bool) {
        cache.setVerified(verifiedUnlocked)
        entitlement = verifiedUnlocked ? .unlocked : .locked
    }

    private let provider: any PurchaseProviding
    private let cache: PurchaseEntitlementCache
    private var hasStarted = false
}
