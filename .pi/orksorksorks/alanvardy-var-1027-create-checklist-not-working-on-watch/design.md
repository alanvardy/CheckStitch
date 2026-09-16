# Design Discussion — VAR-1027 Create checklist not working on watch

## Current State

Tapping **Create reminders** on the watch does nothing visible on the phone. The
path exists and is coherent, but every link between "tap" and "reminder created"
is best-effort with **zero end-to-end feedback** (research.md, Cross-Cutting).

- **Watch send**: `WatchChecklistDetailView.swift:20-28` — button action
  `sent = store.run(checklist)` (`:24`), disabled when `sent || visibleItems.isEmpty`
  (`:25`). `WatchChecklistStore.run` (`ChecklistSync.swift:87-91`) guards
  `transport.sendUserInfo(...)` and, on acceptance, sets `pendingRunID`
  (`:70-71`) and returns `true`. `WatchSyncAdapter.sendUserInfo`
  (`WatchSyncAdapter.swift:27-31`) returns `false` unless
  `activationState == .activated` (`:28`) and then **discards** the
  `transferUserInfo` result, returning `true` unconditionally (`:29-30`).
  `pendingRunID` is **never read by production code** (only tests
  `WatchChecklistStoreTests.swift:62,94`) — there is no retry and no delivery
  observation (`didFinish` is not implemented; the delegate is `:37-50`).
- **Candidate sends drop window**: any send issued before async activation
  completes is dropped (`ChecklistSync.swift:54-57,83-85`). The `.task {
  requestRefresh() }` in `WatchChecklistListView.swift:30-31` races activation;
  the reliable refresh comes from `onActivated` (`ChecklistSync.swift:82-87`).
- **Phone receive**: `PhoneSyncAdapter.swift:70-73` decodes
  `ChecklistSyncMessage(userInfo:)` (drop on `nil`, `:71`) and funnels to
  `onMessage` via a `Task { @MainActor }` (`:72`). Wiring is lazy inside a
  SwiftUI `.task` (`MyApp.swift:63-67`); there is no launch-time WCSession setup
  (`AppDelegate.swift:24-26` has no `didFinishLaunching`/session hook), so the
  inbound async-activation drop window applies here too.
- **Silent drop gates (≥5)**: decode failure (`ChecklistSync.swift:19-31` +
  `PhoneSyncAdapter.swift:71`); `self` nil in the weak capture (`:72`);
  `onMessage` nil before `coordinator.start()` (`ChecklistSyncCoordinator.swift:34`);
  `isSupported()` false (`PhoneSyncAdapter.swift:28`); and the coordinator's
  snapshot-ID guard (`ChecklistSyncCoordinator.swift:40`).
- **Coordinator**: `.runChecklist` looks the id up in `snapshot()`
  (`ChecklistSyncCoordinator.swift:38-48`); a miss is a **silent return**
  (`:40`). Hits chain a serialized `pendingRun: Task<Void, Never>`
  (`:42-47,57`) — the documented EKCADErrorDomain 1021 workaround
  (`:41`) — but `Task<Void, Never>` and a `(Checklist) async -> Void` closure
  (`:10`) cannot carry an error.
- **Outcome discarded**: `MyApp.swift:67` wires `createReminders` to
  `ChecklistReminders.create(from:)`, which returns `ReminderRunOutcome`
  (`.permissionDenied`/`.destinationMissing`/`.failed`/`.created(count:)`,
  `ChecklistReminders.swift:15-35`). The closure returns `Void`, so **every
  outcome is thrown away**; `.failed` logs (`ChecklistReminders.swift:27`);
  `.permissionDenied`/`.destinationMissing` are not even logged.
- **No return channel**: the coordinator only calls `sendContext`
  (`ChecklistSyncCoordinator.swift:33-35`); `PhoneSyncAdapter.sendUserInfo`
  (`PhoneSyncAdapter.swift:39-43`) has **zero call sites**. The watch's `receive`
  handles only `.context`; `.runChecklist`/`.requestChecklists` are `break`
  (`ChecklistSync.swift:106-116`).
- **Why the watch can hold a stale id**: context is latest-state-wins
  (`ChecklistSync.swift:14`) and re-pushed only on observable store change or an
  explicit `requestChecklists` (`ChecklistSyncCoordinator.swift:37-38`); the
  `start()` push is dropped pre-activation; KVS reconciles mutate the phone
  snapshot (`ChecklistSyncService.swift:44-51`); tombstones are omitted from the
  envelope (`ChecklistStore.swift:382-398`, `Checklist.swift:268-283`).
- **Root cause is not yet located** — research is explicit that no amount of
  code reading decides which gate fires; the drop points are observationally
  identical from the outside.

## Desired End State

1. **The root cause is identified with evidence** from a real paired watch/phone:
   os-log records show, for one tap, the watch's activation state at send time,
   whether the phone's `didReceiveUserInfo` fires, whether `.runChecklist` enters
   `handle`, the snapshot membership of the id, and the final `ReminderRunOutcome`.
2. **The user-visible bug is fixed.** Tapping Create reminders on the watch
   results in reminders in the phone's Reminders app; if it cannot, the watch
   says so instead of claiming success.
3. **Feedback is honest.** The watch button is `Sending…` while in flight and
   shows `Created` only after the phone confirms creation; on failure it shows a
   short reason and re-enables for retry. No state reaches the user that is not
   backed by a phone-side result.
4. **Silent drops are gone on the run path.** An unknown/stale id triggers a
   phone→watch "not found, refreshing" result plus a fresh context push, not a
   bare `return` (`ChecklistSyncCoordinator.swift:40`).
5. **A run survives the activation race and a non-running phone.** A pending run
   is retained and re-sent when the session becomes usable, and cleared only on a
   confirmed result.
6. **Verification is on-device**: `bash scripts/run-watch.sh` installs/launches
   and the end state is stated as what the user must see (AGENTS.md: sync tickets
   cannot close on static evidence). Unit tests cover the new state machine with
   fakes; `./scripts/test.sh` is the gate.

## Patterns to Follow

- **Seam-first, Core-owned**: the watch's logic lives in `CheckStitchCore`
  (`WatchChecklistStore` in `ChecklistSync.swift:70-91`) behind a transport
  protocol (`ChecklistSyncing`), so the new send/ack state machine is testable
  with `FakeChecklistSyncTransport` (`TestFixtures.swift:149-177`) — follow this,
  do not put logic in `WatchChecklistDetailView`.
- **Message codec as a closed enum** (`ChecklistSyncMessage`,
  `ChecklistSync.swift:19-36`): add the new phone→watch result case here and
  extend `ChecklistSyncMessageTests.swift` with round-trip + unknown-key
  rejection (`:7,11,15,19,23`), matching the existing pattern.
- **Single `EKEventStore` discipline**: keep creation on the coordinator closure
  with `EventKitReminderDestination.shared` and the serialized `pendingRun`
  chain (`ChecklistSyncCoordinator.swift:40-47`, `PhoneSyncAdapter.swift:8-9`) —
  the 1021 workaround is load-bearing; do not parallelize runs.
- **Serialized-run chaining is the correct pattern** (`ChecklistSyncCoordinator.swift:42-47`);
  extend it to carry an outcome (e.g. a `Task<Void, Outcome>` or a continuation)
  rather than replacing it.
- **Panic-free seams**: `ChecklistReminders.create` returns an
  `Outcome` value rather than throwing (`ChecklistReminders.swift:15-35`) — put
  the new result on that value; do not introduce a throwing path.
- **`activationDidCompleteWith`/`onActivated` is the reliable timer**, not
  `.task` (`ChecklistSync.swift:82-87`, `WatchChecklistListView.swift:30-31`):
  re-send/resend-on-activate must hang off `onActivated`, the pattern the code
  already uses for refresh.
- **`Sendable`/`@MainActor` conventions**: watch store is `@MainActor`
  (`ChecklistSync.swift:70`), suites opt in with `@MainActor` and use Swift
  Testing `@Test`/behaviour names (conventions.md) — match that.
- **Avoid**: the `onMessage`-installed-in-`.task` startup (`MyApp.swift:63-67`)
  and the ignored `error:` param in `WatchSyncAdapter.swift:37-45` are the
  anti-patterns that created this bug; do not extend them. Do not add logic that
  reports success from a transport `Bool`.
- **Do not rely on `sendUserInfo`'s `Bool`** as a delivery signal anywhere new
  (`WatchSyncAdapter.swift:29-30` is the cautionary example).

## Design Decisions

1. **Instrument-first, then fix**: add a dedicated `Logger` subsystem with one
   log per gate on both targets, run the device spike, read the logs, then
   implement the fix chosen by the evidence. The alternative (fix every gate
   blindly) risks shipping a non-fix and cannot demonstrate the bug is closed.
2. **Honest three-state watch feedback (Q2A)**: `pendingRunID` graduates from
   write-only to the source of truth; the button shows `Sending…` → `Created` /
   failure, driven by a new phone→watch result message, not by
   `transferUserInfo` acceptance.
3. **Phone recovers on unknown id (Q3A)**: replace the bare `return` at
   `ChecklistSyncCoordinator.swift:40` with a `notFound` result to the watch plus
   a fresh `pushContext()`, so the watch self-corrects instead of showing a run
   that never happened.
4. **Retain-and-resend (Q4A)**: keep the pending run and re-issue it from
   `onActivated`/context arrival; clear only on a confirmed phone result. This
   covers the activation race and a phone that is not running.
5. **Phone→watch channel reuses `transferUserInfo`/`sendUserInfo`** on
   `PhoneSyncAdapter.sendUserInfo` (`PhoneSyncAdapter.swift:39-43`, currently
   zero call sites) + a watch-side receive case, rather than inventing a second
   transport; keep `.context` (applicationContext) as the state channel and add
   `.runResult` as the event channel.
6. **One ticket, no child tickets**: instrumentation, root-cause fix, feedback,
   stale-id recovery and resend all land here, per the step instructions.
7. **Scope the fix to the located root cause**: decisions 2–4 are the *class*
   fix for the silent-drop family, but if the spike shows the failure is e.g.
   phone permissions or destination-missing, that specific fix is the primary
   deliverable and the others are the safety net — decide after the spike, not
   before.

## What We're NOT Doing

- **Not touching EventKit creation semantics**: no change to
  `ChecklistReminders.create`, destination resolution, `save(commit: true)`, or
  the 1021 serialization beyond carrying an outcome out of the closure
  (`ChecklistReminders.swift`, `EventKitReminderDestination.swift`).
- **Not adding a second transport** (CloudKit, direct KVS run queue, push
  notifications) — WCSession is the seam; we make its failures visible and
  recoverable.
- **Not rewriting the context/refresh model** (`updateApplicationContext`
  latest-state-wins) — only the unknown-id recovery and tombstone-awareness
  needed for correctness of the run path.
- **Not building real-WCSession automation**: both adapters stay app-target-only
  (conventions.md); the new logic is tested through fakes, and real delivery is
  verified by the device spike, as the repo already does.
- **Not changing the phone in-app Run path** (`ContentView.swift:347-383`) or
  its alert (`:156-164`) except where it shares the coordinator seam.
- **Not adding UI beyond the watch button states** needed for decision 2 —
  no settings screen, no run history.
- **Not filing child tickets**; follow-ups (if any) are notes for future tickets.

## Open Risks

- **The spike may not reproduce.** If logs are clean end-to-end on hardware, the
  failure may be environmental (paired-device state, app not installed on the
  phone, Reminders permission never granted) — decision 7 covers this, but the
  design must be revisited rather than "fixing" healthy code.
- **`transferUserInfo` delivery semantics are OS-owned** (research Open Areas):
  we can make the watch honest and retry, but cannot guarantee delivery timing;
  background-wake behavior of the phone is out of repo control.
- **Result-message loss**: a phone→watch result can itself be dropped (same
  activation race). Mitigation: the watch's pending run is only cleared on
  result, and re-send on activation means a lost result eventually re-runs —
  which risks **duplicate reminders**, since neither side is idempotent. Needs a
  run id / de-dup key (watch does not currently send one; `Checklist.id` is the
  closest but a checklist can legitimately be run twice). Consider whether the
  `runChecklist` message must gain a per-run UUID.
- **Serialized-queue outcome plumbing**: `Task<Void, Never>` (`:42-47`) must
  become outcome-carrying; done wrong it could reintroduce the 1021 overlap the
  chain exists to prevent.
- **Watch-only testability**: `WatchChecklistStore` and the new result-handling
  logic must stay in `CheckStitchCore` to be unit-tested at all
  (`WatchChecklistStoreTests.swift`), or coverage silently disappears.
- **Test target's actor isolation**: suites must not set
  `SWIFT_DEFAULT_ACTOR_ISOLATION`; opt in with `@MainActor` (AGENTS.md,
  conventions.md) — a new suite that forgets this will fail the gate confusingly.
