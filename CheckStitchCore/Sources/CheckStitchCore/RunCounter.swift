import Foundation

/// Durable "successful runs" counter in an injected `UserDefaults` suite (the
/// App Group in production). Mirrors `AppLanguagePreference`'s validated-read
/// convention: missing/corrupt/negative reads as `0`.
@MainActor
public final class RunCounter {
    public init(defaults: UserDefaults, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public static let defaultsKey = "runCount.v1"

    /// Validated count; absent, non-integer or negative → 0.
    public var count: Int {
        guard let stored = defaults.object(forKey: key) as? Int, stored >= 0 else { return 0 }
        return stored
    }

    public func increment() { defaults.set(count + 1, forKey: key) }
    public func reset() { defaults.removeObject(forKey: key) }

    private let defaults: UserDefaults
    private let key: String
}

/// The "may I run this checklist?" policy. Permits every run while unlocked;
/// otherwise permits while `count < limit`. Callers must call `recordSuccess()`
/// exactly once per `.created` outcome — nothing else advances the counter.
@MainActor
public struct RunGate: Sendable {
    public static let freeRunLimit = 20

    public init(counter: RunCounter, isUnlocked: Bool, limit: Int = freeRunLimit) {
        self.counter = counter
        self.isUnlocked = isUnlocked
        self.limit = limit
    }

    public var permitsRun: Bool { isUnlocked || counter.count < limit }

    public func recordSuccess() { counter.increment() }

    private let counter: RunCounter
    private let isUnlocked: Bool
    private let limit: Int
}