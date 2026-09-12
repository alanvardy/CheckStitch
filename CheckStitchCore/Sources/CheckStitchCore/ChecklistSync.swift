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
@MainActor
public protocol ChecklistSyncTransport: AnyObject {
    var onMessage: ((ChecklistSyncMessage) -> Void)? { get set }
    func activate()
    func sendContext(_ data: Data)
    func sendUserInfo(_ message: ChecklistSyncMessage)
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
    public func start() {
        transport.onMessage = { [weak self] in self?.receive($0) }
        transport.activate()
    }

    /// Asks the phone to create reminders for `checklist` and remembers it.
    public func run(_ checklist: Checklist) {
        pendingRunID = checklist.id
        transport.sendUserInfo(.runChecklist(checklist.id))
    }

    /// Cold launch: the phone re-pushes its context on receipt.
    public func requestRefresh() {
        transport.sendUserInfo(.requestChecklists)
    }

    private func receive(_ message: ChecklistSyncMessage) {
        switch message {
        case .context(let data):
            // Malformed or future-version payloads leave the previous list intact.
            if case .loaded(let decoded) = ChecklistCodec.classify(data) {
                checklists = decoded
            }
        case .runChecklist, .requestChecklists:
            break // phone-only directions
        }
    }

    private let transport: ChecklistSyncTransport
}