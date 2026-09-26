import Foundation

/// The process-wide purchase service. The app target replaces `service` at
/// launch with the StoreKit-backed instance; out-of-app processes (widgets,
/// Siri) keep the StoreKit-free default.
@MainActor
public enum PurchaseEnvironment {
    public static var service: PurchaseService = PurchaseService(
        provider: CachedEntitlementProvider(),
        cache: PurchaseEntitlementCache(defaults: AppGroup.defaults))
}

/// StoreKit-free provider for cold extension processes: reports the durable
/// verified-entitlement cache and never starts a StoreKit session.
@MainActor
public struct CachedEntitlementProvider: PurchaseProviding {
    public init() {}
    public func offer() async -> PurchaseOffer? { nil }
    public func currentEntitlement() async -> Bool {
        PurchaseEntitlementCache(defaults: AppGroup.defaults).isVerified
    }
    public func purchase() async throws -> Bool { false }
    public func restore() async throws -> Bool { false }
    public func startObserving(_ onChange: @escaping @MainActor (Bool) -> Void) {}
}