import CheckStitchCore
import os
import StoreKit

/// The only StoreKit-importing type. Kept in the app target so
/// `CheckStitchCore` (also compiled for watchOS) stays StoreKit-free.
@MainActor
final class StoreKitPurchaseService: PurchaseProviding {
    static let productID = "app.alanvardy.CheckStitch.unlimited"

    private let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "purchases")

    private var updatesTask: Task<Void, Never>?

    func offer() async -> OfferLoadOutcome {
        do {
            let products = try await Product.products(for: [Self.productID])
            guard let product = products.first else {
                logger.error("""
                StoreKit listed no product for '\(Self.productID, privacy: .public)'. \
                Check that the In-App Purchase exists in App Store Connect, is \
                'Cleared for Sale' with a price and review screenshot, and that the \
                Paid Applications Agreement is Active.
                """)
                return .productNotListed
            }
            logger.info("StoreKit offer loaded: \(product.id, privacy: .public) \(product.displayPrice, privacy: .public)")
            return .offer(PurchaseOffer(id: product.id,
                                        displayName: product.displayName,
                                        displayPrice: product.displayPrice))
        } catch {
            logger.error("""
            StoreKit product lookup failed for '\(Self.productID, privacy: .public)': \
            \(error.localizedDescription, privacy: .public)
            """)
            return .storeUnreachable
        }
    }

    func currentEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    func purchase() async throws -> Bool {
        guard let product = try await Product.products(for: [Self.productID]).first else {
            throw PurchaseError.productUnavailable
        }
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw PurchaseError.unverified
            }
            await transaction.finish()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async throws -> Bool {
        try await AppStore.sync()
        return await currentEntitlement()
    }

    func startObserving(_ onChange: @escaping @MainActor (Bool) -> Void) {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                guard transaction.productID == Self.productID,
                      transaction.revocationDate == nil else { continue }
                await transaction.finish()
                onChange(true)
            }
        }
    }
}

enum PurchaseError: LocalizedError {
    case productUnavailable
    case unverified

    var errorDescription: String? {
        switch self {
        case .productUnavailable: "The CheckStitch license isn't available right now."
        case .unverified: "The purchase couldn't be verified."
        }
    }
}
