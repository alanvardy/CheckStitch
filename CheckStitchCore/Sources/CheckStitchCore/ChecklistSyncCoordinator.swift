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
            Task { await createReminders(checklist) }
        case .context:
            break // watch-only direction
        }
    }

    private let transport: ChecklistSyncTransport
    private let snapshot: () -> [Checklist]
    private let createReminders: (Checklist) async -> Void
}