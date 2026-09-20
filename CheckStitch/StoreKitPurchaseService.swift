import CheckStitchCore
import StoreKit

/// The only StoreKit-importing type. Kept in the app target so
/// `CheckStitchCore` (also compiled for watchOS) stays StoreKit-free.
@MainActor
final class StoreKitPurchaseService: PurchaseProviding {
    static let productID = "app.alanvardy.CheckStitch.license"

    private var updatesTask: Task<Void, Never>?

    func offer() async -> PurchaseOffer? {
        guard let product = try? await Product.products(for: [Self.productID]).first else {
            return nil
        }
        return PurchaseOffer(id: product.id,
                             displayName: product.displayName,
                             displayPrice: product.displayPrice)
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
