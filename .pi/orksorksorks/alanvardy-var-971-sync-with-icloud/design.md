# Design Discussion

## Current State

**Models carry identity but no sync state.** `Checklist` and `ChecklistItem` live
only in the app target (`CheckStitch/Checklist.swift:6-28`) and are
`Identifiable, Codable, Hashable` with a single `let id: UUID` and no revision,
timestamp, tombstone, or external identifier. The core copy
(`CheckStitchCore/Sources/CheckStitchCore/ChecklistItem.swift:7-20`) is the same
shape. The only versioning anywhere is the wire envelope's `version`
(`Checklist.swift:31-34`, `currentVersion = 1` at `:38`).

**One persistence owner, one key.** `ChecklistStore` (`CheckStitch/ChecklistStore.swift:5`)
is the sole source of truth, injected with `defaults: UserDefaults = AppGroup.defaults`
and `key = "checklists.v1"` (`:16-23`). `AppGroup.swift:6-10` is the shared suite
`group.app.alanvardy.CheckStitch`. Load in `init` (`:25-41`) sets
`canOverwriteStoredPayload = false` on `.unsupportedVersion`; structural mutations
save immediately (`:47-92`), text edits debounce through `scheduleSave` (`:103-115`)
and `flushPendingSave` (`:96-101`) is called on scene-phase exit (`MyApp.swift:36,45`)
and detail-view disappear (`ChecklistDetailView.swift:61`). `save` (`:117-133`)
refuses to overwrite a newer payload. Deletion is a whole-array re-encode; there is
no per-key delete, and `:87-88` documents that reminders already created are never
touched.

**Reminders is a one-way export, not a store.** `ChecklistReminders.create(from:)`
(`CheckStitch/ChecklistReminders.swift:4-28`) builds a fresh `EKEventStore()` per
call (`:11`), calls `requestFullAccessToReminders()`, then per non-blank item does
`EKReminder` + `defaultCalendarForNewReminders()` + `save(commit: true)` (`:18-21`)
— i.e. the "inbox"/default list. The core seam
(`CheckStitchCore/Sources/CheckStitchCore/ReminderCreating.swift:6-38`) has the
opposite doctrine (one long-lived store, `:11-21`) and is **test-only**: no
production code constructs `AppEnvironment`/`EventKitReminderCreator`
(`MyApp.swift:33-46` injects only `store`). Nothing in either project ever *reads*
Reminders (research.md Q2). Reminders is therefore **not** the sync medium — the
user runs a checklist and reminders appear in the inbox as a side effect.

**No sync infrastructure exists.** No iCloud/CloudKit/ubiquity entitlement or
container in either project (research.md Q6, `CheckStitch/AppGroup.entitlements:1-11`).
**No refresh surface exists** either: no `.refreshable` anywhere in app or core; the
only state-update mechanisms are `@Observable` mutations, per-keystroke bindings,
`flushPendingSave`, nav push/pop, and `.onChange(of: appearanceMode)`
(`ContentView.swift:47-53`).

**Test seam pattern is established.** EventKit is never mocked; behaviour is tested
through a protocol + spy (`ReminderCreating` / `SpyReminderCreator`,
`TestFixtures.swift:29-51`), with the real adapter only as a construction canary
(`EventKitReminderCreatorTests.swift:13-15`). UserDefaults tests isolate suites via
`makeIsolatedDefaults` (`TestFixtures.swift:10-16`).

## Desired End State

The set of checklists **and** their items round-trips across devices through the
user's iCloud account. Reminders creation is unchanged and remains a local,
per-device export into the inbox. The local `ChecklistStore` survives as the
offline cache and the UI's write path. `ContentView` gains a pull-to-refresh that
force-reconciles sync state, and sync failures are surfaced rather than swallowed.

Verifiable by: unit tests over an in-memory sync fake covering merge, tombstone,
migration and reconcile; the real adapter as a construction canary; the existing
`make test-unit` and `bash scripts/test.sh` gate (conventions.md) staying green; a
manual two-device check on the pinned simulator.

## Patterns to Follow

- **Protocol + fake seam**: mirror `ReminderCreating` (`ReminderCreating.swift:6-38`)
  with `SpyReminderCreator` (`TestFixtures.swift:29-51`) for a new `ChecklistSyncing`.
  Real adapter gets a construction canary only, as in `EventKitReminderCreatorTests.swift:13-15`.
- **Versioned envelope + classify**: extend the existing `ChecklistEnvelope` /
  `classify` design (`Checklist.swift:31-75`) rather than inventing a second codec.
- **Never-overwrite-newer guard**: preserve the `canOverwriteStoredPayload` contract
  (`ChecklistStore.swift:25-41`, `:117-133`) — sync must not become a back door that
  clobbers a payload written by a newer app version.
- **Outcome enum over thrown errors**: follow `ChecklistCreationOutcome`
  (`ChecklistCreator.swift:5-8`) and its UI consumption (`ChecklistViewModel.swift:19-40`,
  `ContentView.swift:193-210`) for `SyncOutcome`.
- **Debounce + flush**: extend the existing `scheduleSave`/`flushPendingSave` shape
  (`ChecklistStore.swift:96-115`) to also schedule a cloud push; reuse the
  scene-phase flush points (`MyApp.swift:34-45`) to push before backgrounding.
- **Test isolation**: any new defaults-touching suite uses `makeIsolatedDefaults`
  (`TestFixtures.swift:10-16`); suites touching platform state are `@MainActor`,
  because test targets deliberately have no default actor isolation
  (conventions.md, Makefile:35-37).

**Patterns NOT to follow**: the app-target `ChecklistReminders` fresh-`EKEventStore`-
per-call style (`ChecklistReminders.swift:11`) contradicts the core doctrine
(`ReminderCreating.swift:11-21`) — leave it alone, it is out of scope. Also do not
copy the "core seam exists but nothing wires it in production" gap
(`MyApp.swift:33-46`); the new sync seam must actually be constructed in `MyApp`.

## Design Decisions

1. **Sync medium: `NSUbiquitousKeyValueStore`, now, behind a seam.** The existing
   JSON envelope is written to one KVS key (`checklists.v1`). One entitlement
   (`com.apple.developer.ubiquity-kvstore-identifier`), no iCloud container to
   provision. KVS's own per-key last-writer-wins is never relied on — we read,
   merge ourselves, and write back. Documented migration path to CloudKit private
   DB (one record per checklist, server-side `recordChangeTag` conflicts) if the
   payload approaches the 1 MB / 1024-key limits.
2. **New cloud seam in CheckStitchCore, not EventKit.** `protocol ChecklistSyncing`
   (`read() -> Data?`, `write(Data)`, plus a change-observation hook) with
   `UbiquitousChecklistSync` as the real adapter and `InMemoryChecklistSync` for
   tests. EventKit is untouched by this ticket; the task's "EventKit seam" wording
   is superseded because Reminders is only an export.
3. **Local store stays the write path and cache** (5a). Sync never writes
   `UserDefaults` directly; it reconciles into `ChecklistStore` through one
   `apply(remote:)` entry point, and the store remains the only encoder. This keeps
   the `canOverwriteStoredPayload` guard intact and keeps the app usable with iCloud
   signed out or KVS unavailable.
4. **Schema v2: per-item `modifiedAt` + `revision`, tombstones, and a device id.**
   `Checklist` and `ChecklistItem` gain `modifiedAt: Date`, `revision: Int`, and
   `deletedAt: Date?`; the payload also carries a stable per-install `deviceID` used
   only as a deterministic tie-break. `ChecklistCodec.currentVersion` becomes `2`,
   and `classify` gains a `.migratable(from: 1)` case that upgrades v1 checklists
   by stamping `modifiedAt`/`revision` rather than rejecting them as
   `.unsupportedVersion` (`Checklist.swift:56-69`, which today would leave
   `canOverwriteStoredPayload = false` and stall migration).
5. **Conflict resolution: item-level last-writer-wins.** Merge by `UUID`: higher
   `revision` wins; equal revision falls back to `modifiedAt`, then `deviceID` as a
   deterministic tie-break. Checklist-level metadata (name, ordering, tombstone)
   merges the same way; items union by id so a checklist edited on two devices
   keeps both edits.
6. **Deletes propagate as tombstones.** A checklist or item removed locally gets
   `deletedAt` set, not dropped, so "absent from the remote payload" is never
   confused with "deleted on another device". Tombstoned entries win over
   concurrent edits and are merged like any other change. **Reminders already
   created in the inbox are never touched** (`ChecklistStore.swift:87-88`).
7. **Triggers: automatic plus manual** (7a). Push after local mutation (debounced
   through the existing `scheduleSave` window), reconcile on app foreground, and
   reconcile on the KVS external-change notification
   (`NSUbiquitousKeyValueStore.didChangeExternallyNotification`) — the analogue of
   SingleThread's `EventStoreChangedObserver` (`EventStoreChangedObserver.swift:16-38`).
   Pull-to-refresh forces `synchronize()` then a full reconcile. Concurrent syncs
   are coalesced by a single in-flight task.
8. **First sync is a seeding migration** (4a): cloud empty → upload the local
   payload; local empty, cloud non-empty → download; both non-empty → merge under
   the 3B rules. The migration runs once, gated on a `didSeedCloud` flag, and never
   discards local data it could not classify.
9. **UI surface**: `.refreshable` on `ContentView`'s checklist `List`
   (`ContentView.swift:18-21` branch), driving a `SyncOutcome`-backed `isSyncing`
   flag and an error banner; the view model gain is minimal since `ContentView`
   already owns the `creating`/`created` per-row feedback pattern
   (`ContentView.swift:168-185`, `:193-210`).
10. **Entitlement/configuration**: add `ubiquity-kvstore-identifier` to
    `CheckStitch/AppGroup.entitlements` and the `CODE_SIGN_ENTITLEMENTS[sdk=...]`
    wiring in `project.pbxproj` (`:402-403`, `:444-445`); `DEVELOPMENT_TEAM =
    6NWX2DHB9Q` is unchanged. No container identifier is needed. Unit tests must
    never touch `NSUbiquitousKeyValueStore.default`.

## What We're NOT Doing

- No checklist↔Reminders-list mapping; no changes to `ChecklistReminders`,
  `ReminderCreating`, `ChecklistCreator`, or how/where reminders are created.
- No deletion or modification of reminders already created.
- No CloudKit this ticket (the seam and merge layer leave room for it).
- No conflict-resolution UI, no per-field merge, no three-way merge.
- No push notifications, background refresh, or `BGTaskScheduler`.
- No server, no accounts beyond the device's iCloud login.
- No read-back of Reminders into the app.
- No fixes to the pre-existing `AppEnvironment`/`EventKitReminderCreator` wiring gap
  or the duplicate app-target reminder path.
- No new child tickets; all work lands on the main ticket.

## Open Risks

- **KVS limits and latency**: 1 MB total / 1024 keys, and no dependable "force a
  pull" API — `synchronize()` is effectively deprecated guidance. Pull-to-refresh
  may therefore feel like a no-op on a healthy connection; the UI must not claim
  more than "reconciled with the last known remote state".
- **Tombstone growth** has no GC policy yet; without one the payload trends toward
  the 1 MB ceiling. Bounded retention is a follow-up decision.
- **Clock skew** across devices makes `modifiedAt` the weakest part of the merge;
  `revision` is the primary key deliberately, with `modifiedAt` only a tie-break.
- **Torn writes**: KVS gives no atomic multi-key write, so the whole envelope must
  always be written as one value and validated (envelope `version` + integrity
  check) on read before merging.
- **Entitlement provisioning**: the ubiquity key-value store identifier must be
  present in the provisioning profile; `-allowProvisioningUpdates` may be needed on
  machines without it (conventions.md, signing gotchas).
- **macOS `build-mac` is unsigned** (`CODE_SIGNING_ALLOWED=NO`, Makefile:24-30), so
  the macOS leg of the gate cannot exercise KVS — unit tests must go through
  `InMemoryChecklistSync` only.
- **Migration correctness for v1 payloads** is the highest-risk path: a bad upgrade
  could trip `canOverwriteStoredPayload = false` and leave a user unable to save.
  The reproducing test comes before the fix (repo AGENTS.md testing rule).