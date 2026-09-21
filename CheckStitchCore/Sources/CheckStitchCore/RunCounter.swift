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

    /// Undoes one `increment()`, never below zero.
    public func decrement() {
        let next = count - 1
        if next <= 0 {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(next, forKey: key)
        }
    }

    public func reset() { defaults.removeObject(forKey: key) }

    private let defaults: UserDefaults
    private let key: String
}

/// The "may I run this checklist?" policy. Permits every run while unlocked;
/// otherwise permits while `count < limit`. `reserveRun()` consumes a free slot
/// atomically (check and increment are one synchronous step, so concurrent runs
/// cannot both pass at the limit); `releaseRun()` returns the slot when the run
/// created nothing. While unlocked the counter is capped at `limit` so it cannot
/// grow without bound.
@MainActor
public struct RunGate: Sendable {
    public static let freeRunLimit = 20

    public init(counter: RunCounter, isUnlocked: Bool, limit: Int = freeRunLimit) {
        self.counter = counter
        self.isUnlocked = isUnlocked
        self.limit = limit
    }

    public var permitsRun: Bool { isUnlocked || counter.count < limit }

    /// Reserves a slot, incrementing the durable counter at most once. Returns
    /// `false` when the free limit is reached and no license is held. Callers
    /// must `releaseRun()` if the run creates nothing.
    public mutating func reserveRun() -> Bool {
        guard permitsRun else { return false }
        didReserve = true
        if counter.count < limit {
            counter.increment()
            didIncrement = true
        }
        return true
    }

    /// Returns a slot reserved by `reserveRun()` when the run created nothing.
    public mutating func releaseRun() {
        guard didReserve else { return }
        if didIncrement { counter.decrement() }
        didReserve = false
        didIncrement = false
    }

    private let counter: RunCounter
    private let isUnlocked: Bool
    private let limit: Int
    private var didReserve = false
    private var didIncrement = false
}