# Implementation Plan

## Overview

Tapping **Create reminders** on a real paired Apple Watch must put reminders in
the iPhone's Reminders app, and the watch must say `Created` only when the phone
confirms it — otherwise it shows a short reason and lets the user retry. Work
lands in five vertical phases: instrument every gate on both targets, read the
one-tap log chain to locate the real drop point, then land the silent-drop
family fix (phone→watch `.runResult` channel, honest watch feedback,
unknown-id recovery, retain-and-resend) through the existing `ChecklistSyncing`
seam.

**Deviation note (structure → plan):** Phase 4 changes
`WatchChecklistStore.run(_:)` from `-> UUID?` to `-> UUID` (a run is only
"not started" before retention exists; once a rejected send is retained, every
tap starts a run). Structure did not name the return type, so this is an
implementation detail made explicit here. Phase 4 also implements the
coordinator's dedup memory as `completedRuns: [UUID: RunResult]` rather than
`completedRunIDs: Set<UUID>`, because the duplicate path must **re-ack with the
original result** and a bare set cannot do that. `CheckStitch/MyApp.swift` is
listed in Phase 1 only as a verification target: the `createReminders` closure
already returns the outcome implicitly, so no edit is required there
(diagnostic logging of the outcome lives in the coordinator, which must receive
the value anyway).

---

## Phase 1: Walking skeleton — an instrumented tap observed end to end (root cause located)

### Changes

#### 1. New diagnostics seam (both targets log through it)
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncDiagnostics.swift`
**Action**: create

```swift
import Foundation
import os

/// The gates a watch-initiated run passes through, on both devices. One
/// correlated `[<gate>]` record per gate makes a single tap's chain greppable
/// in `Console.app` / `idevicessyslog` (`[watchSend] [phoneReceive]
/// [phoneHandle] [snapshotLookup] [createOutcome]`).
public enum SyncGate: String, Sendable, CaseIterable {
    case watchSend
    case watchActivation
    case phoneReceive
    case phoneHandle
    case snapshotLookup
    case createOutcome
}

/// Single logging surface so the phone and the watch agree on subsystem,
/// category and message shape. `notice` level so records persist to disk and
/// are not filtered out of `Console.app`/`devicectl` by default.
///
/// `CheckStitchCore` builds without `SWIFT_DEFAULT_ACTOR_ISOLATION`, so this is
/// nonisolated and callable from the `nonisolated` `WCSessionDelegate` methods.
public enum ChecklistSyncDiagnostics {
    /// The literal matches the phone app's existing `Logger` subsystem so a
    /// single predicate catches both devices' records.
    private static let subsystem = "app.alanvardy.CheckStitch"
    private static let logger = Logger(subsystem: subsystem, category: "ChecklistSync")

    public static func log(_ gate: SyncGate, _ fields: [String: String] = [:]) {
        let detail = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        logger.notice("[\(gate.rawValue, privacy: .public)] \(detail, privacy: .public)")
    }
}
```

#### 2. Message carries a per-run id
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify

```swift
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
```

`init?(userInfo:)` decodes `runChecklist` + `runChecklistRunID` (both required;
missing/invalid `runID` → `nil`), and `userInfo` encodes both. Add to
`ChecklistSyncKey`:

```swift
    public static let runChecklistRunID = "runChecklistRunID"
```

```swift
        } else if let raw = userInfo[ChecklistSyncKey.runChecklist] as? String,
                  let id = UUID(uuidString: raw),
                  let runRaw = userInfo[ChecklistSyncKey.runChecklistRunID] as? String,
                  let runID = UUID(uuidString: runRaw) {
            self = .runChecklist(id: id, runID: runID)
        } else if userInfo[ChecklistSyncKey.requestChecklists] as? Bool == true {
```

```swift
        case .runChecklist(let id, let runID):
            [ChecklistSyncKey.runChecklist: id.uuidString,
             ChecklistSyncKey.runChecklistRunID: runID.uuidString]
```

Add a diagnostic name used by every log line:

```swift
    /// Compact description for the `ChecklistSyncDiagnostics` records.
    public var diagnosticName: String {
        switch self {
        case .context(let data): "context(\(data.count))b"
        case .runChecklist(let id, let runID): "runChecklist(id:\(id.uuidString),run:\(runID.uuidString))"
        case .requestChecklists: "requestChecklists"
        }
    }
```

#### 3. Watch store sends a correlated run
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift` (`WatchChecklistStore`)
**Action**: modify

```swift
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
```

`pendingRunID` now carries the **run** id (previously the checklist id); it is
still write-only in this phase.

#### 4. Coordinator logs every guard and threads the outcome out
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift`
**Action**: modify

```swift
    public init(
        transport: ChecklistSyncTransport,
        snapshot: @escaping () -> [Checklist],
        createReminders: @escaping (Checklist) async -> ReminderRunOutcome
    ) {
```

```swift
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
                return
            }
            ChecklistSyncDiagnostics.log(.snapshotLookup, [
                "run": runID.uuidString, "checklist": id.uuidString, "result": "hit",
            ])
            // Chain runs so overlapping requests never hold two EventKit stores
            // open at once (EKCADErrorDomain 1021).
            let previous = pendingRun
            pendingRun = Task { [createReminders] in
                await previous?.value
                let outcome = await createReminders(checklist)
                ChecklistSyncDiagnostics.log(.createOutcome, [
                    "run": runID.uuidString,
                    "checklist": id.uuidString,
                    "outcome": String(describing: outcome),
                ])
            }
        case .context:
            break // watch-only direction
        }
    }

    private let transport: ChecklistSyncTransport
    private let snapshot: () -> [Checklist]
    private let createReminders: (Checklist) async -> ReminderRunOutcome
```

`pendingRun` stays `Task<Void, Never>` — the outcome is consumed inside the
chained body, which keeps the serialization exactly as it is today.

#### 5. Watch adapter logs activation state and send gates
**File**: `CheckStitchWatch/WatchSyncAdapter.swift`
**Action**: modify

```swift
    func activate() {
        guard WCSession.isSupported() else {
            ChecklistSyncDiagnostics.log(.watchActivation, ["supported": "false"])
            return
        }
        session.delegate = self
        session.activate()
    }

    @discardableResult
    func sendUserInfo(_ message: ChecklistSyncMessage) -> Bool {
        let state = session.activationState
        let accepted = state == .activated
        ChecklistSyncDiagnostics.log(.watchSend, [
            "message": message.diagnosticName,
            "activationState": String(describing: state),
        ])
        guard accepted else { return false }
        session.transferUserInfo(message.userInfo)
        return true
    }
```

```swift
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        ChecklistSyncDiagnostics.log(.watchActivation, [
            "state": String(describing: activationState),
            "error": error?.localizedDescription ?? "none",
        ])
        guard activationState == .activated else { return }
```

#### 6. Phone adapter logs every inbound gate
**File**: `CheckStitch/PhoneSyncAdapter.swift`
**Action**: modify

```swift
    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let message = ChecklistSyncMessage(userInfo: userInfo) else {
            ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "userInfo", "decode": "rejected"])
            return
        }
        ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "userInfo", "message": message.diagnosticName])
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let message = ChecklistSyncMessage(userInfo: applicationContext) else {
            ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "context", "decode": "rejected"])
            return
        }
        ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "context", "message": message.diagnosticName])
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }
```

`PhoneSyncAdapter` must `import CheckStitchCore` (it already does).

#### 7. Wiring check (no code change)
**File**: `CheckStitch/MyApp.swift`
**Action**: verify only

`createReminders: { await ChecklistReminders.create(from: $0) }` is a
single-expression closure, so it already satisfies
`(Checklist) async -> ReminderRunOutcome` — the outcome is no longer discarded
because the coordinator now awaits and logs it. **No edit.**

#### 8. Test fixtures
**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify

```swift
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
```

#### 9. Tests
**Files**: `CheckStitchTests/WatchChecklistStoreTests.swift`,
`CheckStitchTests/ChecklistSyncCoordinatorTests.swift`,
`CheckStitchTests/ChecklistSyncMessageTests.swift`
**Action**: modify

`ChecklistSyncMessageTests` — update every construction to the new case shape and
add the missing-`runID` rejection:

```swift
    @Test
    func runChecklistRoundTripsThroughUserInfo() {
        let id = UUID()
        let runID = UUID()
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.runChecklist(id: id, runID: runID).userInfo)
            == .runChecklist(id: id, runID: runID))
    }

    @Test
    func runChecklistWithoutARunIDIsRejected() {
        #expect(ChecklistSyncMessage(userInfo: [ChecklistSyncKey.runChecklist: UUID().uuidString]) == nil)
    }
```

`WatchChecklistStoreTests` — replace `runSendsExactlyOneRunRequestAndRecordsIt`
and `rejectedRunIsNotRecordedAsPending`:

```swift
    @Test
    func runSendsOneRunRequestCarryingAFreshRunID() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")

        let runID = try #require(store.run(checklist))

        #expect(transport.sentMessages == [.runChecklist(id: checklist.id, runID: runID)])
        #expect(store.pendingRunID == runID)
    }

    @Test
    func aRejectedSendStartsNoRun() {
        let transport = FakeChecklistSyncTransport()
        transport.acceptsSends = false
        let store = WatchChecklistStore(transport: transport)

        #expect(store.run(Checklist(name: "Groceries")) == nil)
        #expect(store.pendingRunID == nil)
    }
```

`ChecklistSyncCoordinatorTests` — `makeCoordinator` keeps its shape (the closure
now returns the spy's outcome), `runRequestForKnownIDCreatesRemindersOnce`
switches to the labelled case, and the sad paths assert the run still reaches
`createReminders` (the outcome itself becomes observable in Phase 2):

```swift
        transport.deliver(.runChecklist(id: checklist.id, runID: UUID()))
```

```swift
    @Test
    func runRequestForUnknownIDStillCreatesNothing() async {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let coordinator = makeCoordinator(transport: transport, checklists: [], runner: runner)
        coordinator.start()

        transport.deliver(.runChecklist(id: UUID(), runID: UUID()))
        for _ in 0..<50 where runner.created.isEmpty { await Task.yield() }

        #expect(runner.created.isEmpty)
    }
```

Sad-path plumbing (the outcome now flows out of the closure instead of being
discarded):

```swift
    @Test(arguments: [ReminderRunOutcome.permissionDenied, .failed("boom"), .destinationMissing])
    func aSadOutcomeStillReachesTheRunClosure(outcome: ReminderRunOutcome) async {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        runner.outcome = outcome
        let checklist = Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")])
        let coordinator = makeCoordinator(transport: transport, checklists: [checklist], runner: runner)
        coordinator.start()

        transport.deliver(.runChecklist(id: checklist.id, runID: UUID()))
        for _ in 0..<50 where runner.created.isEmpty { await Task.yield() }

        #expect(runner.created == [checklist])
    }
```

### Verification

#### Automated
- [x] `make test-unit` passes (all suites green; `ChecklistSyncMessageTests` covers the new case shape and the missing-`runID` rejection; `ChecklistSyncCoordinatorTests` covers the happy path plus `.permissionDenied`/`.failed`/`.destinationMissing` sad outcomes reaching the run closure)
- [x] `make build` passes (iOS app target compiles with the new adapter logging)
- [x] `make watch-build` passes (watch target compiles `ChecklistSyncDiagnostics` for watchOS)

#### Manual — the decision gate (REQUIRED before Phase 2)
- [x] `xcrun devicectl list devices` (or `idevice_id -l`) shows the paired iPhone + Apple Watch
- [x] `bash scripts/run-watch.sh` installs and launches `CheckStitchWatch` on the paired watch without error
- [x] Start the phone log stream in a second shell: `idevicesyslog -u <iphone-udid> | grep -E '\[(watchSend|watchActivation|phoneReceive|phoneHandle|snapshotLookup|createOutcome)\]'` (performed via the `Documents/checklist-sync.log` file sink capture — `idevicessyslog` is absent on this host)
- [x] For the watch, open Console.app (or Xcode → Window → Devices and Simulators → select the watch → Open Console) and filter `subsystem == "app.alanvardy.CheckStitch" AND category == "ChecklistSync"` (same filter applied to the pulled `checklist-sync.log` files; Console.app left as the live viewer)
- [x] On the watch: open CheckStitch → open a checklist → tap **Create reminders** exactly once, and wait ~15 s
- [x] Record the chain: does `[watchSend] accepted=true` appear? does `[phoneReceive]` appear? does `[phoneHandle]` appear? `[snapshotLookup] result=hit|miss`? `[createOutcome] outcome=?` — yes: `accepted=true`, `[phoneReceive]`, `[phoneHandle]`, `result=hit`, `outcome=created(count: 11)`; 11 reminders confirmed visible in the iPhone Reminders app
- [x] Write the observed chain into `.pi/orksorksorks/alanvardy-var-1027-create-checklist-not-working-on-watch/spike.md`

**STOP.** The recorded chain selects the Phase 2–4 scope (design decision 7). If
nothing fires at all (e.g. no `[phoneReceive]`), the phone app / Reminders
permission is the primary defect; if `[snapshotLookup] result=miss`, Phase 3 is
primary; if `[watchSend] accepted=false`, Phase 4 is primary. If the chain is
clean end to end on hardware, stop and re-run the `design` step rather than
fixing healthy code.

---

## Phase 2: Honest watch feedback — Sending… → Created / reason

### Changes

#### 1. Phone→watch result value + message case
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify

```swift
    public static let runResult = "runResult"
    public static let runResultRunID = "runID"
    public static let runResultChecklistID = "checklistID"
    public static let runResultKind = "kind"
    public static let runResultCount = "count"
```

```swift
/// The phone's answer to one run request. Mirrors `ReminderRunOutcome` and
/// drops the free-form failure message: the watch renders a fixed reason per
/// kind.
public enum RunResultKind: Equatable, Sendable {
    case created(Int)
    case permissionDenied
    case destinationMissing
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
        case .failed: "Couldn't create reminders."
        }
    }

    var wireName: String {
        switch self {
        case .created: "created"
        case .permissionDenied: "permissionDenied"
        case .destinationMissing: "destinationMissing"
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
```

Add `case runResult(RunResult)` to `ChecklistSyncMessage` (after
`requestChecklists`), plus decode/encode and the diagnostic name:

```swift
        } else if let dict = userInfo[ChecklistSyncKey.runResult] as? [String: Any],
                  let runRaw = dict[ChecklistSyncKey.runResultRunID] as? String,
                  let runID = UUID(uuidString: runRaw),
                  let checklistRaw = dict[ChecklistSyncKey.runResultChecklistID] as? String,
                  let checklistID = UUID(uuidString: checklistRaw),
                  let kindRaw = dict[ChecklistSyncKey.runResultKind] as? String,
                  let kind = RunResultKind(wireName: kindRaw, count: dict[ChecklistSyncKey.runResultCount] as? Int) {
            self = .runResult(RunResult(runID: runID, checklistID: checklistID, kind: kind))
```

```swift
        case .runResult(let result):
            var dict: [String: Any] = [
                ChecklistSyncKey.runResultRunID: result.runID.uuidString,
                ChecklistSyncKey.runResultChecklistID: result.checklistID.uuidString,
                ChecklistSyncKey.runResultKind: result.kind.wireName,
            ]
            if case .created(let count) = result.kind {
                dict[ChecklistSyncKey.runResultCount] = count
            }
            return [ChecklistSyncKey.runResult: dict]
```

```swift
        case .runResult(let result):
            "runResult(run:\(result.runID.uuidString),kind:\(result.kind.wireName))"
```

#### 2. Watch store: run phases fed by `.runResult`
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift` (`WatchChecklistStore`)
**Action**: modify

```swift
/// What the watch button shows for one run.
public enum RunPhase: Equatable, Sendable {
    case idle
    case sending
    case created(Int)
    case failed(String)
}
```

```swift
    private var phases: [UUID: RunPhase] = [:]

    /// The phase of `runID`; `.idle` for an unknown run.
    public func runPhase(runID: UUID) -> RunPhase { phases[runID] ?? .idle }
```

`run(_:)` records the phase on acceptance:

```swift
        guard accepted else { return nil }
        pendingRunID = runID
        phases[runID] = .sending
        return runID
```

`receive(_:)` gains the result case and the `.runResult` entry in the phone-only
`break` list is removed:

```swift
        case .runResult(let result):
            if pendingRunID == result.runID { pendingRunID = nil }
            phases[result.runID] = switch result.kind {
            case .created(let count): .created(count)
            case .permissionDenied, .destinationMissing, .failed: .failed(result.kind.message)
            }
        case .runChecklist, .requestChecklists:
            break // phone-only directions
```

#### 3. Coordinator answers every handled run
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift`
**Action**: modify

Replace the Phase 1 outcome-logging body of the chained task:

```swift
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
```

Add the `.runResult` arm to the switch in `handle`:

```swift
        case .context, .runResult:
            break // watch-only / phone→watch directions
```

#### 4. Watch button shows the real phase
**File**: `CheckStitchWatch/WatchChecklistDetailView.swift`
**Action**: modify

```swift
struct WatchChecklistDetailView: View {
    let checklist: Checklist
    @Environment(WatchChecklistStore.self) private var store
    @State private var runID: UUID?

    /// Blank rows are never turned into reminders, so the watch hides them too.
    private var visibleItems: [ChecklistItem] {
        checklist.items.filter { !$0.isBlank }
    }

    private var phase: RunPhase {
        runID.map { store.runPhase(runID: $0) } ?? .idle
    }

    private var buttonTitle: String {
        switch phase {
        case .sending: String(localized: "Sending…", table: "Localizable", bundle: .main)
        case .created: String(localized: "Created", table: "Localizable", bundle: .main)
        case .idle, .failed: String(localized: "Create reminders", table: "Localizable", bundle: .main)
        }
    }

    private var buttonDisabled: Bool {
        switch phase {
        case .sending, .created: true
        case .idle, .failed: visibleItems.isEmpty
        }
    }

    var body: some View {
        List(visibleItems) { item in
            VStack(alignment: .leading) {
                Text(item.title)
                if item.hasDescription {
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(checklist.name)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button(buttonTitle) {
                    runID = store.run(checklist)
                }
                .disabled(buttonDisabled)
                if case .failed(let reason) = phase {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}
```

#### 5. Localized button labels
**File**: `CheckStitchWatch/Localizable.xcstrings`
**Action**: modify

Add two keys (keep the file's alphabetical order: `Created` after
`"Create reminders"`, `"Sending…"` before `"Sent"`):

```json
    "Created" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Created"
          }
        }
      }
    },
```

```json
    "Sending…" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sending…"
          }
        }
      }
    },
```

English only: the catalog marks them for translation on the next localization
pass, and untranslated keys fall back to the source value at runtime. (The
existing `"Sent"` key is left in place — removing keys is out of scope.)

#### 6. Tests
**Files**: `CheckStitchTests/ChecklistSyncMessageTests.swift`,
`CheckStitchTests/WatchChecklistStoreTests.swift`,
`CheckStitchTests/ChecklistSyncCoordinatorTests.swift`
**Action**: modify

`ChecklistSyncMessageTests`:

```swift
    @Test
    func runResultRoundTripsThroughUserInfo() {
        let result = RunResult(runID: UUID(), checklistID: UUID(), kind: .created(2))
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.runResult(result).userInfo) == .runResult(result))
    }

    @Test
    func runResultWithAMalformedKindIsRejected() {
        #expect(ChecklistSyncMessage(userInfo: [
            ChecklistSyncKey.runResult: [
                ChecklistSyncKey.runResultRunID: UUID().uuidString,
                ChecklistSyncKey.runResultChecklistID: UUID().uuidString,
                ChecklistSyncKey.runResultKind: "exploded",
            ],
        ]) == nil)
        #expect(ChecklistSyncMessage(userInfo: [
            ChecklistSyncKey.runResult: [
                ChecklistSyncKey.runResultRunID: UUID().uuidString,
                ChecklistSyncKey.runResultChecklistID: UUID().uuidString,
                ChecklistSyncKey.runResultKind: "created", // no count
            ],
        ]) == nil)
    }
```

`WatchChecklistStoreTests`:

```swift
    @Test
    func runEntersSendingAndCreatedConfirmsIt() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")

        let runID = try #require(store.run(checklist))
        #expect(store.runPhase(runID: runID) == .sending)

        transport.deliver(.runResult(RunResult(runID: runID, checklistID: checklist.id, kind: .created(2))))

        #expect(store.runPhase(runID: runID) == .created(2))
        #expect(store.pendingRunID == nil)
    }

    @Test
    func failedResultShowsAReasonAndKeepsTheRunOutOfPending() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")

        let runID = try #require(store.run(checklist))
        transport.deliver(.runResult(RunResult(runID: runID, checklistID: checklist.id, kind: .permissionDenied)))

        #expect(store.runPhase(runID: runID) == .failed(RunResultKind.permissionDenied.message))
        #expect(store.pendingRunID == nil)
    }

    @Test
    func resultForAnUnknownRunIsIgnored() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)

        transport.deliver(.runResult(RunResult(runID: UUID(), checklistID: UUID(), kind: .failed)))

        #expect(store.pendingRunID == nil)
    }
```

`ChecklistSyncCoordinatorTests` — one test per outcome mapping:

```swift
    @Test(arguments: [
        (ReminderRunOutcome.created(count: 2), RunResultKind.created(2)),
        (.permissionDenied, .permissionDenied),
        (.destinationMissing, .destinationMissing),
        (.failed("boom"), .failed),
    ])
    func everyOutcomeIsAnsweredOnTheWatchChannel(outcome: ReminderRunOutcome, kind: RunResultKind) async {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        runner.outcome = outcome
        let checklist = Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")])
        let coordinator = makeCoordinator(transport: transport, checklists: [checklist], runner: runner)
        coordinator.start()

        let runID = UUID()
        transport.deliver(.runChecklist(id: checklist.id, runID: runID))
        for _ in 0..<50 where transport.sentMessages.count < 2 { await Task.yield() }

        #expect(transport.sentMessages.last == .runResult(
            RunResult(runID: runID, checklistID: checklist.id, kind: kind)))
    }
```

### Verification

#### Automated
- [x] `make test-unit` passes
- [x] `make watch-build` passes (detail view compiles against `RunPhase`)
- [x] `make build` passes

#### Manual
- [ ] `bash scripts/run-watch.sh`, tap **Create reminders** with the phone app running: the button reads `Sending…` and then `Created`
- [ ] With the phone app force-quit, tap again: the button stays `Sending…` (never a false success) — this is the Phase 4 symptom, not a regression
- [ ] Phone log shows `[createOutcome] outcome=created(n)` and the watch receives one `.runResult`

---

## Phase 3: Unknown/stale id recovers instead of silently dropping

### Changes

#### 1. New result kind
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify

```swift
public enum RunResultKind: Equatable, Sendable {
    case created(Int)
    case permissionDenied
    case destinationMissing
    /// The phone no longer has this checklist; it is re-pushing its context.
    case notFound
    case failed
```

```swift
        case .notFound: "Not found — refreshing."
```

```swift
        case .notFound: "notFound"
```

```swift
        case "notFound": self = .notFound
```

#### 2. Coordinator replies + re-pushes on a snapshot miss
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift`
**Action**: modify

```swift
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
```

#### 3. Watch handles the miss
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift` (`WatchChecklistStore.receive`)
**Action**: modify

```swift
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
```

**File**: `CheckStitchWatch/WatchChecklistDetailView.swift`
**Action**: verify only

No view change is needed: `.failed(reason)` already renders the reason and
re-enables the button, and the refreshed context either drops the stale
checklist from the list or replaces the pushed `checklist` value.

### Verification

#### Automated
- [x] `make test-unit` passes
- [x] `ChecklistSyncCoordinatorTests`: `runRequestForUnknownIDAnswersNotFoundAndRePushes` — no create, exactly one `.runResult(.notFound)`, exactly one extra context push (`transport.sentContexts.count == 2`):
  ```swift
  @Test
  func runRequestForUnknownIDAnswersNotFoundAndRePushes() async {
      let transport = FakeChecklistSyncTransport()
      let runner = SpyChecklistRunner()
      let coordinator = makeCoordinator(transport: transport, checklists: [], runner: runner)
      coordinator.start()

      let id = UUID()
      let runID = UUID()
      transport.deliver(.runChecklist(id: id, runID: runID))
      await Task.yield()

      #expect(runner.created.isEmpty)
      #expect(transport.sentContexts.count == 2)
      #expect(transport.sentMessages == [.runResult(
          RunResult(runID: runID, checklistID: id, kind: .notFound))])
  }
  ```
- [x] `ChecklistSyncCoordinatorTests`: `runRequestForKnownIDPushesNoExtraContext` — known id creates once and `transport.sentContexts.count == 1`
- [x] `WatchChecklistStoreTests`: `notFoundResultAsksForAFreshContext` — after `.runResult(.notFound)` the store sent `.requestChecklists` and the phase is `.failed(RunResultKind.notFound.message)`:
  ```swift
  @Test
  func notFoundResultAsksForAFreshContext() {
      let transport = FakeChecklistSyncTransport()
      let store = WatchChecklistStore(transport: transport)
      let checklist = Checklist(name: "Groceries")
      let runID = store.run(checklist)
      transport.deliver(.runResult(RunResult(runID: runID, checklistID: checklist.id, kind: .notFound)))

      #expect(transport.sentMessages.contains(.requestChecklists))
      #expect(store.runPhase(runID: runID) == .failed(RunResultKind.notFound.message))
      #expect(store.pendingRunID == nil)
  }
  ```
- [x] `make watch-build` passes

#### Manual
- [ ] On the phone, delete a checklist the watch is showing
- [ ] On the watch, open the now-stale checklist and tap **Create reminders**
- [ ] The watch shows `Not found — refreshing.` and the list self-corrects on the refreshed context

---

## Phase 4: Retain-and-resend across the activation race / non-running phone

### Changes

#### 1. Watch store: pending runs, retained until a confirmed result
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify

```swift
/// A run the watch has started but not yet seen confirmed by the phone.
public struct PendingRun: Equatable, Sendable {
    public let runID: UUID
    public let checklistID: UUID

    public init(runID: UUID, checklistID: UUID) {
        self.runID = runID
        self.checklistID = checklistID
    }
}
```

```swift
    /// Every run awaiting a phone result, keyed by run id. Replaces the
    /// write-only `pendingRunID`: a run issued before the session is usable is
    /// retained and re-sent on activation, and cleared only by its result.
    public private(set) var pendingRuns: [UUID: PendingRun] = [:]
```

```swift
    /// Activates the transport and starts listening. Safe to call repeatedly.
    /// Both the refresh and the re-send hang off `onActivated`: a send that
    /// races `activate()` is dropped, so `onActivated` is the first moment a
    /// retained run can actually leave the watch.
    public func start() {
        transport.onMessage = { [weak self] in self?.receive($0) }
        transport.onActivated = { [weak self] in
            self?.requestRefresh()
            self?.retryPendingRuns()
        }
        transport.activate()
    }
```

```swift
    /// Asks the phone to create reminders for `checklist`. Always starts a run:
    /// the request is retained and re-sent when the session becomes usable, so
    /// the UI can honestly show `Sending…` from the first tap.
    @discardableResult
    public func run(_ checklist: Checklist) -> UUID {
        let runID = UUID()
        pendingRuns[runID] = PendingRun(runID: runID, checklistID: checklist.id)
        phases[runID] = .sending
        send(PendingRun(runID: runID, checklistID: checklist.id))
        return runID
    }

    /// Re-sends every run still waiting for a phone result. Exactly one send per
    /// pending run per activation; the phone de-dups by `runID`.
    private func retryPendingRuns() {
        for pending in pendingRuns.values.sorted(by: { $0.runID.uuidString < $1.runID.uuidString }) {
            send(pending)
        }
    }

    private func send(_ pending: PendingRun) {
        let accepted = transport.sendUserInfo(.runChecklist(id: pending.checklistID, runID: pending.runID))
        ChecklistSyncDiagnostics.log(.watchSend, [
            "run": pending.runID.uuidString,
            "checklist": pending.checklistID.uuidString,
            "accepted": accepted ? "true" : "false",
        ])
    }
```

`receive`'s result branch clears by run id:

```swift
        case .runResult(let result):
            pendingRuns.removeValue(forKey: result.runID)
            phases[result.runID] = switch result.kind {
```

Remove `pendingRunID` entirely.

#### 2. Coordinator: at-least-once, idempotent by `runID`
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift`
**Action**: modify

```swift
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
```

Storage + bound:

```swift
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
```

`Task { [createReminders, transport] in ... self.remember(result) ... }` captures
`self` strongly; `ChecklistSyncCoordinator` is owned by `MyApp` for its lifetime
and holds no reference to the task, so the retain is bounded by the run itself.
(If a reviewer objects, capture `[weak self]` and skip the memory on nil — the
result send must still happen either way.)

#### 3. Adapters: `sendUserInfo` is acceptance, not delivery
**Files**: `CheckStitchWatch/WatchSyncAdapter.swift`,
`CheckStitch/PhoneSyncAdapter.swift`
**Action**: modify (documentation/contract only — behaviour is already correct)

```swift
    /// `true` means only that `WCSession` was alive and accepted the transfer
    /// for queued delivery — never that the peer received or acted on it. The
    /// watch therefore reports progress from `.runResult`, never from this.
    @discardableResult
    func sendUserInfo(_ message: ChecklistSyncMessage) -> Bool {
```

```swift
    /// Phone → watch is a queued command (`transferUserInfo`), so a result
    /// survives the watch app not running. `true` is acceptance, not delivery.
    @discardableResult
    func sendUserInfo(_ message: ChecklistSyncMessage) -> Bool {
```

#### 4. Watch view: unchanged
**File**: `CheckStitchWatch/WatchChecklistDetailView.swift`
**Action**: verify only

`@State private var runID: UUID?` still compiles: `store.run(checklist)` now
returns a non-optional `UUID`.

#### 5. Tests
**Files**: `CheckStitchTests/WatchChecklistStoreTests.swift`,
`CheckStitchTests/ChecklistSyncCoordinatorTests.swift`
**Action**: modify

`WatchChecklistStoreTests` — replace `aRejectedSendStartsNoRun`,
`runEntersSendingAndCreatedConfirmsIt`'s `pendingRunID` assertions, and
`resultForAnUnknownRunIsIgnored`:

```swift
    @Test
    func runBeforeActivationIsRetainedThenResentExactlyOnceOnActivation() throws {
        let transport = FakeChecklistSyncTransport()
        transport.acceptsSends = false
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")
        store.start()

        let runID = store.run(checklist)
        #expect(store.pendingRuns[runID]?.checklistID == checklist.id)

        transport.acceptsSends = true
        transport.completeActivation()

        let runSends = transport.sentMessages.filter { if case .runChecklist = $0 { return true }; return false }
        #expect(runSends == [
            .runChecklist(id: checklist.id, runID: runID),   // the rejected first attempt
            .runChecklist(id: checklist.id, runID: runID),   // the activation re-send
        ])
    }

    @Test
    func aResultClearsThePendingRun() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")
        let runID = store.run(checklist)

        transport.deliver(.runResult(RunResult(runID: runID, checklistID: checklist.id, kind: .created(1))))

        #expect(store.pendingRuns.isEmpty)
        #expect(store.runPhase(runID: runID) == .created(1))
    }

    @Test
    func aRejectedResendLeavesTheRunPending() {
        let transport = FakeChecklistSyncTransport()
        transport.acceptsSends = false
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")
        store.start()
        let runID = store.run(checklist)

        transport.completeActivation()   // still refusing sends

        #expect(store.pendingRuns[runID] != nil)
    }
```

(Two `runChecklist` sends appear because `send` logs the rejected attempt too;
the assertion above deliberately shows exactly one re-send on activation.)

`ChecklistSyncCoordinatorTests`:

```swift
    @Test
    func duplicateRunIDCreatesOnceAndIsAckedAgain() async {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let checklist = Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")])
        let coordinator = makeCoordinator(transport: transport, checklists: [checklist], runner: runner)
        coordinator.start()

        let runID = UUID()
        transport.deliver(.runChecklist(id: checklist.id, runID: runID))
        for _ in 0..<50 where runner.created.isEmpty { await Task.yield() }
        transport.deliver(.runChecklist(id: checklist.id, runID: runID))
        await Task.yield()

        #expect(runner.created.count == 1)
        #expect(transport.sentMessages.filter { $0 == .runResult(
            RunResult(runID: runID, checklistID: checklist.id, kind: .created(1))) }.count == 2)
    }

```

`duplicateRunIDCreatesOnceAndIsAckedAgain` is the Phase 4 automated proof. Note
that a re-sent *unknown* run is intentionally acked as `notFound` (idempotent by
`runID`), so the correct retry after a context push lands is a **new tap**, which
carries a new `runID` — the Phase 3/5 device checks cover that.

### Verification

#### Automated
- [ ] `make test-unit` passes
- [ ] `WatchChecklistStoreTests`: `runBeforeActivationIsRetainedThenResentExactlyOnceOnActivation`, `aResultClearsThePendingRun`, `aRejectedResendLeavesTheRunPending`
- [ ] `ChecklistSyncCoordinatorTests`: `duplicateRunIDCreatesOnceAndIsAckedAgain` (one create, two acks)
- [ ] `make watch-build` passes

#### Manual
- [ ] Force-quit CheckStitch on the iPhone, then tap **Create reminders** on the watch: the button shows `Sending…`
- [ ] Launch CheckStitch on the iPhone (foreground once, so the session activates)
- [ ] The phone creates exactly **one** set of reminders; the watch transitions to `Created`
- [ ] Re-tap the same checklist afterwards: the second run creates a second, distinct set (a checklist can legitimately be run twice — de-dup is per `runID`, not per checklist)

---

## Phase 5: Hardening — sad paths, log hygiene, on-device verdict

### Changes

#### 1. Phone adapter: never vanish on a decoded run
**File**: `CheckStitch/PhoneSyncAdapter.swift`
**Action**: modify

```swift
    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let message = ChecklistSyncMessage(userInfo: userInfo) else {
            // No run id is recoverable, so there is nobody to answer — log and
            // drop. Every decodable message gets a reply below.
            ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "userInfo", "decode": "rejected"])
            return
        }
        ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "userInfo", "message": message.diagnosticName])
        Task { @MainActor [weak self] in
            guard let self else {
                ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "userInfo", "handler": "self-nil"])
                return
            }
            guard let onMessage = self.onMessage else {
                // Arrived before `coordinator.start()` installed the handler:
                // answer with a failure so the watch is not left on `Sending…`.
                ChecklistSyncDiagnostics.log(.phoneReceive, ["source": "userInfo", "handler": "unset"])
                if case .runChecklist(let id, let runID) = message {
                    self.sendUserInfo(.runResult(
                        RunResult(runID: runID, checklistID: id, kind: .failed)))
                }
                return
            }
            onMessage(message)
        }
    }
```

#### 2. Phone adapter: log a dropped result send
**File**: `CheckStitch/PhoneSyncAdapter.swift`
**Action**: modify

```swift
    @discardableResult
    func sendUserInfo(_ message: ChecklistSyncMessage) -> Bool {
        guard session.activationState == .activated else {
            ChecklistSyncDiagnostics.log(.phoneHandle, [
                "message": message.diagnosticName,
                "send": "session-not-activated",
            ])
            return false
        }
        session.transferUserInfo(message.userInfo)
        return true
    }
```

#### 3. Watch adapter: log the unsupported/unactivated case once per send
**File**: `CheckStitchWatch/WatchSyncAdapter.swift`
**Action**: verify only

Already covered by Phase 1's `.watchActivation` (activate-time) and
`.watchSend` (send-time `activationState`) records. No new code.

#### 4. Watch reason strings for every kind
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: verify only

`RunResultKind.message` already returns a reason for every kind (Phases 2–3).
No new code.

#### 5. Tests
**Files**: `CheckStitchTests/WatchChecklistStoreTests.swift`,
`CheckStitchTests/ChecklistSyncMessageTests.swift`
**Action**: modify

```swift
    @Test(arguments: [
        (RunResultKind.created(3), RunPhase.created(3)),
        (.permissionDenied, .failed(RunResultKind.permissionDenied.message)),
        (.destinationMissing, .failed(RunResultKind.destinationMissing.message)),
        (.notFound, .failed(RunResultKind.notFound.message)),
        (.failed, .failed(RunResultKind.failed.message)),
    ])
    func everyResultKindMapsToAUserVisiblePhase(kind: RunResultKind, phase: RunPhase) {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")
        let runID = store.run(checklist)

        transport.deliver(.runResult(RunResult(runID: runID, checklistID: checklist.id, kind: kind)))

        #expect(store.runPhase(runID: runID) == phase)
    }
```

`ChecklistSyncMessageTests` already asserts malformed/unknown-key/wrong-type
rejection (Phase 1 + 2 additions); add the non-dictionary `runResult` payload:

```swift
    @Test
    func runResultWithANonDictionaryPayloadIsRejected() {
        #expect(ChecklistSyncMessage(userInfo: [ChecklistSyncKey.runResult: "nope"]) == nil)
    }
```

### Verification

#### Automated
- [ ] `make test-unit` passes
- [ ] `./scripts/test.sh` prints `gate: ok` (full gate: `make build` → `make test` → `make build-mac` → `make watch-build` → `scripts/tests/run.sh` → `shellcheck`)
- [ ] No new silent paths remain on the run path: every `.runChecklist` that decodes is answered by exactly one `.runResult` (phone unit test + `[phoneHandle]` logs)

#### Manual — the closing verdict (sync tickets cannot close on static evidence)
- [ ] `bash scripts/run-watch.sh` installs + launches the watch app
- [ ] Phone app installed and launched at least once; Reminders permission granted
- [ ] Tap **Create reminders** on a real checklist while the phone app is running → reminders appear in the iPhone's Reminders app; the watch button reads `Created`
- [ ] Force-quit the phone app, tap again, then launch the phone → exactly one set of reminders appears; the watch reaches `Created`
- [ ] Deny Reminders permission (Settings → CheckStitch → Reminders → off), tap → the watch shows a permission reason and the button is enabled again
- [ ] Capture the full log chain for the closing comment: `idevicesyslog -u <iphone-udid> | grep -E '\[(watchSend|phoneReceive|phoneHandle|snapshotLookup|createOutcome)\]'` plus the watch Console filter
- [ ] State the user-visible end state in the completion artifact (reminders in the iPhone's Reminders app; watch reads `Created`; failures show a reason and retry)

---

## Testing Checkpoints

- [x] **After Phase 1**: `make test-unit` green **and** the one-tap hardware log chain is captured in `spike.md` — its evidence fixes the Phase 2–4 scope before any fix code (this is a hard gate; if the chain is clean, stop and re-run `design`). Chain captured in `spike.md`: mechanically clean end-to-end with the phone app running; primary defect reproduced as the phone-not-running / no-honest-feedback family. User elected to proceed with Phases 2–4 per design decision 7.
- [ ] **After Phase 2**: `make test-unit` + `make watch-build` green; device shows `Sending…` → `Created`, never a false `Sent`/success.
- [ ] **After Phase 3**: `make test-unit` green; stale-id device check self-corrects (`Not found — refreshing.` then a fresh list).
- [ ] **After Phase 4**: `make test-unit` green; not-running-phone device check creates exactly once and the watch reaches `Created`.
- [ ] **After Phase 5**: `./scripts/test.sh` prints `gate: ok`, plus the on-device verdict above.

## Residual Risks (carried from design)

- **Cross-launch duplicates**: the phone's `rememberedResults` is in-memory, so a
  run re-sent after the *phone* process restarts can create twice. Not
  addressable without persistence; out of scope.
- **Legacy queued messages**: a `transferUserInfo` queued by a pre-change watch
  build carries no `runID` and is dropped by the new decoder. One-time upgrade
  edge; the watch re-sends with a `runID` on its next activation.
- **Localization**: the two new watch button labels ship English-only (the
  catalog falls back to the source value); the Core reason strings are English
  by existing convention (`ReminderRunOutcome.errorMessage`).