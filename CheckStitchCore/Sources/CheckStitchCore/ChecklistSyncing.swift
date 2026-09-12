import Foundation

/// Seam over the iCloud key-value store the checklist payload travels through.
/// `Data`-only so it carries no app-target model.
@MainActor
public protocol ChecklistSyncing: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func synchronize()
    @discardableResult
    func startObserving(_ onChange: @escaping @MainActor () -> Void) -> any ChecklistSyncObservation
}

/// Cancels a change subscription. Cancelling a token twice is allowed.
@MainActor
public protocol ChecklistSyncObservation: Sendable {
    func cancel()
}

/// Real adapter over one long-lived `NSUbiquitousKeyValueStore` and one key.
@MainActor
public final class UbiquitousChecklistSync: ChecklistSyncing {
    public init(store: NSUbiquitousKeyValueStore = .default, key: String = "checklists.v1") {
        self.store = store
        self.key = key
    }

    public func read() throws -> Data? { store.data(forKey: key) }
    public func write(_ data: Data) throws { store.set(data, forKey: key) }
    public func synchronize() { _ = store.synchronize() }

    @discardableResult
    public func startObserving(_ onChange: @escaping @MainActor () -> Void) -> any ChecklistSyncObservation {
        let token = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { _ in
            // The notification can arrive off-main; hop before calling back.
            MainActor.assumeIsolated { onChange() }
        }
        return NotificationObservation(token: token)
    }

    private let store: NSUbiquitousKeyValueStore
    private let key: String
}

/// Removes the NotificationCenter observer on `cancel()`.
@MainActor
private final class NotificationObservation: ChecklistSyncObservation {
    public init(token: NSObjectProtocol) { self.token = token }

    public func cancel() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }

    private var token: NSObjectProtocol?
}