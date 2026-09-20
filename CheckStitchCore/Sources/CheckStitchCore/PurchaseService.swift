import Foundation
import Observation

/// Entitlement source for the run gate. Resolves StoreKit entitlement and
/// drives the paywall's offer/purchase flow.
@MainActor
@Observable
public final class PurchaseService {
    public enum EntitlementState: Equatable, Sendable { case unknown, locked, unlocked }

    public init(provider: any PurchaseProviding) {
        self.provider = provider
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
            self?.entitlement = unlocked ? .unlocked : .locked
        }
        entitlement = await provider.currentEntitlement() ? .unlocked : .locked
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
            if try await provider.purchase() { entitlement = .unlocked }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private let provider: any PurchaseProviding
    private var hasStarted = false
}
