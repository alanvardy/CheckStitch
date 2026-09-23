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

/// Outcome of loading the storefront offer. Distinguishes a store that could not
/// be reached (StoreKit threw) from one that answered but does not list the
/// product for the requested id. The two need different advice: the former is a
/// connectivity problem, the latter an App Store Connect configuration problem
/// that retrying the network will never fix.
public enum OfferLoadOutcome: Equatable, Sendable {
    case offer(PurchaseOffer)
    /// StoreKit threw — network, Storefront, or authentication failure.
    case storeUnreachable
    /// The store answered but returned no product for the requested id.
    case productNotListed
}

/// Seam over StoreKit 2. Mirrors `ReminderDestinationTargeting`: a `@MainActor`
/// protocol so the service and its tests share one isolation domain.
@MainActor
public protocol PurchaseProviding: Sendable {
    /// Loads the license offer and reports *why* it failed when it does.
    func offer() async -> OfferLoadOutcome
    /// Verified entitlement for the license, `false` when none is held.
    func currentEntitlement() async -> Bool
    /// Runs the purchase flow. `true` means a verified entitlement is now held.
    func purchase() async throws -> Bool
    /// `AppStore.sync()` then re-read entitlement. `true` means unlocked now.
    func restore() async throws -> Bool
    /// Fires on `Transaction.updates`; the argument is the new verified state.
    func startObserving(_ onChange: @escaping @MainActor (Bool) -> Void)
}
