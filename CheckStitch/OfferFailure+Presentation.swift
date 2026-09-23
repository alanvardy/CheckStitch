import CheckStitchCore
import SwiftUI

/// User-facing copy for a failed offer load. The two failures need different
/// advice: an unreachable store is a connectivity problem the user can act on,
/// while a store that answered without the product is an App Store Connect
/// configuration problem that retrying the network will never fix.
extension PurchaseService.OfferFailure {
    var advice: LocalizedStringKey {
        switch self {
        case .storeUnreachable: "Couldn't load the store. Check your connection and try again."
        case .productNotListed: "This purchase isn't available right now. Please try again later."
        }
    }
}