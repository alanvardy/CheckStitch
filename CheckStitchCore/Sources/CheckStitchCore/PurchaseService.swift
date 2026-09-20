import Foundation
import Observation

/// Entitlement source for the run gate. Phase 1 is a stub: always locked.
@MainActor
@Observable
public final class PurchaseService {
    public enum EntitlementState: Equatable, Sendable {
        case unknown
        case locked
        case unlocked
    }

    public init() {}

    public private(set) var entitlement: EntitlementState = .locked

    public var isUnlocked: Bool { entitlement == .unlocked }

    public func start() async {}
}