import Foundation
import Observation

/// `WCSession` dictionary keys. Shared so both adapters and the tests agree.
public enum ChecklistSyncKey {
    public static let context = "checklists"
    public static let runChecklist = "runChecklist"
    public static let runChecklistRunID = "runChecklistRunID"
    public static let requestChecklists = "requestChecklists"
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
        }
    }

    /// Compact description for the `ChecklistSyncDiagnostics` records.
    public var diagnosticName: String {
        switch self {
        case .context(let data): "context(\(data.count))b"
        case .runChecklist(let id, let runID): "runChecklist(id:\(id.uuidString),run:\(runID.uuidString))"
        case .requestChecklists: "requestChecklists"
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
        case .runChecklist, .requestChecklists:
            break // phone-only directions
        }
    }

    private let transport: ChecklistSyncTransport
}