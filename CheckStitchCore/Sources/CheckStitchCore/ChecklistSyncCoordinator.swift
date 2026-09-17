import Foundation

/// Phone side of the sync seam: pushes the checklist set on start and on every
/// change, and turns run requests into the app's existing reminder creation.
@MainActor
public final class ChecklistSyncCoordinator {
    public init(
        transport: ChecklistSyncTransport,
        snapshot: @escaping () -> [Checklist],
        createReminders: @escaping (Checklist) async -> ReminderRunOutcome
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
        guard let data = try? ChecklistCodec.encode(ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: "", checklists: snapshot())) else { return }
        transport.sendContext(data)
    }

    private func handle(_ message: ChecklistSyncMessage) {
        ChecklistSyncDiagnostics.log(.phoneHandle, ["message": message.diagnosticName])
        switch message {
        case .requestChecklists:
            pushContext()
        case .runChecklist(let id, let runID):
            guard let checklist = snapshot().first(where: { $0.id == id }) else {
                ChecklistSyncDiagnostics.log(.snapshotLookup, [
                    "run": runID.uuidString, "checklist": id.uuidString, "result": "miss",
                ])
                // The watch's list is stale: tell it so and hand it the truth.
                transport.sendUserInfo(.runResult(
                    RunResult(runID: runID, checklistID: id, kind: .notFound)))
                pushContext()
                return
            }
            ChecklistSyncDiagnostics.log(.snapshotLookup, [
                "run": runID.uuidString, "checklist": id.uuidString, "result": "hit",
            ])
            // Chain runs so overlapping requests never hold two EventKit stores
            // open at once (EKCADErrorDomain 1021).
            let previous = pendingRun
            pendingRun = Task { [createReminders, transport] in
                await previous?.value
                let outcome = await createReminders(checklist)
                let result = RunResult(runID: runID, checklistID: id, kind: RunResultKind(outcome))
                ChecklistSyncDiagnostics.log(.createOutcome, [
                    "run": runID.uuidString,
                    "checklist": id.uuidString,
                    "outcome": String(describing: outcome),
                ])
                transport.sendUserInfo(.runResult(result))
            }
        case .context, .runResult:
            break // watch-only / phone→watch directions
        }
    }

    private let transport: ChecklistSyncTransport
    private let snapshot: () -> [Checklist]
    private let createReminders: (Checklist) async -> ReminderRunOutcome
    /// Tail of the serialized run queue; see `handle`.
    private var pendingRun: Task<Void, Never>?
}