# Implementation Plan

## Overview

Persist an optional `destinationListIdentifier: String?` on `Checklist` (nil = system
default), make it first-class in the codec/store/merge, rework the production run path into
a pre-validating, outcome-returning orchestrator on an injectable EventKit seam, then
surface the selector on the detail screen and run failures as an alert on the list screen.

**Files touched**
- `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` (modify)
- `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift` (create)
- `CheckStitch/ChecklistStore.swift` (modify)
- `CheckStitch/ChecklistMerge.swift` (modify)
- `CheckStitch/ChecklistReminders.swift` (rewrite)
- `CheckStitch/EventKitReminderDestination.swift` (create)
- `CheckStitch/ChecklistDetailView.swift` (modify)
- `CheckStitch/ContentView.swift` (modify)
- `CheckStitchTests/ChecklistCodecTests.swift` (modify)
- `CheckStitchTests/ChecklistStoreTests.swift` (modify)
- `CheckStitchTests/ChecklistMergeTests.swift` (modify)
- `CheckStitchTests/WatchChecklistStoreTests.swift` (modify)
- `CheckStitchTests/TestFixtures.swift` (modify)
- `CheckStitchTests/ChecklistRemindersTests.swift` (create)
- `CheckStitchTests/EventKitReminderDestinationTests.swift` (create)

New files under `CheckStitch/` and `CheckStitchCore/Sources/CheckStitchCore/` need no
`project.pbxproj` edit (`PBXFileSystemSynchronizedRootGroup`).

**Deviations from `structure.md` (all additive, no phase reordering):**
1. `ReminderRunOutcome` gains an `errorMessage: String?` computed property (in the same
   Stage 4 core file, no extra file). This implements the structure's cross-cutting note —
   it makes Stage 7's outcome→message mapping unit-testable in Stage 4 instead of an
   untestable view-layer switch.
2. `ReminderListsSnapshot` gains a pure `resolve(_ identifier: String?) -> ReminderListOption?`
   helper so the pre-validation rule is one expression, shared by the orchestrator and tests.
3. The shared adapter is `EventKitReminderDestination.shared` (a `@MainActor static let`)
   rather than a private instance inside `ChecklistReminders` — Stage 6's `onAppear`
   enumeration needs the same instance.
4. The adapter's `create(title:in:)` re-guards the calendar lookup and throws if the list
   vanished between pre-validation and creation (TOCTOU), so a deleted list can never
   silently fall back to a nil calendar.

---

## Phase 1: Model + codec — persist the destination field

### Changes

#### 1. `Checklist` model + codec
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Three edits inside `public struct Checklist` (currently `Checklist.swift:52-86`). Insert the
new field after `items` in the memberwise init and the stored properties, add the coding key,
`decodeIfPresent` in `init(from:)`, and encode unconditionally. `currentVersion` stays `2`;
`migrated(at:)` is untouched (it copies the whole struct).

```swift
public init(id: UUID = UUID(), name: String = "New checklist", items: [ChecklistItem] = [], destinationListIdentifier: String? = nil, modifiedAt: Date = .distantPast, revision: Int = 0) {
    self.id = id
    self.name = name
    self.items = items
    self.destinationListIdentifier = destinationListIdentifier
    self.modifiedAt = modifiedAt
    self.revision = revision
}

public let id: UUID
public var name: String
public var items: [ChecklistItem]
/// `EKCalendar.calendarIdentifier` of the chosen Reminders list. `nil` means
/// "system default list", so legacy payloads keep today's behaviour.
public var destinationListIdentifier: String?
public var modifiedAt: Date
public var revision: Int

private enum CodingKeys: String, CodingKey { case id, name, items, destinationListIdentifier, modifiedAt, revision }

public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    items = try container.decodeIfPresent([ChecklistItem].self, forKey: .items) ?? []
    destinationListIdentifier = try container.decodeIfPresent(String.self, forKey: .destinationListIdentifier)
    modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
}

public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(items, forKey: .items)
    try container.encode(destinationListIdentifier, forKey: .destinationListIdentifier)
    try container.encode(modifiedAt, forKey: .modifiedAt)
    try container.encode(revision, forKey: .revision)
}
```

No `currentVersion` bump and no storage-key migration: `?? nil` on decode keeps every stored
v2 payload loading, and unconditional encode keeps older peers syncing (design decision 4).

#### 2. Codec tests
**File**: `CheckStitchTests/ChecklistCodecTests.swift`
**Action**: modify

Append two XCTest cases to the existing `@MainActor final class ChecklistCodecTests`.

```swift
/// A v2 payload written before the destination field existed: decodes as nil
/// rather than throwing, so every checklist already stored keeps working.
func testDecodesV2PayloadWithoutDestinationAsNil() {
    let id = UUID().uuidString
    let data = Data(#"{"version":2,"deviceID":"device-a","checklists":[{"id":"\#(id)","name":"Groceries","items":[],"modifiedAt":0,"revision":1}]}"#.utf8)

    let decoded = ChecklistCodec.decode(data)

    XCTAssertEqual(decoded.count, 1)
    XCTAssertNil(decoded.first?.destinationListIdentifier)
}

func testDestinationSurvivesEnvelopeRoundTrip() throws {
    let checklist = Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")],
                              destinationListIdentifier: "list-a")
    let envelope = ChecklistEnvelope(deviceID: "device-a", checklists: [checklist])

    let data = try ChecklistCodec.encode(envelope)

    XCTAssertEqual(ChecklistCodec.classify(data), .loaded(envelope))
    XCTAssertEqual(ChecklistCodec.decode(data).first?.destinationListIdentifier, "list-a")
}
```

#### 3. Watch store field-preservation assertion
**File**: `CheckStitchTests/WatchChecklistStoreTests.swift`
**Action**: modify

The watch store shares the core model and codec, so this is an assertion only — no
watch-side source change.

```swift
@Test
func destinationFieldSurvivesTheWatchTransport() throws {
    let transport = FakeChecklistSyncTransport()
    let store = WatchChecklistStore(transport: transport)
    store.start()

    let expected = [Checklist(name: "Groceries", destinationListIdentifier: "list-a")]
    transport.deliver(.context(try ChecklistCodec.encode(ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: "", checklists: expected))))

    #expect(store.checklists.first?.destinationListIdentifier == "list-a")
}
```

### Verification
#### Automated
- [x] `make test-unit` passes (codec, watch-store, and all pre-existing suites green)
#### Manual
- [ ] `git grep -n destinationListIdentifier CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` shows exactly the init/property/key/decode/encode sites above

---

## Phase 2: Store mutation — `setDestination`

### Changes

#### 1. `SetDestinationOutcome` + `setDestination`
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

Add the outcome enum next to `RenameOutcome` (`ChecklistStore.swift:10-14`) and the setter
next to `rename(id:to:)` (`ChecklistStore.swift:120-130`), so it inherits the same
revision/`modifiedAt`/save bookkeeping. `scheduleSave()` is the coalescing path; with the
test-store's `textEditDelay: nil` it saves synchronously, and `flushPendingSave()` already
covers screen-exit/scene-phase.

```swift
/// Whether a `setDestination(_:for:)` call was applied or aimed at an id that
/// no longer exists (deleted while its edit screen was visible).
enum SetDestinationOutcome: Equatable {
    case updated
    case notFound
}
```

```swift
/// Points a checklist at a Reminders list (`nil` = system default) and reports
/// whether it applied. Follows `rename`: bump revision + `modifiedAt`, then
/// persist through the coalescing path.
@discardableResult
func setDestination(_ identifier: String?, for id: UUID) -> SetDestinationOutcome {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return .notFound }
    checklists[index].destinationListIdentifier = identifier
    checklists[index].revision += 1
    checklists[index].modifiedAt = now()
    scheduleSave()
    return .updated
}
```

No new load/save path: `envelope` already flows through the codec from Phase 1.

#### 2. Store tests
**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify

Append three XCTest cases to `ChecklistStoreTests` (uses the existing private `Clock` and
`makeStore`/`makeDefaults` helpers).

```swift
func testSetDestinationUpdatesRevisionAndPersists() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
    let clock = Clock()
    let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
    let created = store.create()
    clock.now = Date(timeIntervalSince1970: 5)

    XCTAssertEqual(store.setDestination("list-a", for: created.id), .updated)

    let reloaded = makeStore(defaults: suite.defaults)
    XCTAssertEqual(reloaded.checklist(id: created.id)?.destinationListIdentifier, "list-a")
    XCTAssertEqual(reloaded.checklist(id: created.id)?.revision, 2)
    XCTAssertEqual(reloaded.checklist(id: created.id)?.modifiedAt, clock.now)
}

func testSetDestinationClearsToDefaultWithNil() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
    let store = makeStore(defaults: suite.defaults)
    let created = store.create()
    store.setDestination("list-a", for: created.id)

    XCTAssertEqual(store.setDestination(nil, for: created.id), .updated)

    XCTAssertNil(makeStore(defaults: suite.defaults).checklist(id: created.id)?.destinationListIdentifier)
}

/// Sad path: an id deleted while its edit screen was on the stack changes
/// nothing and reports not-found.
func testSetDestinationForUnknownChecklistReturnsNotFound() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
    let store = makeStore(defaults: suite.defaults)

    XCTAssertEqual(store.setDestination("list-a", for: UUID()), .notFound)
    XCTAssertTrue(store.checklists.isEmpty)
}
```

### Verification
#### Automated
- [x] `make test-unit` passes
#### Manual
- [ ] None (covered by reload assertion in `testSetDestinationUpdatesRevisionAndPersists`)

---

## Phase 3: Merge — destination follows the checklist winner

### Changes

#### 1. Checklist-winner overwrite set
**File**: `CheckStitch/ChecklistMerge.swift`
**Action**: modify

In `mergedChecklists`, inside the `if wins(...)` branch (`ChecklistMerge.swift:76-82`), copy
the destination alongside `name`/`revision`/`modifiedAt`. Tombstone and item-level rules are
untouched.

```swift
if wins(revision: remoteChecklist.revision, date: remoteChecklist.modifiedAt,
        device: remoteDevice,
        overRevision: localChecklist.revision, overDate: localChecklist.modifiedAt,
        overDevice: localDevice) {
    merged.name = remoteChecklist.name
    merged.destinationListIdentifier = remoteChecklist.destinationListIdentifier
    merged.revision = remoteChecklist.revision
    merged.modifiedAt = remoteChecklist.modifiedAt
}
```

#### 2. Merge tests
**File**: `CheckStitchTests/ChecklistMergeTests.swift`
**Action**: modify

The file-scope `checklist(...)` helper (`ChecklistMergeTests.swift:165-168`) gains a
defaulted `destination` parameter, then two cases are appended. Existing call sites keep
working via the default.

```swift
@MainActor
func checklist(id: UUID, name: String, revision: Int, modifiedAt: Date = .distantPast, items: [ChecklistItem] = [], destination: String? = nil) -> Checklist {
    Checklist(id: id, name: name, items: items, destinationListIdentifier: destination, modifiedAt: modifiedAt, revision: revision)
}
```

```swift
@Test
func winnerDestinationOverwritesLoser() {
    let id = UUID()
    let newer = checklist(id: id, name: "newer", revision: 2, modifiedAt: Date(timeIntervalSince1970: 2), destination: "list-b")
    let older = checklist(id: id, name: "older", revision: 1, modifiedAt: Date(timeIntervalSince1970: 1), destination: "list-a")

    let merged = ChecklistMerge.merge(
        local: envelope(device: "device-a", checklists: [older]),
        remote: envelope(device: "device-b", checklists: [newer])
    )

    #expect(merged.checklists.first?.destinationListIdentifier == "list-b", "the newest editor controls the destination")
}

@Test
func loserDestinationIsPreservedWhenNonWinning() {
    let id = UUID()
    let newer = checklist(id: id, name: "newer", revision: 2, modifiedAt: Date(timeIntervalSince1970: 2), destination: "list-b")
    let older = checklist(id: id, name: "older", revision: 1, modifiedAt: Date(timeIntervalSince1970: 1), destination: "list-a")

    let merged = ChecklistMerge.merge(
        local: envelope(device: "device-a", checklists: [newer]),
        remote: envelope(device: "device-b", checklists: [older])
    )

    #expect(merged.checklists.first?.destinationListIdentifier == "list-b", "an older revision must not leak its destination in")
}
```

### Verification
#### Automated
- [x] `make test-unit` passes
#### Manual
- [ ] None (both directions asserted by argument-order-swapped cases)

---

## Phase 4: Run orchestration seam — pre-validate, then create-or-fail

### Changes

#### 1. Core seam types
**File**: `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift`
**Action**: create

Pure value types + protocol; no `EventKit` import, so it also compiles into the watchOS
`CheckStitchCore` build. The protocol is the seam the Phase 5 adapter implements and
`SpyReminderDestination` fakes.

```swift
import Foundation

/// One selectable Reminders list. `id` is `EKCalendar.calendarIdentifier` — stable
/// across list renames and app restarts, unlike the title.
public struct ReminderListOption: Equatable, Identifiable, Sendable {
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    public let id: String
    public let title: String
}

/// The Reminders lists visible at one instant, plus which one the system would
/// use by default (nil when there is no default list — treated as a failure,
/// never a silent skip).
public struct ReminderListsSnapshot: Equatable, Sendable {
    public init(options: [ReminderListOption], defaultIdentifier: String?) {
        self.options = options
        self.defaultIdentifier = defaultIdentifier
    }

    public let options: [ReminderListOption]
    public let defaultIdentifier: String?

    /// Resolves a stored destination to a selectable list. `nil` means "system
    /// default". Returns nil when the requested list (or the default) is gone,
    /// which the orchestrator turns into `.destinationMissing` before creating
    /// anything.
    public func resolve(_ identifier: String?) -> ReminderListOption? {
        if let identifier {
            return options.first { $0.id == identifier }
        }
        guard let defaultIdentifier else { return nil }
        return options.first { $0.id == defaultIdentifier }
    }
}

/// Outcome of a checklist run. `.destinationMissing` is distinct from `.failed`
/// so the UI can explain the missing-list case specifically.
public enum ReminderRunOutcome: Equatable, Sendable {
    case created(count: Int)
    case destinationMissing
    case permissionDenied
    case failed(String)

    /// User-facing text for every non-success outcome, `nil` on success. Kept
    /// here (not in the view) so the mapping is unit-testable.
    public var errorMessage: String? {
        switch self {
        case .created: return nil
        case .destinationMissing: return "That list no longer exists; no reminders were created."
        case .permissionDenied: return "CheckStitch doesn't have permission to access Reminders; no reminders were created."
        case .failed(let message): return message
        }
    }
}

/// Seam over the EventKit surface the run path needs: permission, list
/// enumeration, and creating a reminder in a chosen list. Injected so tests can
/// drive denial/missing-list/save-failure without touching EventKit.
@MainActor
public protocol ReminderDestinationTargeting {
    func requestAccess() async throws -> Bool
    func reminderLists() async throws -> ReminderListsSnapshot
    func create(title: String, in list: ReminderListOption) async throws
}
```

#### 2. Orchestrator rewrite
**File**: `CheckStitch/ChecklistReminders.swift`
**Action**: rewrite

Replaces the `Void`/log-only version (`ChecklistReminders.swift:10-28`). Validation happens
**before** the loop, so a missing destination creates zero reminders. `logger` is kept for
the thrown-error case.

```swift
import CheckStitchCore
import EventKit
import os

enum ChecklistReminders {
    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistReminders")

    /// Production entry point: requests access, resolves the checklist's
    /// destination (or the system default) BEFORE creating anything, then
    /// creates one reminder per non-blank item. Returns an outcome the caller
    /// can surface — permission denial and missing lists are no longer silent.
    static func create(from checklist: Checklist) async -> ReminderRunOutcome {
        await create(from: checklist, targeting: EventKitReminderDestination.shared)
    }

    static func create(from checklist: Checklist, targeting: ReminderDestinationTargeting) async -> ReminderRunOutcome {
        do {
            guard try await targeting.requestAccess() else { return .permissionDenied }
            let snapshot = try await targeting.reminderLists()
            guard let destination = snapshot.resolve(checklist.destinationListIdentifier) else {
                // All-or-nothing: validate existence before the first create.
                return .destinationMissing
            }
            var created = 0
            for item in checklist.items where !item.isBlank {
                try await targeting.create(title: item.title, in: destination)
                created += 1
            }
            return .created(count: created)
        } catch {
            logger.error("Failed to create checklist reminders: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }
}
```

Note `.isBlank` is `ChecklistItem`'s existing trimmed-emptiness check — same semantics as the
current inline `trimmingCharacters` guard.

#### 3. Spy fixture
**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify

Append below `SpyReminderCreator` (`TestFixtures.swift:28-49`), following its shape.
`@MainActor` is what makes the class satisfy the `@MainActor` protocol and implicitly
`Sendable`.

```swift
/// Test double for `ReminderDestinationTargeting`: records created titles and
/// list ids, and can be told to deny access, expose a given set of lists, or
/// throw on create.
@MainActor
final class SpyReminderDestination: ReminderDestinationTargeting {
    var accessGranted = true
    var accessError: Error?
    var lists = ReminderListsSnapshot(options: [], defaultIdentifier: nil)
    var createError: Error?
    private(set) var createdTitles: [String] = []
    private(set) var createdListIDs: [String] = []

    func requestAccess() async throws -> Bool {
        if let accessError { throw accessError }
        return accessGranted
    }

    func reminderLists() async throws -> ReminderListsSnapshot { lists }

    func create(title: String, in list: ReminderListOption) async throws {
        if let createError { throw createError }
        createdTitles.append(title)
        createdListIDs.append(list.id)
    }
}
```

#### 4. Orchestrator tests
**File**: `CheckStitchTests/ChecklistRemindersTests.swift`
**Action**: create

Swift Testing, `@MainActor` suite (the protocol and spy are actor-isolated). `makeItem`
comes from `TestFixtures.swift:6`.

```swift
@testable import CheckStitch
import CheckStitchCore
import Foundation
import Testing

@MainActor
struct ChecklistRemindersTests {
    private func snapshot(defaultIdentifier: String? = "list-default") -> ReminderListsSnapshot {
        ReminderListsSnapshot(
            options: [
                ReminderListOption(id: "list-default", title: "Reminders"),
                ReminderListOption(id: "list-a", title: "Groceries"),
            ],
            defaultIdentifier: defaultIdentifier)
    }

    @Test
    func createsInChosenList() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk"), makeItem("Eggs")],
                                  destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .created(count: 2))
        #expect(spy.createdTitles == ["Milk", "Eggs"])
        #expect(spy.createdListIDs == ["list-a", "list-a"])
    }

    @Test
    func nilDestinationUsesDefaultList() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot(defaultIdentifier: "list-default")
        let checklist = Checklist(items: [makeItem("Milk")])

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .created(count: 1))
        #expect(spy.createdListIDs == ["list-default"])
    }

    /// Sad path: a destination that no longer exists must create ZERO reminders.
    @Test
    func missingDestinationCreatesNothing() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk"), makeItem("Eggs")],
                                  destinationListIdentifier: "list-deleted")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .destinationMissing)
        #expect(spy.createdTitles.isEmpty)
        #expect(spy.createdListIDs.isEmpty)
    }

    /// Sad path: no default list at all is a failure, not a silent skip.
    @Test
    func missingDefaultCreatesNothing() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot(defaultIdentifier: nil)
        let checklist = Checklist(items: [makeItem("Milk")])

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .destinationMissing)
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func permissionDeniedReturnsDenied() async {
        let spy = SpyReminderDestination()
        spy.accessGranted = false
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .permissionDenied)
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func blankTitlesAreSkipped() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk"), makeItem("   "), makeItem("")],
                                  destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .created(count: 1))
        #expect(spy.createdTitles == ["Milk"])
    }

    @Test
    func saveFailureReturnsFailed() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        spy.createError = TestError.boom
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        guard case .failed = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
    }

    @Test
    func errorMessagesDescribeEachFailure() {
        #expect(ReminderRunOutcome.created(count: 1).errorMessage == nil)
        #expect(ReminderRunOutcome.destinationMissing.errorMessage == "That list no longer exists; no reminders were created.")
        #expect(ReminderRunOutcome.permissionDenied.errorMessage != nil)
        #expect(ReminderRunOutcome.failed("boom").errorMessage == "boom")
    }
}
```

### Verification
#### Automated
- [x] `make test-unit` passes — all seven run outcomes plus the message mapping covered
#### Manual
- [ ] `git grep -n "createdListIDs" CheckStitchTests/ChecklistRemindersTests.swift` shows the zero-create assertion in `missingDestinationCreatesNothing`

---

## Phase 5: Real EventKit adapter

### Changes

#### 1. `EventKitReminderDestination`
**File**: `CheckStitch/EventKitReminderDestination.swift`
**Action**: create

One long-lived injected `EKEventStore` (never per call — `EKReminder` holds a weak store ref
and a deallocated store SIGTRAPs). Mirrors `EventKitReminderCreator`'s `#if !os(watchOS)`
around `save`.

```swift
import CheckStitchCore
import EventKit

/// Real adapter over one long-lived `EKEventStore`: enumerates Reminders lists
/// and creates reminders in a chosen one. `shared` is the production instance —
/// it must outlive every reminder it creates (`EKReminder` holds a weak
/// reference to its store).
@MainActor
final class EventKitReminderDestination: ReminderDestinationTargeting {
    static let shared = EventKitReminderDestination()

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToReminders()
    }

    func reminderLists() async throws -> ReminderListsSnapshot {
        ReminderListsSnapshot(
            options: eventStore.calendars(for: .reminder).compactMap { calendar in
                let identifier = calendar.calendarIdentifier
                guard !identifier.isEmpty else { return nil }
                return ReminderListOption(id: identifier, title: calendar.title)
            },
            defaultIdentifier: eventStore.defaultCalendarForNewReminders()?.calendarIdentifier)
    }

    func create(title: String, in list: ReminderListOption) async throws {
        // Re-resolve by identifier: a list deleted between pre-validation and
        // creation must throw rather than silently fall back to a nil calendar.
        guard let calendar = eventStore.calendars(for: .reminder)
            .first(where: { $0.calendarIdentifier == list.id })
        else { throw ReminderDestinationError.listMissing }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = calendar
        // watchOS EventKit is read-only; the watch never reaches this adapter.
        #if !os(watchOS)
            try eventStore.save(reminder, commit: true)
        #endif
    }

    private let eventStore: EKEventStore
}

enum ReminderDestinationError: LocalizedError {
    case listMissing

    var errorDescription: String? { "That list no longer exists; no reminders were created." }
}
```

#### 2. Construction canary
**File**: `CheckStitchTests/EventKitReminderDestinationTests.swift`
**Action**: create

Construction only — no EventKit API is called, matching
`EventKitReminderCreatorTests.swift:13-16`. The identifier-populated/stability check is the
manual device step below (design Open Risk 1).

```swift
import EventKit
@testable import CheckStitch
import Testing

@MainActor
struct EventKitReminderDestinationTests {
    /// Crash-canary for the real adapter: it must be constructible around an
    /// injected `EKEventStore` without constructing one of its own. No EventKit
    /// API is called; behavior is exercised through `SpyReminderDestination`.
    @Test
    func destinationAcceptsInjectedStore() {
        _ = EventKitReminderDestination(eventStore: sharedTestEventStore)
    }
}
```

No `ChecklistReminders` change is needed beyond Phase 4: the no-argument `create(from:)`
already defaults to `EventKitReminderDestination.shared`.

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `make build-mac` passes (unsigned macOS leg; the adapter compiles without provisioning)
#### Manual
- [ ] `make run` → open a checklist → run one with an explicit list → confirm in Reminders.app the reminder landed in that list (validates `calendarIdentifier` stability on this toolchain)
- [ ] In Reminders.app, rename that list, then run again → the reminder still lands in the renamed list (identifier, not title, is the identity)

---

## Phase 6: Detail-screen destination selector

### Changes

#### 1. Destination selector section
**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

Add state next to the existing `@State` block (`ChecklistDetailView.swift:11-18`), a new
`Section("Destination list")` after `Section("Checklist name")` (`:23-26`), an on-appear
load, and one binding helper. The `Picker` + `.tag` row precedent is
`SettingsView.swift:17`.

```swift
@State private var reminderLists: [ReminderListOption] = []
/// True when Reminders access was denied, threw, or returned no lists: the
/// picker degrades to the default-only row with an explanatory note.
@State private var destinationUnavailable = false
```

```swift
Section("Destination list") {
    Picker("List", selection: destinationBinding(checklistID: checklistID)) {
        Text("Default (Inbox)").tag(String?.none)
        ForEach(reminderLists) { list in
            Text(list.title).tag(String?.some(list.id))
        }
    }
    .accessibilityIdentifier("destinationListPicker")

    if destinationUnavailable {
        Text("Reminders access is unavailable, so reminders go to the default list.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
```

```swift
.onAppear {
    guard !didLoadDraft else { return }
    draftName = checklist.name
    didLoadDraft = true
    Task { await loadReminderLists() }
}
```

```swift
/// Enumerates the Reminders lists for the picker. Denied access, a thrown
/// error, or an empty enumeration leaves the default-only row plus the note.
private func loadReminderLists() async {
    let destination = EventKitReminderDestination.shared
    do {
        guard try await destination.requestAccess() else {
            destinationUnavailable = true
            return
        }
        let snapshot = try await destination.reminderLists()
        reminderLists = snapshot.options
        destinationUnavailable = snapshot.options.isEmpty
    } catch {
        destinationUnavailable = true
    }
}

/// Per-selection write through the store (Phase 2). `nil` is the "Default
/// (Inbox)" row. `.notFound` (deleted while this screen was open) is ignored,
/// matching `commitDraftIfChanged`.
private func destinationBinding(checklistID: UUID) -> Binding<String?> {
    Binding(
        get: { store.checklist(id: checklistID)?.destinationListIdentifier },
        set: { store.setDestination($0, for: checklistID) }
    )
}
```

The buffered-name draft, the rename-conflict alert, and the item bindings are untouched.
`onDisappear` already calls `store.flushPendingSave()` (`ChecklistDetailView.swift:78`), so a
selection made just before leaving is persisted.

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `make test-ui` passes (existing smoke unchanged; it never opens the detail screen)
#### Manual
- [ ] `make run` → edit a checklist → pick a non-default list → Done → relaunch → the picker still shows that list and it is checked in Reminders.app
- [ ] `make run` → pick "Default (Inbox)" → run → the reminder lands in the default list
- [ ] Deny Reminders access in Settings → reopen the edit screen → only "Default (Inbox)" plus the explanatory note is shown

---

## Phase 7: Run-failure surfacing on the list screen

### Changes

#### 1. Outcome switch + alert
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Add `@State private var runErrorMessage: String?` to the state block
(`ContentView.swift:17-22`), replace the body of `createReminders(for:)`
(`ContentView.swift:303-319`) so success is only marked on `.created`, and attach the alert
to the outer `ZStack` (after the `.onChange(of: backgroundPinned)` block, `:122-124`), copying
the rename-conflict `.alert` idiom (`ChecklistDetailView.swift:80-85`).

```swift
@State private var runErrorMessage: String?
```

```swift
private func createReminders(for id: UUID) {
    // Mark the checklist as creating before spawning the task so a second
    // tap can't enqueue duplicate reminders while the first task starts.
    guard !creating.contains(id), let checklist = store.checklist(id: id) else { return }
    creating.insert(id)
    Task {
        // Hold the spinner for at least a second so saving quickly
        // doesn't flash the progress feedback past the user.
        async let minimumSpinner: Void = Task.sleep(for: .seconds(1))
        let outcome = await ChecklistReminders.create(from: checklist)
        try? await minimumSpinner
        creating.remove(id)
        switch outcome {
        case .created:
            created.insert(id)
            try? await Task.sleep(for: .seconds(1))
            created.remove(id)
        case .destinationMissing, .permissionDenied, .failed:
            // Never flash success: nothing was created (or the run failed).
            runErrorMessage = outcome.errorMessage
        }
    }
}
```

```swift
.alert("Couldn't create reminders", isPresented: Binding(
    get: { runErrorMessage != nil },
    set: { if !$0 { runErrorMessage = nil } })
) {
    Button("OK", role: .cancel) {}
        .accessibilityIdentifier("runErrorMessageButton")
} message: {
    Text(runErrorMessage ?? "")
}
```

This is the whole outcome→message mapping: `ReminderRunOutcome.errorMessage` (Phase 4), already
unit-tested in `errorMessagesDescribeEachFailure`.

### Verification
#### Automated
- [ ] `make test-unit` passes
- [ ] `make test-ui` passes
#### Manual
- [ ] `make run` → pick a list for a checklist → delete that list in Reminders.app → run the checklist → the alert appears and Reminders.app shows zero new reminders (no green checkmark)
- [ ] Deny Reminders access → run a checklist → the permission alert appears, no green checkmark
- [ ] Happy path: valid list → run → green checkmark still flashes as before

---

## Full-gate and residual risks

- **Gate**: `./scripts/test.sh` must print `gate: ok` before the work is declared done
  (`make build` → simulator pre-boot → `make test` → `make build-mac` → `make watch-build` →
  `scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`).
- **Residual risk (accepted, from design)**: `EKCalendar.calendarIdentifier` stability is
  assumed from the SDK; the Phase 5 manual checks are the confirmation. If it proves
  unreliable, the fallback is title-based identity — not implemented here.
- **Residual risk (accepted)**: merge winner-takes-all can point a checklist at a list that
  does not exist on another device; that device's next run returns `.destinationMissing` and
  surfaces the alert.
- **No unresolved questions**: the structure outline expanded without contradictions; the
  only additions are the small testability helpers noted under Deviations.