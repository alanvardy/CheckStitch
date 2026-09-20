import CheckStitchCore
import EventKit
import Foundation

/// Builds an item without saving anything anywhere.
func makeItem(_ title: String, description: String = "") -> ChecklistItem {
    ChecklistItem(title: title, description: description)
}

/// A `UserDefaults` isolated from `.standard`, wiped so appearance suites can
/// never read or write the real app preference.
func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "CheckStitchTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// A single `EKEventStore` kept alive for the test session. `EKReminder` holds
/// a weak reference to its store, so a deallocated store crashes (SIGTRAP) on
/// any property read — this global must outlive every reminder built from it.
@MainActor
let sharedTestEventStore = EKEventStore()

/// Test double for `ReminderCreating`: records created titles and can be told
/// to deny access or throw. `@MainActor` makes it implicitly `Sendable`.
@MainActor
final class SpyReminderCreator: ReminderCreating {
    var accessGranted = true
    var accessError: Error?
    var createError: Error?
    /// Invoked at the start of every `create(title:, dueDateComponents:)` —
    /// lets a suite observe view-model state while the work is in flight.
    var onCreate: (() -> Void)?
    /// Records every created reminder's title and date. `createdTitles` remains
    /// a computed shim so existing assertions (Creator + ViewModel suites) stay
    /// valid.
    private(set) var createdItems: [(title: String, dueDateComponents: DateComponents?)] = []
    var createdTitles: [String] { createdItems.map { $0.title } }

    func requestAccess() async throws -> Bool {
        if let accessError { throw accessError }
        return accessGranted
    }

    func create(title: String, dueDateComponents: DateComponents?) async throws {
        if let createError { throw createError }
        onCreate?()
        createdItems.append((title: title, dueDateComponents: dueDateComponents))
    }
}

/// Test double for `ReminderDestinationTargeting`: records created titles and
/// list ids, and can be told to deny access, expose a given set of lists, or
/// throw on create.
@MainActor
final class SpyReminderDestination: ReminderDestinationTargeting {
    var accessGranted = true
    var accessError: Error?
    var lists = ReminderListsSnapshot(options: [], defaultIdentifier: nil)
    var createError: Error?
    /// Awaited at the start of every `requestAccess()` — lets a suite hold a run
    /// in flight and observe the duplicate-tap guard.
    var onRequestAccess: (() async -> Void)?
    /// Status served by `accessStatus()`; defaults to `.fullAccess` so the 13
    /// existing ChecklistReminders suites stay green.
    var accessStatusValue: ReminderAccessStatus = .fullAccess
    /// Throw once `create` has already succeeded this many times (`0` = before any
    /// create). `nil` never throws here; `createError` still throws unconditionally.
    var createFailureCount: Int?
    private(set) var createdTitles: [String] = []
    private(set) var createdNotes: [String?] = []
    /// How many times `requestAccess()` has been entered — lets the gate tests
    /// assert a refused run performs no EventKit work.
    private(set) var requestAccessCount = 0
    /// The priority passed to each `create`. Index-aligned with `createdTitles`.
    private(set) var createdPriorities: [ChecklistItemPriority] = []
    private(set) var createdListIDs: [String] = []

    func requestAccess() async throws -> Bool {
        requestAccessCount += 1
        if let onRequestAccess { await onRequestAccess() }
        if let accessError { throw accessError }
        return accessGranted
    }

    func accessStatus() -> ReminderAccessStatus { accessStatusValue }

    func reminderLists() async throws -> ReminderListsSnapshot { lists }

    func create(title: String, notes: String?, priority: ChecklistItemPriority,
                in list: ReminderListOption, dueDateComponents: DateComponents?) async throws {
        if let createError { throw createError }
        if let createFailureCount, createdTitles.count >= createFailureCount { throw TestError.boom }
        createdTitles.append(title)
        createdNotes.append(notes)
        createdPriorities.append(priority)
        createdListIDs.append(list.id)
        createdDates.append(dueDateComponents)
    }

    /// The date (or `nil`) passed to each `create`. Index-aligned with
    /// `createdTitles` and `createdListIDs`.
    private(set) var createdDates: [DateComponents?] = []
}

/// Test double for `ChecklistSyncing`: in-memory bytes, recorded writes, and a
/// manually-fired external-change callback.
@MainActor
final class InMemoryChecklistSync: ChecklistSyncing {
    var stored: Data?
    var readError: Error?
    var writeError: Error?
    private(set) var written: [Data] = []
    private(set) var synchronizeCount = 0
    private(set) var readCount = 0
    private var onChange: (@MainActor () -> Void)?

    init(stored: Data? = nil) { self.stored = stored }

    func read() throws -> Data? {
        readCount += 1
        if let readError { throw readError }
        return stored
    }
    func write(_ data: Data) throws {
        if let writeError { throw writeError }
        written.append(data)
        stored = data
    }
    func synchronize() { synchronizeCount += 1 }
    @discardableResult
    func startObserving(_ onChange: @escaping @MainActor () -> Void) -> any ChecklistSyncObservation {
        self.onChange = onChange
        return InMemoryObservation()
    }
    func fireExternalChange() { onChange?() }
}

@MainActor
final class InMemoryObservation: ChecklistSyncObservation {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}

/// Deterministic error for failure-path assertions.
enum TestError: Error, Equatable {
    case boom
}

/// Records everything the store/coordinator sends and lets tests inject inbound
/// messages, standing in for `WCSession`.
@MainActor
final class FakeChecklistSyncTransport: ChecklistSyncTransport {
    var onMessage: ((ChecklistSyncMessage) -> Void)?
    var onActivated: (() -> Void)?
    private(set) var activateCount = 0
    private(set) var sentContexts: [Data] = []
    private(set) var sentMessages: [ChecklistSyncMessage] = []
    /// Set false to model a session that has not finished activating and so
    /// drops every send.
    var acceptsSends = true

    func activate() { activateCount += 1 }

    @discardableResult
    func sendContext(_ data: Data) -> Bool {
        sentContexts.append(data)
        return acceptsSends
    }

    @discardableResult
    func sendUserInfo(_ message: ChecklistSyncMessage) -> Bool {
        sentMessages.append(message)
        return acceptsSends
    }

    /// Clears only `sentMessages` (the `transferUserInfo` channel), so tests
    /// can ignore the cold-start language push. `sentContexts` is deliberately
    /// left intact for assertions that still expect the context pushes.
    func clearSentMessages() { sentMessages = [] }

    func deliver(_ message: ChecklistSyncMessage) { onMessage?(message) }

    /// Stands in for `WCSession` finishing activation.
    func completeActivation() { onActivated?() }
}

/// Spy for the coordinator's `createReminders` closure: records every checklist
/// the coordinator hands over and returns a configurable outcome.
@MainActor
final class SpyChecklistRunner {
    private(set) var created: [Checklist] = []
    /// Returned by `run`; set to drive the sad paths.
    var outcome: ReminderRunOutcome = .created(count: 1)
    func run(_ checklist: Checklist) async -> ReminderRunOutcome {
        created.append(checklist)
        return outcome
    }
}

/// Test double for `PurchaseProviding`: configurable offer/entitlement/purchase
/// results and a manually-fired observer callback. `@MainActor` matches the seam.
@MainActor
final class SpyPurchaseProvider: PurchaseProviding {
    var offer: PurchaseOffer? = PurchaseOffer(id: "license", displayName: "CheckStitch License",
                                              displayPrice: "$4.99")
    var entitlement = false
    var purchaseResult = true
    var purchaseError: Error?
    private(set) var purchaseCount = 0
    var restoreResult = true
    var restoreError: Error?
    private(set) var restoreCount = 0
    private var onChange: (@MainActor (Bool) -> Void)?

    func offer() async -> PurchaseOffer? { offer }
    func currentEntitlement() async -> Bool { entitlement }
    func purchase() async throws -> Bool {
        purchaseCount += 1
        if let purchaseError { throw purchaseError }
        return purchaseResult
    }
    func restore() async throws -> Bool {
        restoreCount += 1
        if let restoreError { throw restoreError }
        return restoreResult
    }
    func startObserving(_ onChange: @escaping @MainActor (Bool) -> Void) { self.onChange = onChange }
    func fireChange(_ unlocked: Bool) { onChange?(unlocked) }
}
