import Foundation
import Observation

/// `WCSession` dictionary keys. Shared so both adapters and the tests agree.
public enum ChecklistSyncKey {
    public static let context = "checklists"
    public static let runChecklist = "runChecklist"
    public static let requestChecklists = "requestChecklists"
}

/// The two directions of the watch protocol. `UUID` is not a plist type, so it
/// travels as its `uuidString`.
public enum ChecklistSyncMessage: Equatable, Sendable {
    /// Phone → watch, via `updateApplicationContext` (latest state wins).
    case context(Data)
    /// Watch → phone, via `transferUserInfo` (queued command).
    case runChecklist(UUID)
    /// Watch → phone, via `transferUserInfo` (cold launch re-push request).
    case requestChecklists

    public init?(userInfo: [String: Any]) {
        if let data = userInfo[ChecklistSyncKey.context] as? Data {
            self = .context(data)
        } else if let raw = userInfo[ChecklistSyncKey.runChecklist] as? String,
                  let id = UUID(uuidString: raw) {
            self = .runChecklist(id)
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
        case .runChecklist(let id):
            [ChecklistSyncKey.runChecklist: id.uuidString]
        case .requestChecklists:
            [ChecklistSyncKey.requestChecklists: true]
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

    /// Asks the phone to create reminders for `checklist` and remembers it.
    /// Returns whether the transport accepted the request; `false` means nothing
    /// was sent and the UI must not report success.
    @discardableResult
    public func run(_ checklist: Checklist) -> Bool {
        guard transport.sendUserInfo(.runChecklist(checklist.id)) else { return false }
        pendingRunID = checklist.id
        return true
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