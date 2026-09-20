import Foundation

/// Storefront offer for the license. Field subset of StoreKit's `Product` that
/// Core needs; the adapter maps it.
public struct PurchaseOffer: Equatable, Sendable {
    public init(id: String, displayName: String, displayPrice: String) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
    }

    public let id: String
    public let displayName: String
    public let displayPrice: String
}

/// Seam over StoreKit 2. Mirrors `ReminderDestinationTargeting`: a `@MainActor`
/// protocol so the service and its tests share one isolation domain.
@MainActor
public protocol PurchaseProviding: Sendable {
    /// Loads the license offer; `nil` when the store is unreachable.
    func offer() async -> PurchaseOffer?
    /// Verified entitlement for the license, `false` when none is held.
    func currentEntitlement() async -> Bool
    /// Runs the purchase flow. `true` means a verified entitlement is now held.
    func purchase() async throws -> Bool
    /// `AppStore.sync()` then re-read entitlement. `true` means unlocked now.
    func restore() async throws -> Bool
    /// Fires on `Transaction.updates`; the argument is the new verified state.
    func startObserving(_ onChange: @escaping @MainActor (Bool) -> Void)
}
