import Foundation
import Observation

/// `WCSession` dictionary keys. Shared so both adapters and the tests agree.
public enum ChecklistSyncKey {
    public static let context = "checklists"
    public static let runChecklist = "runChecklist"
    public static let runChecklistRunID = "runChecklistRunID"
    public static let requestChecklists = "requestChecklists"
    public static let runResult = "runResult"
    public static let runResultRunID = "runID"
    public static let runResultChecklistID = "checklistID"
    public static let runResultKind = "kind"
    public static let runResultCount = "count"
}

/// The phone's answer to one run request. Mirrors `ReminderRunOutcome` and
/// drops the free-form failure message: the watch renders a fixed reason per
/// kind.
public enum RunResultKind: Equatable, Sendable {
    case created(Int)
    case permissionDenied
    case destinationMissing
    /// The phone no longer has this checklist; it is re-pushing its context.
    case notFound
    case failed

    public init(_ outcome: ReminderRunOutcome) {
        switch outcome {
        case .created(let count): self = .created(count)
        case .permissionDenied: self = .permissionDenied
        case .destinationMissing: self = .destinationMissing
        case .failed: self = .failed
        }
    }

    /// Short user-facing reason. Plain English, matching
    /// `ReminderRunOutcome.errorMessage` (Core reason strings are not
    /// localized in this repo).
    public var message: String {
        switch self {
        case .created(let count): "Created \(count) reminders."
        case .permissionDenied: "CheckStitch doesn't have permission to access Reminders."
        case .destinationMissing: "That list no longer exists."
        case .notFound: "Not found — refreshing."
        case .failed: "Couldn't create reminders."
        }
    }

    var wireName: String {
        switch self {
        case .created: "created"
        case .permissionDenied: "permissionDenied"
        case .destinationMissing: "destinationMissing"
        case .notFound: "notFound"
        case .failed: "failed"
        }
    }

    init?(wireName: String, count: Int?) {
        switch wireName {
        case "created":
            guard let count else { return nil }
            self = .created(count)
        case "permissionDenied": self = .permissionDenied
        case "destinationMissing": self = .destinationMissing
        case "notFound": self = .notFound
        case "failed": self = .failed
        default: return nil
        }
    }
}

/// One completed (or refused) run, echoed back to the watch so its button
/// reflects the phone, not the transport.
public struct RunResult: Equatable, Sendable {
    public let runID: UUID
    public let checklistID: UUID
    public let kind: RunResultKind

    public init(runID: UUID, checklistID: UUID, kind: RunResultKind) {
        self.runID = runID
        self.checklistID = checklistID
        self.kind = kind
    }
}

/// The two directions of the watch protocol. `UUID` is not a plist type, so it
/// travels as its `uuidString`.
public enum ChecklistSyncMessage: Equatable, Sendable {
    /// Phone → watch, via `updateApplicationContext` (latest state wins).
    case context(Data)
    /// Watch → phone, via `transferUserInfo` (queued command). `runID` is a
    /// fresh per-tap id: the correlation key for logs and the de-dup key for
    /// re-sent runs.
    case runChecklist(id: UUID, runID: UUID)
    /// Watch → phone, via `transferUserInfo` (cold launch re-push request).
    case requestChecklists
    /// Phone → watch, via `transferUserInfo` (the phone's answer to a run).
    /// `runID` echoes the request's id so the watch can match the result.
    case runResult(RunResult)

    public init?(userInfo: [String: Any]) {
        if let data = userInfo[ChecklistSyncKey.context] as? Data {
            self = .context(data)
        } else if let raw = userInfo[ChecklistSyncKey.runChecklist] as? String,
                  let id = UUID(uuidString: raw),
                  let runRaw = userInfo[ChecklistSyncKey.runChecklistRunID] as? String,
                  let runID = UUID(uuidString: runRaw) {
            self = .runChecklist(id: id, runID: runID)
        } else if userInfo[ChecklistSyncKey.requestChecklists] as? Bool == true {
            self = .requestChecklists
        } else if let dict = userInfo[ChecklistSyncKey.runResult] as? [String: Any],
                  let runRaw = dict[ChecklistSyncKey.runResultRunID] as? String,
                  let runID = UUID(uuidString: runRaw),
                  let checklistRaw = dict[ChecklistSyncKey.runResultChecklistID] as? String,
                  let checklistID = UUID(uuidString: checklistRaw),
                  let kindRaw = dict[ChecklistSyncKey.runResultKind] as? String,
                  let kind = RunResultKind(wireName: kindRaw, count: dict[ChecklistSyncKey.runResultCount] as? Int) {
            self = .runResult(RunResult(runID: runID, checklistID: checklistID, kind: kind))
        } else {
            return nil
        }
    }

    public var userInfo: [String: Any] {
        switch self {
        case .context(let data):
            [ChecklistSyncKey.context: data]
        case .runChecklist(let id, let runID):
            [ChecklistSyncKey.runChecklist: id.uuidString,
             ChecklistSyncKey.runChecklistRunID: runID.uuidString]
        case .requestChecklists:
            [ChecklistSyncKey.requestChecklists: true]
        case .runResult(let result):
            [ChecklistSyncKey.runResult: runResultDict(result)]
        }
    }

    /// The `runResult` payload, including `count` only for `.created`.
    private func runResultDict(_ result: RunResult) -> [String: Any] {
        var dict: [String: Any] = [
            ChecklistSyncKey.runResultRunID: result.runID.uuidString,
            ChecklistSyncKey.runResultChecklistID: result.checklistID.uuidString,
            ChecklistSyncKey.runResultKind: result.kind.wireName,
        ]
        if case .created(let count) = result.kind {
            dict[ChecklistSyncKey.runResultCount] = count
        }
        return dict
    }

    /// Compact description for the `ChecklistSyncDiagnostics` records.
    public var diagnosticName: String {
        switch self {
        case .context(let data): "context(\(data.count))b"
        case .runChecklist(let id, let runID): "runChecklist(id:\(id.uuidString),run:\(runID.uuidString))"
        case .requestChecklists: "requestChecklists"
        case .runResult(let result):
            "runResult(run:\(result.runID.uuidString),kind:\(result.kind.wireName))"
        }
    }
}

/// The seam both adapters (phone and watch) implement and the tests fake.
///
/// `activate()` is asynchronous, so a send issued in the same turn is dropped.
/// `onActivated` fires once the session is usable and is the signal to re-push
/// or re-request. The `send…` methods report whether the session accepted the
/// message, so callers can avoid claiming success for a dropped send.
@MainActor
public protocol ChecklistSyncTransport: AnyObject {
    var onMessage: ((ChecklistSyncMessage) -> Void)? { get set }
    var onActivated: (() -> Void)? { get set }
    func activate()
    @discardableResult func sendContext(_ data: Data) -> Bool
    @discardableResult func sendUserInfo(_ message: ChecklistSyncMessage) -> Bool
}

/// What the watch button shows for one run.
public enum RunPhase: Equatable, Sendable {
    case idle
    case sending
    case created(Int)
    case failed(String)
}

/// The watch's observable state: a mirror of the phone's checklist set, plus
/// the last run requested. It never touches EventKit.
@MainActor
@Observable
public final class WatchChecklistStore {
    public init(transport: ChecklistSyncTransport) {
        self.transport = transport
    }

    public private(set) var checklists: [Checklist] = []
    public private(set) var pendingRunID: UUID?
    private var phases: [UUID: RunPhase] = [:]

    /// The phase of `runID`; `.idle` for an unknown run.
    public func runPhase(runID: UUID) -> RunPhase { phases[runID] ?? .idle }

    /// Activates the transport and starts listening. Safe to call repeatedly.
    /// The refresh is requested from `onActivated` rather than here: a send that
    /// races `activate()` is dropped, so a cold launch would otherwise never ask
    /// the phone for its context.
    public func start() {
        transport.onMessage = { [weak self] in self?.receive($0) }
        transport.onActivated = { [weak self] in self?.requestRefresh() }
        transport.activate()
    }

    /// Asks the phone to create reminders for `checklist` and remembers the
    /// run. Returns the new `runID`, or `nil` when the transport rejected the
    /// send — `nil` means nothing was sent and the UI must not report success.
    @discardableResult
    public func run(_ checklist: Checklist) -> UUID? {
        let runID = UUID()
        let accepted = transport.sendUserInfo(.runChecklist(id: checklist.id, runID: runID))
        ChecklistSyncDiagnostics.log(.watchSend, [
            "run": runID.uuidString,
            "checklist": checklist.id.uuidString,
            "accepted": accepted ? "true" : "false",
        ])
        guard accepted else { return nil }
        pendingRunID = runID
        phases[runID] = .sending
        return runID
    }

    /// Cold launch: the phone re-pushes its context on receipt.
    @discardableResult
    public func requestRefresh() -> Bool {
        transport.sendUserInfo(.requestChecklists)
    }

    private func receive(_ message: ChecklistSyncMessage) {
        switch message {
        case .context(let data):
            // Malformed or future-version payloads leave the previous list intact.
            switch ChecklistCodec.classify(data) {
            case .loaded(let envelope):
                checklists = envelope.checklists
            case .migratable(let from, let envelope) where from >= 2:
                // v2/v3 contexts carry sync state; accept rather than blanking
                // the list. Display order comes from `items`, which is intact.
                checklists = envelope.checklists
            default:
                break
            }
        case .runResult(let result):
            if pendingRunID == result.runID { pendingRunID = nil }
            if case .notFound = result.kind {
                // The phone is re-pushing; ask for it too in case the push is
                // dropped pre-activation.
                requestRefresh()
            }
            phases[result.runID] = switch result.kind {
            case .created(let count): .created(count)
            case .permissionDenied, .destinationMissing, .notFound, .failed: .failed(result.kind.message)
            }
        case .runChecklist, .requestChecklists:
            break // phone-only directions
        }
    }

    private let transport: ChecklistSyncTransport
}