import Foundation

/// Phone side of the sync seam: pushes the checklist set on start and on every
/// change, and turns run requests into the app's existing reminder creation.
@MainActor
public final class ChecklistSyncCoordinator {
    public init(
        transport: ChecklistSyncTransport,
        snapshot: @escaping () -> [Checklist],
        createReminders: @escaping (Checklist) async -> ReminderRunOutcome,
        language: @escaping @MainActor () -> AppLanguage
    ) {
        self.transport = transport
        self.snapshot = snapshot
        self.createReminders = createReminders
        self.language = language
    }

    public func start() {
        transport.onMessage = { [weak self] in self?.handle($0) }
        // `activate()` is asynchronous, so the pushes below are dropped on a cold
        // start; `onActivated` is what actually seeds the watch.
        transport.onActivated = { [weak self] in
            self?.pushContext()
            self?.pushLanguage()
        }
        transport.activate()
        pushContext()
        pushLanguage()
    }

    public func checklistsDidChange() {
        pushContext()
    }

    private func pushContext() {
        guard let data = try? ChecklistCodec.encode(ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: "", checklists: snapshot())) else { return }
        transport.sendContext(data)
    }

    /// Language travels on the `transferUserInfo` channel, not inside
    /// `updateApplicationContext` — `sendContext` owns that dictionary and
    /// would overwrite a sibling key.
    private func pushLanguage() {
        transport.sendUserInfo(.language(language().rawValue))
    }

    private func handle(_ message: ChecklistSyncMessage) {
        ChecklistSyncDiagnostics.log(.phoneHandle, ["message": message.diagnosticName])
        switch message {
        case .requestChecklists:
            pushContext()
            pushLanguage()
        case .runChecklist(let id, let runID):
            // A re-sent run (activation race, lost result) must not create
            // reminders twice: re-ack with the recorded result instead.
            if let result = rememberedResults[runID] {
                ChecklistSyncDiagnostics.log(.phoneHandle, [
                    "run": runID.uuidString, "result": "duplicate-ack",
                ])
                transport.sendUserInfo(.runResult(result))
                return
            }
            if inFlightRunIDs.contains(runID) {
                ChecklistSyncDiagnostics.log(.phoneHandle, [
                    "run": runID.uuidString, "result": "duplicate-in-flight",
                ])
                return
            }
            guard let checklist = snapshot().first(where: { $0.id == id }) else {
                ChecklistSyncDiagnostics.log(.snapshotLookup, [
                    "run": runID.uuidString, "checklist": id.uuidString, "result": "miss",
                ])
                remember(RunResult(runID: runID, checklistID: id, kind: .notFound))
                transport.sendUserInfo(.runResult(
                    RunResult(runID: runID, checklistID: id, kind: .notFound)))
                pushContext()
                return
            }
            ChecklistSyncDiagnostics.log(.snapshotLookup, [
                "run": runID.uuidString, "checklist": id.uuidString, "result": "hit",
            ])
            inFlightRunIDs.insert(runID)
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
                inFlightRunIDs.remove(runID)
                self.remember(result)
                let sent = transport.sendUserInfo(.runResult(result))
                ChecklistSyncDiagnostics.log(.phoneHandle, [
                    "run": runID.uuidString, "result": sent ? "acked" : "ack-dropped",
                ])
            }
        case .context, .runResult, .language:
            break // watch-only / phone→watch directions
        }
    }

    private let transport: ChecklistSyncTransport
    private let snapshot: () -> [Checklist]
    private let createReminders: (Checklist) async -> ReminderRunOutcome
    private let language: @MainActor () -> AppLanguage
    /// Tail of the serialized run queue; see `handle`.
    private var pendingRun: Task<Void, Never>?
    /// Bounded memory of completed runs so a re-sent request is acked, never
    /// re-created. Insertion-ordered; oldest evicted past the cap.
    private var rememberedResults: [UUID: RunResult] = [:]
    private var rememberedOrder: [UUID] = []
    private let rememberedLimit = 32
    private var inFlightRunIDs: Set<UUID> = []

    private func remember(_ result: RunResult) {
        if rememberedResults[result.runID] == nil { rememberedOrder.append(result.runID) }
        rememberedResults[result.runID] = result
        while rememberedOrder.count > rememberedLimit {
            rememberedResults.removeValue(forKey: rememberedOrder.removeFirst())
        }
    }
}