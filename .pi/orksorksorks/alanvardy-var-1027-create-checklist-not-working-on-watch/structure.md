# Structure Outline

## Approach

Instrument-first (design decision 1): a correlated log per gate on both targets
locates the root cause on a real watch/phone, then the "silent-drop family" fix
(decisions 2–4) lands as a phone→watch result channel, honest watch feedback,
unknown-id recovery, and retain-and-resend — all through the existing
`ChecklistSyncing` seam and app-only `WCSession` adapters, tested with fakes and
verified on device (`bash scripts/run-watch.sh`).

---

## Phase 1: Walking skeleton — an instrumented tap observed end to end (root cause located)

One tap on the watch produces a single correlated chain of `os_log` records:
watch activation state + transfer acceptance at send time, phone
`didReceiveUserInfo` arrival, `handle(.runChecklist)` entry, snapshot membership
of the id, and the final `ReminderRunOutcome` (today discarded). The outcome is
threaded out of the coordinator closure, so the chain no longer stops at "Sent".
Green tests prove the outcome/run-id plumbing; the hardware spike is the demo
and produces the evidence that selects the fix for Phases 2–4.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`,
`ChecklistSyncCoordinator.swift`, `ChecklistSyncDiagnostics.swift` (new),
`CheckStitch/MyApp.swift`, `CheckStitch/PhoneSyncAdapter.swift`,
`CheckStitchWatch/WatchSyncAdapter.swift`, `CheckStitchWatch/WatchChecklistDetailView.swift`

**Key changes**:
- `enum SyncGate { case watchSend, watchActivation, phoneReceive, phoneHandle, snapshotLookup, createOutcome }` — new
- `enum ChecklistSyncDiagnostics { static func log(_ gate: SyncGate, _ fields: [String: String]) }` (wraps one `Logger(subsystem:category:)`) — new
- `case runChecklist(id: UUID, runID: UUID)` — modified: per-run id is the correlation (and later de-dup) key
- `typealias CreateReminders = (Checklist) async -> ReminderRunOutcome` — modified from `async -> Void`
- `ChecklistSyncCoordinator.handle` / `run(_:runID:)` log every guard, incl. the SnapshotLookup miss — modified

**Contract**: `SyncGate`/`ChecklistSyncDiagnostics` (both targets log through it);
the outcome-carrying `CreateReminders` closure; the `runID` carried by
`.runChecklist` and echoed in every later `RunResult`.

**Tests**: `WatchChecklistStoreTests` — a run emits one `.runChecklist` carrying a fresh `runID`; `ChecklistSyncCoordinatorTests` — known id invokes `createReminders` once and the returned `ReminderRunOutcome` is observable via `SpyChecklistRunner` (happy + `.permissionDenied`/`.failed` sad paths).
**Verify**: `make test-unit` green; then the decision gate —
`bash scripts/run-watch.sh`, tap once, read both targets' logs (Console/Xcode
per `SyncGate`), and record which gate fires. **This evidence selects the
Phase 2–4 scope (design decision 7); do not proceed without it.**

---

## Phase 2: Honest watch feedback — Sending… → Created / reason

Tapping Create reminders shows `Sending…` until the phone confirms; `Created`
only after `ReminderRunOutcome.created(count:)`, otherwise a short reason and a
re-enabled button. The phone answers every handled run with a `.runResult`.

**Files**: `ChecklistSync.swift`, `ChecklistSyncCoordinator.swift`,
`CheckStitch/PhoneSyncAdapter.swift`, `CheckStitchWatch/WatchChecklistDetailView.swift`

**Key changes**:
- `struct RunResult { let runID: UUID; let checklistID: UUID; let kind: RunResultKind }` — new
- `enum RunResultKind { case created(Int), permissionDenied, destinationMissing, failed }` — new
- `case runResult(RunResult)` — new `ChecklistSyncMessage` case (codec)
- `enum RunPhase { case idle, sending, created(Int), failed(String) }`; `WatchChecklistStore.runPhase(runID: UUID) -> RunPhase`; `run(_:)` sets `.sending`; `receive` maps `.runResult` → phase — modified/new
- coordinator sends `transport.sendUserInfo(.runResult(...))` on completion — new call site

**Contract**: `RunResult`/`RunResultKind` wire shape and `runPhase` are what
Phase 3 reads; `.runResult` is emitted for **every** run that reaches the
coordinator (Phase 3 adds the `notFound` kind).

**Tests**: `ChecklistSyncMessageTests` — `.runResult` round-trip + unknown-key/wrong-type rejection; `WatchChecklistStoreTests` — `.sending` on run, `.created(2)`/`.failed` on result, unknown `runID` ignored; `ChecklistSyncCoordinatorTests` — each `ReminderRunOutcome` maps to the matching `RunResult` (happy + 2 sad).
**Verify**: `make test-unit` green; device: `bash scripts/run-watch.sh`, tap shows `Sending…` then `Created`/reason.

---

## Phase 3: Unknown/stale id recovers instead of silently dropping

Running a checklist whose id is not in the phone snapshot yields `notFound — refreshing` on the watch plus a fresh context push; the watch list self-corrects and the button re-enables.

**Files**: `ChecklistSyncCoordinator.swift`, `ChecklistSync.swift`, `CheckStitchWatch/WatchChecklistDetailView.swift`

**Key changes**:
- `RunResultKind.notFound` — new case
- `ChecklistSyncCoordinator.handle(.runChecklist)` snapshot miss → send `.runResult(.notFound)`, then `pushContext()`, then return — modified (replaces the bare `return` at `:40`)
- `WatchChecklistStore.receive(.runResult(.notFound))` → phase + `requestRefresh()` — modified

**Contract**: the snapshot-miss outcomes (`.runResult(.notFound)` + re-pushed
`.context`) that Phase 4's resend must not fight.

**Tests**: `ChecklistSyncCoordinatorTests` — unknown id: no create, exactly one `.runResult(.notFound)`, exactly one extra `.context` push (happy); known id still creates once and does **not** push a redundant context (sad/regression).
**Verify**: `make test-unit` green; device: delete a checklist on the phone, tap the stale one on the watch → `Not found — refreshing`, then the fresh list.

---

## Phase 4: Retain-and-resend across the activation race / non-running phone

A run issued before the session activates (or while the phone is not running) is retained and re-sent on `onActivated`/context arrival, and cleared only on a confirmed `.runResult` — no duplicate reminders.

**Files**: `ChecklistSync.swift`, `ChecklistSyncCoordinator.swift`, `CheckStitch/PhoneSyncAdapter.swift`, `CheckStitchWatch/WatchSyncAdapter.swift`

**Key changes**:
- `WatchChecklistStore.pendingRuns: [UUID: PendingRun]` (was write-only `pendingRunID`); re-issue from the `onActivated` refresh path — modified
- `ChecklistSyncCoordinator.completedRunIDs: Set<UUID>` (bounded) — `.runChecklist` with a seen `runID` is acked, never re-created; `.runResult` clears the watch's pending entry — new
- adapter `sendUserInfo` result is **not** treated as delivery (only `transferUserInfo` acceptance) — modified

**Contract**: `.runChecklist` is at-least-once and idempotent by `runID`; the
watch clears a pending run only on a matching `.runResult`.

**Tests**: `WatchChecklistStoreTests` — run before activation is retained then re-sent exactly once on activation; cleared on `.runResult`; not cleared on rejected send. `ChecklistSyncCoordinatorTests` — duplicate `runID` creates once (idempotency). Happy + sad.
**Verify**: `make test-unit` green; device: tap with the phone app not running, then launch it → exactly one set of reminders, watch reaches `Created`.

---

## Phase 5: Hardening — sad paths, log hygiene, on-device verdict

Every remaining silent drop on the run path is either surfaced or intentionally
silent-and-logged, and the ticket closes on the stated on-device end state.

**Files**: `ChecklistSync.swift`, `CheckStitch/PhoneSyncAdapter.swift`, `CheckStitchWatch/WatchSyncAdapter.swift`

**Key changes**:
- codec rejection + `self`-nil + `onMessage`-nil (pre-`start()`) log their gate and fail the run instead of vanishing — modified
- `.permissionDenied`/`.destinationMissing` are logged on the phone (today unlogged); watch reason strings for each `RunResultKind` — modified
- no new transport, no EventKit semantics change, no phone in-app Run-path change (design "What We're NOT Doing")

**Contract**: none new — closes the gate on the existing seams.

**Tests**: `ChecklistSyncMessageTests` — malformed/unknown payload rejection stays silent-but-typed; `WatchChecklistStoreTests` — one test per `RunResultKind` → user-visible phase.
**Verify**: `./scripts/test.sh` prints `gate: ok`; device `bash scripts/run-watch.sh` and state the user-visible end state (reminders in the iPhone's Reminders app; watch reads `Created`; failure shows a reason and retries).

---

## Testing Checkpoints

- After Phase 1: `make test-unit` green **and** the hardware spike log chain captured — its evidence fixes Phases 2–4 scope before any fix code.
- After Phase 2: `make test-unit` green; device shows `Sending…`→`Created`, never a false `Sent`.
- After Phase 3: `make test-unit` green; stale-id device check self-corrects.
- After Phase 4: `make test-unit` green; not-running-phone device check creates exactly once.
- After Phase 5: full `./scripts/test.sh` → `gate: ok`, plus the on-device verdict.
