# Structure Outline

## Approach

Grow a new, fully-tested sync stack behind the existing local store without touching
EventKit: **schema v2 → Data-only KVS transport seam (Core) → pure merge engine →
store reconciliation → sync coordinator wired in `MyApp` → pull-to-refresh UI.**
`ChecklistStore` stays the only encoder and the UI's write path; sync reaches it
through one `apply(remote:)` entry point, preserving the `canOverwriteStoredPayload`
guard. Every stage ships its tests and is green before the next begins.

**Two structural refinements of `design.md` (flagged, not silent):**
1. **The seam lives in `CheckStitchCore`; the persisted model + merge stay in the app
   target.** The seam is `Data`-in/`Data`-out so it needs no model type, and Core
   already owns a *different* `ChecklistItem` (`ChecklistItem.swift`, used by
   `ChecklistCreator`). Moving `Checklist`/`ChecklistCodec` into Core would be a
   cross-cutting refactor with a name collision, unrelated to the sync goal. Tests
   reach app-target types via `@testable import CheckStitch` (as `ChecklistStoreTests`
   already does).
2. **Tombstones are a separate persisted collection, not a `deletedAt` field on the
   models.** Design decision 4's intent (deletes propagate, never conflated with
   "absent remotely") is kept, but the UI iterates `checklist.items` and
   `store.checklists` directly (`ChecklistDetailView.swift:20`, `ContentView.swift:18,125`).
   Inline `deletedAt` would force visible-vs-indexed filtering through `.onDelete`
   offsets. A `[ChecklistTombstone]` keeps `items`/`checklists` meaning exactly what
   they mean today, so Stage 4 needs **zero** UI index changes.

## Stage 1: Schema v2 & migration

Adds revision/timestamp identity to the persisted payload and teaches the codec to
upgrade v1 in place instead of rejecting it. Green tests prove a v1 payload becomes a
savable v2 payload and a v3 payload is still refused.

**Files**: `CheckStitch/Checklist.swift`, `CheckStitch/ChecklistStore.swift`,
`CheckStitchTests/ChecklistCodecTests.swift`, `CheckStitchTests/ChecklistStoreTests.swift`,
`CheckStitchTests/TestFixtures.swift`

**Key changes**:
- `Checklist`, `ChecklistItem` gain `var modifiedAt: Date`, `var revision: Int` (Codable defaulted so v1 JSON decodes)
- `struct ChecklistTombstone: Codable, Hashable { let checklistID: UUID; let itemID: UUID?; var deletedAt: Date; var revision: Int }`
- `ChecklistEnvelope { version, deviceID: String, checklists: [Checklist], tombstones: [ChecklistTombstone] }`
- `ChecklistCodec.currentVersion = 2`; `encode(_:deviceID:tombstones:) throws -> Data`
- `ChecklistCodec.Outcome` gains `.migratable(from: Int, deviceID: String)` (v1) and `.loaded(ChecklistEnvelope)`; classify version-probes before decoding
- `ChecklistStore.init(defaults:key:textEditDelay:now: @escaping () -> Date = Date.init)`; persists `deviceID` under `checklist.deviceID`; on `.migratable` stamps `modifiedAt`/`revision = 1`, empty tombstones, keeps `canOverwriteStoredPayload = true`

**Tests**: `ChecklistCodecTests` round-trip v2, v1→`.migratable`, v3→`.unsupportedVersion`, garbage→`.unreadable`; `ChecklistStoreTests` v1 payload migrated **and** savable afterwards (regression for the stalled-migration risk), v3 payload still refuses save.
**Verify**: `make test-unit` green for the codec + store suites.

---

## Stage 2: Sync transport seam (`ChecklistSyncing`)

One narrow seam over `NSUbiquitousKeyValueStore`, mirrored on `ReminderCreating` /
`SpyReminderCreator`; the real adapter is canaried, never exercised.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncing.swift` (new),
`CheckStitch/AppGroup.entitlements`, `CheckStitchTests/TestFixtures.swift`,
`CheckStitchTests/UbiquitousChecklistSyncTests.swift` (new)

**Key changes**:
- `@MainActor public protocol ChecklistSyncing { func read() -> Data?; func write(_ data: Data); func synchronize(); @discardableResult func startObserving(_ onChange: @escaping () -> Void) -> any ChecklistSyncObservation }`
- `public protocol ChecklistSyncObservation { func cancel() }`
- `@MainActor public final class UbiquitousChecklistSync: ChecklistSyncing { public init(store: NSUbiquitousKeyValueStore = .default, key: String = "checklists.v1") }` — one long-lived store, observes `didChangeExternallyNotification`
- `TestFixtures.swift`: `InMemoryChecklistSync` — seeded `stored`, recorded `written`, `synchronizeCount`, `fireExternalChange()`
- `AppGroup.entitlements`: add `com.apple.developer.ubiquity-kvstore-identifier = $(TeamIdentifierPrefix)app.alanvardy.CheckStitch` (existing pbxproj wiring already points at this file)

**Tests**: construction canary for `UbiquitousChecklistSync` (no KVS API called); fake read/write records bytes, observer fires, `synchronize` counts. Unit tests must never touch `NSUbiquitousKeyValueStore.default`.
**Verify**: `make test-unit` and `make build-mac` (unsigned macOS leg must still build) green.

---

## Stage 3: Merge engine (pure)

A dependency-free function that reconciles two envelopes under item-level LWW and
tombstone rules — the highest-risk logic, tested with no store, no seam, no I/O.

**Files**: `CheckStitch/ChecklistMerge.swift` (new), `CheckStitchTests/ChecklistMergeTests.swift` (new)

**Key changes**:
- `enum ChecklistMerge { static func merge(local: ChecklistEnvelope, remote: ChecklistEnvelope) -> ChecklistEnvelope }`
- Winner rule `(revision, modifiedAt, deviceID)`: higher revision, then newer `modifiedAt`, then deterministic device-id tie-break
- Tombstones union by `(checklistID, itemID)`; a tombstone always suppresses its live entry (design decision 6)
- Checklists union by `UUID` (local order kept, remote-only appended); items union by `UUID` so concurrent edits on different items both survive

**Tests**: local/remote disjoint union; higher revision wins; equal revision + `modifiedAt` tie break by deviceID; tombstoned checklist/item never resurrected; item-level edits from both devices preserved; identical envelopes are a no-op.
**Verify**: `make test-unit` green for `ChecklistMergeTests`.

---

## Stage 4: Store reconciliation & tombstones

Makes `ChecklistStore` the sync write target: every mutation stamps revision and
persists tombstones for deletes, and one `apply(remote:)` merges without ever
bypassing the newer-payload guard.

**Files**: `CheckStitch/ChecklistStore.swift`, `CheckStitchTests/ChecklistStoreTests.swift`

**Key changes**:
- `private(set) var tombstones: [ChecklistTombstone]`
- `var envelope: ChecklistEnvelope` — current payload + own `deviceID`, the only encoder entry point
- `func apply(remote: ChecklistEnvelope) -> Bool` — merges via `ChecklistMerge`, replaces local state, saves, returns whether visible state changed; **no-ops and returns `false` when `canOverwriteStoredPayload == false`**
- Mutations (`create`/`rename`/`addItem`/`updateItem`/`removeItems`/`delete`) bump `revision` + stamp `modifiedAt`; `delete`/`removeItems` append tombstones instead of dropping rows
- `var onChange: (() -> Void)?` invoked after each persisted save

**Tests**: revisions increment and timestamps advance per mutation; delete/removeItems leave tombstones and remove live rows; `apply` merges remote edits, propagates remote tombstones, is idempotent on repeat, and is refused (no save, no state change) on an unsupported-version payload; `envelope` round-trips through `ChecklistCodec`.
**Verify**: `make test-unit` green for the store suite; existing `ChecklistStoreTests` cases (reload, corrupt repair, flush) still pass unchanged.

---

## Stage 5: Sync coordinator & app wiring

The only stage that joins store and seam: first-sync seeding, coalesced push, foreground
and external-change reconcile, and a surfaced `SyncOutcome`. Wired in production so the
seam cannot repeat the `AppEnvironment` dead-code gap.

**Files**: `CheckStitch/ChecklistSyncService.swift` (new), `CheckStitch/MyApp.swift`,
`CheckStitchTests/ChecklistSyncServiceTests.swift` (new)

**Key changes**:
- `enum SyncOutcome: Equatable, Sendable { case synced, seeded, unavailable, failed(String) }` (shaped after `ChecklistCreationOutcome`)
- `@MainActor @Observable final class ChecklistSyncService { init(sync: any ChecklistSyncing, store: ChecklistStore, defaults: UserDefaults = AppGroup.defaults, pushDelay: Duration? = .milliseconds(500)); private(set) var isSyncing: Bool; private(set) var lastOutcome: SyncOutcome? }`
- `func start()` (observer + initial reconcile), `func syncOnLaunch() async`, `func reconcile() async`, `func refresh() async -> SyncOutcome`, `func pushNow()`, `func schedulePush()`
- Seeding gated on `checklist.sync.didSeedCloud`; unclassifiable local payload is never discarded
- `MyApp`: construct service, inject `.environment(syncService)`, `.task { await syncService.syncOnLaunch() }`, and on `phase != .active` call `store.flushPendingSave(); syncService.pushNow()`

**Tests**: cloud-empty → local seeded, flag set, once only; local-empty → remote applied; both non-empty → merge path; `read()` failure → `.unavailable`; write failure → `.failed` surfaced; concurrent `refresh()` calls coalesce into one in-flight reconcile; `.unreadable` remote is ignored; observer callback triggers reconcile.
**Verify**: `make test-unit` green for the service suite; `make build` still compiles the app with the service wired in.

---

## Stage 6: Pull-to-refresh UI

The user-visible surface: `.refreshable` driving a real reconcile, plus honest feedback
for in-flight and failed syncs. No view-model change — `ContentView` already owns the
per-row `creating`/`created` feedback pattern the design points at.

**Files**: `CheckStitch/ContentView.swift`, `CheckStitchTests/ViewRenderTests.swift`,
`CheckStitchUITests/CheckStitchUITests.swift`

**Key changes**:
- `@Environment(ChecklistSyncService.self)` in `ContentView`
- `.refreshable { await syncService.refresh() }` on the checklist `List` branch (`ContentView.swift:18-21`)
- in-flight indicator from `isSyncing`; failure banner from `lastOutcome == .failed`, matching the existing `created`-row idiom

**Tests**: render tests for banner absent on `.synced` and present on `.failed`, and indicator on `isSyncing`; existing UI smoke unchanged (one-shot `make test-ui`).
**Verify**: `bash scripts/test.sh` prints `gate: ok`; manual check on two devices signed into one iCloud account (simulator + physical device) — add/rename/delete a checklist and an item on device A, pull-to-refresh on device B, confirm round-trip and that no Reminders are created or removed.

---

## Testing Checkpoints

After **each** stage: `make test-unit` must be green before starting the next stage.
- After Stage 1 → codec/store suites green; v1 payloads still load and save.
- After Stage 2 → seam fake + canary green; `make build-mac` green.
- After Stage 3 → merge suite green (pure, no I/O).
- After Stage 4 → store suite green, including unchanged legacy cases.
- After Stage 5 → service suite green and app builds with the service constructed in `MyApp`.
- After Stage 6 → `bash scripts/test.sh` prints `gate: ok`; manual two-device round-trip verified.