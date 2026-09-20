import Foundation
import Observation

/// Durable cache of a *verified* entitlement, so a paid user stays unlocked on a
/// cold launch while StoreKit is unreachable. Only ever written after a verified
/// transaction; never downgraded (fail-open).
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

    public init(provider: any PurchaseProviding,
                cache: PurchaseEntitlementCache = PurchaseEntitlementCache(defaults: .standard)) {
        self.provider = provider
        self.cache = cache
        self.entitlement = cache.isVerified ? .unlocked : .unknown
    }

    public private(set) var entitlement: EntitlementState = .unknown
    public private(set) var offer: PurchaseOffer?
    public private(set) var isLoadingOffer = false
    public private(set) var isPurchasing = false
    public private(set) var lastError: String?

    public var isUnlocked: Bool { entitlement == .unlocked }

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
        offer = await provider.offer()
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

    /// Apply a just-resolved entitlement, never downgrading an already-verified
    /// unlock (fail-open).
    private func apply(_ verifiedUnlocked: Bool) {
        if verifiedUnlocked {
            cache.setVerified(true)
            entitlement = .unlocked
        } else if cache.isVerified {
            // Fail-open: never downgrade an already-verified unlock.
            entitlement = .unlocked
        } else {
            entitlement = .locked
        }
    }

    private let provider: any PurchaseProviding
    private let cache: PurchaseEntitlementCache
    private var hasStarted = false
}
