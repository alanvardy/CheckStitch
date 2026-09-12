import Foundation

/// Phone side of the sync seam: pushes the checklist set on start and on every
/// change, and turns run requests into the app's existing reminder creation.
@MainActor
public final class ChecklistSyncCoordinator {
    public init(
        transport: ChecklistSyncTransport,
        snapshot: @escaping () -> [Checklist],
        createReminders: @escaping (Checklist) async -> Void
    ) {
        self.transport = transport
        self.snapshot = snapshot
        self.createReminders = createReminders
    }

    public func start() {
        transport.onMessage = { [weak self] in self?.handle($0) }
        // `activate()` is asynchronous, so the push below is dropped on a cold
        // start; `onActivated` is what actually seeds the watch.
        transport.onActivated = { [weak self] in self?.pushContext() }
        transport.activate()
        pushContext()
    }

    public func checklistsDidChange() {
        pushContext()
    }

    private func pushContext() {
        guard let data = try? ChecklistCodec.encode(snapshot()) else { return }
        transport.sendContext(data)
    }

    private func handle(_ message: ChecklistSyncMessage) {
        switch message {
        case .requestChecklists:
            pushContext()
        case .runChecklist(let id):
            guard let checklist = snapshot().first(where: { $0.id == id }) else { return }
            // Chain runs so overlapping requests never hold two EventKit stores
            // open at once (EKCADErrorDomain 1021).
            let previous = pendingRun
            pendingRun = Task { [createReminders] in
                await previous?.value
                await createReminders(checklist)
            }
        case .context:
            break // watch-only direction
        }
    }

    private let transport: ChecklistSyncTransport
    private let snapshot: () -> [Checklist]
    private let createReminders: (Checklist) async -> Void
    /// Tail of the serialized run queue; see `handle`.
    private var pendingRun: Task<Void, Never>?
}