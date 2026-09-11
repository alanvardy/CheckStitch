# Structure Outline

## Approach
Extract a Codable `Checklist` collection into an `@Observable` `ChecklistStore`
backed by the App Group `UserDefaults` suite, then rebuild `ContentView` as a
`NavigationStack` list that drives a renamed `ChecklistDetailView`. Built
bottom-up: pure model → persistence store → EventKit service → detail screen →
list screen + wiring. Each layer compiles, passes the gate, and is verified
before the layer above starts.

## Test strategy (decided)
**Add a minimal `CheckStitchTests` XCTest target scoped to Stages 1–2**
(Codable/versioning/CRUD — the actual bug surface). Stages 3–5 are EventKit/UI
and stay on the repo gate (`./scripts/test.sh` = build + shellcheck) plus
simulator manual checks. This supersedes `design.md`'s "no test target"
non-goal; it is a deliberate scope addition for this ticket, not a general
convention change.

Consequences to carry into Plan:
- The new target **does** require a `project.pbxproj` edit (the
  `PBXFileSystemSynchronizedRootGroup` exemption covers sources under
  `CheckStitch/`, not a new target/product). Add the target, a
  `CheckStitchTests/` bundle, and the host-app linking in Stage 1.
- `scripts/test.sh` gains an `xcodebuild test` step **after** `make build`, so
  `gate: ok` only prints when both build and the unit suite are green. This is
  the gate change that makes every later stage's checkpoint meaningful.
- Tests must not hit the real App Group suite: construct
  `UserDefaults(suiteName: "test.<uuid>")!` per test and
  `removePersistentDomain(forName:)` in `tearDown`.

---

## Stage 1: Model + App Group accessor
Pure value types and the suite accessor. Green here proves the persisted shape
encodes/decodes and version-mismatch is handled without crashing.

**Files**: `CheckStitch/AppGroup.swift` (new), `CheckStitch/Checklist.swift`
(new; `ChecklistItem` moves out of `ContentView.swift`),
`CheckStitchTests/ChecklistCodecTests.swift` (new), `CheckStitch.xcodeproj/project.pbxproj`,
`scripts/test.sh`

**Key changes**:
- `enum AppGroup { static let suiteName = "group.app.alanvardy.CheckStitch"; static var defaults: UserDefaults }`
- `struct Checklist: Identifiable, Codable, Hashable { let id: UUID; var name: String; var items: [ChecklistItem] }` — new
- `struct ChecklistItem: Identifiable, Codable, Hashable { let id: UUID; var title: String }` — moved; add `Codable`/`Hashable`
- `struct ChecklistEnvelope: Codable { var version: Int; var checklists: [Checklist] }` — new; `version: 1`
- `static func decode(_ data: Data) -> [Checklist]` — unknown version → `[]` + log (consumed by Stage 2)
- New `CheckStitchTests` unit-test target (host = CheckStitch, iOS 18.7); `scripts/test.sh` gains `xcodebuild test` after `make build`

**Tests**: `ChecklistCodecTests` — `testEnvelopeRoundTrip`, `testUnknownVersionDecodesAsEmpty` (sad), `testEmptyEnvelopeDecodes`
**Verify**: `./scripts/test.sh` prints `gate: ok` (now build **and** the codec suite); `xcodebuild test` green in isolation

---

## Stage 2: Persistence store
An observable store owning `[Checklist]`, reading/writing the suite on every
mutation. Green here proves persistence and delete semantics without any UI.

**Files**: `CheckStitch/ChecklistStore.swift` (new),
`CheckStitchTests/ChecklistStoreTests.swift` (new)

**Key changes**:
- `@Observable final class ChecklistStore { init(defaults: UserDefaults = AppGroup.defaults, key: String = "checklists.v1") }`
- `private(set) var checklists: [Checklist]` — loaded on init (corrupt/absent → `[]`)
- `func checklist(id: UUID) -> Checklist?`
- `func create() -> Checklist` — append empty, `save()`, return for push
- `func rename(id: UUID, to name: String)`, `func addItem(to id: UUID)`, `func updateItem(checklistID: UUID, itemID: UUID, title: String)`, `func removeItems(from id: UUID, at offsets: IndexSet)`
- `func delete(id: UUID)` — local only; **never** touches EventKit
- `private func save()` / `private func load()` — envelope encode/decode, read-modify-write per mutation
- Consumed by Stages 3–5 (detail view + list view hold it via `@Environment`)

**Tests**: `ChecklistStoreTests` against `UserDefaults(suiteName: "test.<uuid>")!` (domain removed in `tearDown`) — `testCreatePersistsAcrossReload`, `testRenamePersists`, `testAddAndRemoveItemPersists`, `testDeleteRemovesOnlyTarget`, `testDeleteUnknownIDIsNoOp` (sad), `testCorruptDataYieldsEmpty` (sad)
**Verify**: gate green; suite green in isolation (fresh `UserDefaults` per test, no cross-test bleed)

---

## Stage 3: Reminders service
Lift the EventKit flow out of the view into one testable-at-the-edge function
that takes a `Checklist`. Behavior is unchanged: full access, skip blanks,
inbox calendar, `commit: true`, static logger, one `EKEventStore` per call kept
alive until all saves finish.

**Files**: `CheckStitch/ChecklistReminders.swift` (new); `ContentView.swift`
loses `createChecklistReminders()` and `Self.logger`

**Key changes**:
- `enum ChecklistReminders { static func create(from checklist: Checklist) async }` — replaces `createChecklistReminders()`; same guards, logs via `Logger`
- Contract consumed by Stage 5: call `await`, then flash the per-id checkmark

**Tests**: **cross-cutting / not unit-testable** — EventKit requires a device or
authorized simulator. Checkpoint is compile + simulator manual: (a) checklist
with 3 items → 3 reminders in Inbox; (b) blank item skipped; (c) denied access
→ no reminders, no crash, log only.
**Verify**: gate green; `make run` + manual checks a–c

---

## Stage 4: Detail screen
`EditChecklistView` becomes `ChecklistDetailView` keyed by checklist id,
mutating the store instead of a `@Binding` into another view's `@State`. Remove
actually deletes and pops.

**Files**: `CheckStitch/ChecklistDetailView.swift` (new, renamed from
`EditChecklistView` in `ContentView.swift`)

**Key changes**:
- `struct ChecklistDetailView: View { let checklistID: UUID; @Environment(ChecklistStore.self) private var store; @Environment(\.dismiss) private var dismiss }`
- Name field → `store.rename(id:to:)`; `ForEach` rows → `store.updateItem(...)`; `.onDelete` → `store.removeItems(...)`; "Add Item" → `store.addItem(to:)`
- "Remove Checklist" → `store.delete(id:)` then pop (path removal or `dismiss()`); toolbar "Done" → pop only
- Falls back to a not-found state if the id is already deleted (guards the stale-path risk from `design.md`)

**Tests**: manual simulator — rename persists across relaunch; add/remove/edit
items persist; Remove deletes from list and pops **without** a stale id
remaining in the path; Done does not delete
**Verify**: gate green; `make run` + the four manual checks

---

## Stage 5: List screen + navigation wiring
The new main surface: scrollable list, create-then-push, tap-to-push, per-id
reminder feedback, empty state, store injection.

**Files**: `CheckStitch/ContentView.swift` (rewritten), `CheckStitch/MyApp.swift`

**Key changes**:
- `MyApp`: `@State private var store = ChecklistStore()` injected via `.environment(store)`
- `struct ContentView: View { @Environment(ChecklistStore.self) private var store; @State private var path: [UUID] = []; @State private var creating: Set<UUID> = []; @State private var created: Set<UUID> = [] }`
- `NavigationStack(path: $path)` + `List(store.checklists)` rows → `NavigationLink(value: checklist.id)`; `.navigationDestination(for: UUID.self) { ChecklistDetailView(checklistID: $0) }`
- `createChecklist()` → `let c = store.create(); path.append(c.id)`
- Create action per row → `Task` with 1s-minimum spinner + `ChecklistReminders.create(from:)` + green checkmark (both sets keyed by id, transient, not persisted) — preserves VAR-966 feedback
- Empty state view when `store.checklists.isEmpty` (first-launch, per `design.md` risk)

**Tests**: manual end-to-end, the four design scenarios: (1) two checklists →
force-quit → relaunch, both intact; (2) create reminders → checkmark → Remove →
gone from list, Inbox untouched; (3) edit → relaunch persists; (4) `./scripts/test.sh` → `gate: ok`
**Verify**: gate green; `make run` scenarios 1–3; optional `bash scripts/run-devices.sh` to confirm real App Group sharing

---

## Testing Checkpoints
- **After Stage 1**: `gate: ok` + codec suite green → model shape frozen for the store.
- **After Stage 2**: store suite green against a fresh `UserDefaults` domain → persistence proven before any UI relies on it.
- **After Stage 3**: gate green + 3 manual Reminders checks → creation flow unchanged from VAR-966.
- **After Stage 4**: detail screen manual checks pass → item/name/delete mutations proven through the store.
- **After Stage 5**: all four design scenarios pass → feature complete; device run confirms the App Group payload is real (not the `.standard` fallback).
