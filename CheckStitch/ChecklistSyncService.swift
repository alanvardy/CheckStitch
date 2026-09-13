import CheckStitchCore
import Foundation
import Observation

enum SyncOutcome: Equatable, Sendable {
    case synced
    case seeded
    case unavailable
    case failed(String)
}

/// Coordinates the offline `ChecklistStore` with the iCloud key-value bytes
/// behind `ChecklistSyncing`: reconciles on launch, on external change
/// notifications and on pull-to-refresh, coalesces concurrent async reconciles
/// onto one in-flight pass, and debounces local-edit pushes. `pushNow()` is the
/// one deliberate synchronous bypass — it must finish before the app suspends,
/// and the merge's idempotence guard makes an overlapping pass harmless.
@MainActor
@Observable
final class ChecklistSyncService {
    private(set) var isSyncing = false
    private(set) var lastOutcome: SyncOutcome?

    private let sync: any ChecklistSyncing
    private let store: ChecklistStore
    private let pushDelay: Duration?

    @ObservationIgnored private var observation: (any ChecklistSyncObservation)?
    @ObservationIgnored private var inFlight: Task<SyncOutcome, Never>?
    @ObservationIgnored private var inFlightID: UUID?
    @ObservationIgnored private var pushTask: Task<Void, Never>?

    init(sync: any ChecklistSyncing,
         store: ChecklistStore,
         pushDelay: Duration? = .milliseconds(500)) {
        self.sync = sync
        self.store = store
        self.pushDelay = pushDelay
    }

    /// Wires the external-change observer and the store's local-edit callback.
    /// Call once, right after construction.
    func start() {
        observation = sync.startObserving { [weak self] in
            guard let self else { return }
            Task { await self.reconcile() }
        }
        store.onChange = { [weak self] in self?.schedulePush() }
    }

    @discardableResult
    func syncOnLaunch() async -> SyncOutcome {
        // Nudge KVS to pull before the first read; `read()` only sees the local
        // cache, so without this a fresh install can read `nil` while the
        // account's cloud payload already exists.
        sync.synchronize()
        return await reconcile()
    }

    /// Coalesces concurrent callers onto a single in-flight reconcile.
    @discardableResult
    func reconcile() async -> SyncOutcome {
        if let inFlight { return await inFlight.value }
        let id = UUID()
        let task = Task { self.reconcileNow() }
        inFlight = task
        inFlightID = id
        let outcome = await task.value
        if inFlightID == id {
            inFlight = nil
            inFlightID = nil
        }
        return outcome
    }

    /// Pull-to-refresh: ask iCloud for the latest bytes, then reconcile.
    func refresh() async -> SyncOutcome {
        sync.synchronize()
        return await reconcile()
    }

    /// Immediate push for backgrounding — must not wait out the debounce, and
    /// must complete synchronously before the app suspends, so it runs
    /// `reconcileNow()` directly instead of the async `reconcile()` gate.
    func pushNow() {
        pushTask?.cancel()
        pushTask = nil
        _ = reconcileNow()
    }

    func schedulePush() {
        guard let pushDelay else { return pushNow() }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: pushDelay)
            guard !Task.isCancelled else { return }
            self?.pushNow()
        }
    }

    private func reconcileNow() -> SyncOutcome {
        isSyncing = true
        defer { isSyncing = false }

        guard store.canAcceptRemoteChanges else { return finish(.unavailable) }

        let remoteData: Data?
        do { remoteData = try sync.read() } catch { return finish(.unavailable) }

        guard let remoteData else {
            // The cloud holds nothing we can see. Never push an *empty* local
            // payload: on a freshly installed device KVS may not have pulled the
            // account's data yet, and an empty write would win last-write-wins
            // over real remote state. Only seed when there is something to seed.
            let local = store.envelope
            guard !local.checklists.isEmpty || !local.tombstones.isEmpty else {
                return finish(.synced)
            }
            do { try sync.write(try ChecklistCodec.encode(local)) }
            catch { return finish(.failed(error.localizedDescription)) }
            sync.synchronize()
            return finish(.seeded)
        }

        let remote: ChecklistEnvelope
        switch ChecklistCodec.classify(remoteData) {
        case .loaded(let envelope):
            remote = envelope
        case .migratable(_, let checklists):
            remote = ChecklistEnvelope(deviceID: "", checklists: checklists.map { $0.migrated(at: .distantPast) })
        case .unsupportedVersion, .unreadable:
            // Never discard local state because the remote bytes were foreign.
            return finish(.failed("Stored sync data could not be read."))
        }

        let visibleChanged = store.apply(remote: remote)
        if visibleChanged || !store.envelope.contentEquals(remote) {
            do { try sync.write(try ChecklistCodec.encode(store.envelope)) }
            catch { return finish(.failed(error.localizedDescription)) }
            sync.synchronize()
        }
        return finish(.synced)
    }

    private func finish(_ outcome: SyncOutcome) -> SyncOutcome {
        lastOutcome = outcome
        return outcome
    }
}
