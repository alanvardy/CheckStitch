# Structure Outline

## Approach

Add one optional field (`ChecklistItem.relativeDate: Int?`) to the existing
lenient-decode/eager-encode wire format, bump the envelope to v3 with a
`.migratable(from: 2)` read that re-encodes **without** restamping sync state,
derive a pure date-only `DateComponents?` from the offset in Core, and feed that
function to both reminder-creation paths and a per-item detail-row control.

Each stage below is horizontal: it lands code **and** its tests, green, before
the stage above it starts. Nothing here edits `project.pbxproj` or the
`checklists.v1` key.

---

## Stage 1: Item model field + Codable round-trip

`ChecklistItem` gains the offset and round-trips it through JSON. Green here
proves the wire shape works with no version change involved.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`CheckStitchTests/ChecklistItemTests.swift`

**Key changes**:
- `public var relativeDate: Int?` on `ChecklistItem` (add to the memberwise
  init with a default of `nil`, so existing call sites compile unchanged)
- `case relativeDate` in `CodingKeys`; `decodeIfPresent(Int.self, forKey:) ?? nil`
  in `init(from:)`; unconditional write in `encode(to:)` (mirrors `:29-41`)

**Tests**: new `ChecklistItemTests` cases — round-trip of `nil` / `0` / `1` /
`-3`; a hand-written v2 JSON object (no `relativeDate` key) still decodes with
`nil`; `encode` always emits the key, even when `nil`.
**Verify**: `make test-unit` green (fast loop for this stage).

---

## Stage 2: Envelope v3 + version-aware migration (store, sync, watch)

`currentVersion` becomes 3; v2 payloads are accepted and re-encoded at v3
*unchanged*. Green here proves old data loads, is never restamped, and is not
mangled by the LWW merge.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`CheckStitch/ChecklistStore.swift`, `CheckStitch/ChecklistSyncService.swift`,
`CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`,
`CheckStitchTests/{ChecklistCodecTests,ChecklistStoreTests,ChecklistSyncServiceTests,WatchChecklistStoreTests}.swift`

**Key changes**:
- `ChecklistCodec.currentVersion = 3` (`:169`); `classify` gains `case 2` →
  `.migratable(from: 2, checklists:)` alongside `case 1` — reuse the existing
  `Outcome`, add no cases (`:193-208`)
- `ChecklistStore.init` (`:66-79`) branches the `.migratable` arm on
  `from`: `from == 1` → `.map { $0.migrated(at: now()) }` (today's behaviour),
  `from == 2` → payload assigned verbatim. Both keep
  `canOverwriteStoredPayload = true`
- `ChecklistSyncService.reconcileNow` (`:126-133`) treats remote v2 the same way:
  re-wrap the decoded checklists in a `ChecklistEnvelope(version: .currentVersion, …)`
  with **no** `migrated(at:)` call, then `apply(remote:)` as usual
- `WatchChecklistStore.receive` (`ChecklistSync.swift:119-133`) also accepts
  `.migratable(from: 2, …)` (envelope 2 carries every v3 field), ignoring v1 as
  today — **decision point**, recommended yes; if the user prefers strict
  `.loaded`-only, that is a one-line omission plus a documented caveat

**Tests**: `ChecklistCodecTests` — v2 payload → `.migratable(from: 2)`, v1 →
`.migratable(from: 1)`, v3 → `.loaded`, version 4 → `.unsupportedVersion`.
`ChecklistStoreTests` — a seeded v2 payload with non-zero
`revision`/`modifiedAt` loads with those values **byte-identical after save**
(the explicit anti-restamp sad path); v2 payload keeps
`canOverwriteStoredPayload == true`. `ChecklistSyncServiceTests` — remote v2
converges without introducing a spurious LWW win. `WatchChecklistStoreTests` —
v2 `.context` payload populates the watch list.
**Verify**: `make test-unit`; then `bash scripts/test.sh` before this stage's
commit (`make watch-build` is the only leg that compiles the changed watch
decoder).

---

## Stage 3: Pure offset → date-only arithmetic

One dependency-free function in Core turns an offset into a date-only
`DateComponents?`. Green here pins the arithmetic once, for both reminder paths.

**Files** (new): `CheckStitchCore/Sources/CheckStitchCore/ChecklistItem+DueDate.swift`,
`CheckStitchTests/ChecklistItemDateTests.swift`

**Key changes**:
- `func dueDateComponents(today: Date, calendar: Calendar = .current) -> DateComponents?`
  on `ChecklistItem` — `nil` when `relativeDate == nil`, else
  `calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))!)`
  with `hour`/`minute` explicitly absent (the `SingleThread` reference shape)

**Tests**: `ChecklistItemDateTests` (`Calendar(identifier: .gregorian)` with a
fixed `TimeZone`, so it is deterministic) — offset `0`/`±1` across a month and
year boundary; `nil` in → `nil` out; a just-before-midnight `today` still yields
that local day (`startOfDay` case); result carries no time components.
**Verify**: `make test-unit` green.

---

## Stage 4: Store mutation API for the offset

The store gains an offset mutator with the same shape as `updateItem(title:)`.
Green here proves edits bump revision, coalesce, and skip no-op writes.

**Files**: `CheckStitch/ChecklistStore.swift`,
`CheckStitchTests/ChecklistStoreTests.swift`

**Key changes**:
- `func updateItem(checklistID: UUID, itemID: UUID, relativeDate: Int?)` —
  overload of `:190`; guards both indexes, **no-ops when the value is unchanged**
  (this is what stops partial-text edits manufacturing LWW wins), sets
  `relativeDate`, `revision += 1`, `modifiedAt = now()`, `scheduleSave()`
- existing `updateItem(…, title:)` untouched

**Tests**: `ChecklistStoreTests` — set/bump/round-trip through
`ChecklistCodec.encode`; clear-to-`nil`; re-setting the same value does **not**
bump `revision`; unknown checklist/item IDs no-op; `onChange` fires once after
the 300 ms coalescing window, not per call.
**Verify**: `make test-unit` green.

---

## Stage 5: Reminder creation paths (live + core mirror)

Both paths set a date-only `dueDateComponents` from Stage 3. Green here covers
the dormant seam end-to-end; the live path is deliberately logic-free because it
cannot be unit-tested headless.

**Files**: `CheckStitch/ChecklistReminders.swift`,
`CheckStitchCore/Sources/CheckStitchCore/ReminderCreating.swift`,
`CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift`,
`CheckStitchTests/TestFixtures.swift`, `CheckStitchTests/ChecklistCreatorTests.swift`,
`CheckStitchTests/EventKitReminderCreatorTests.swift`

**Key changes**:
- `ReminderCreating.create(title: String, dueDateComponents: DateComponents?)`
  and the same on `EventKitReminderCreator` — sets `reminder.dueDateComponents`
  when non-nil, unchanged when nil (refines design decision 5: the seam passes
  the *computed* components, so the arithmetic has exactly one home in Core)
- `ChecklistCreator.init(reminders:, now: @escaping @Sendable () -> Date = Date.init)`;
  `create(from:)` calls `item.dueDateComponents(today: now())` per item
- `ChecklistReminders.create(from:)` adds one line per item:
  `reminder.dueDateComponents = item.dueDateComponents(today: Date())` guarded
  on non-nil — no other branching
- `SpyReminderCreator` records `createdItems: [(title: String, dueDateComponents: DateComponents?)]`
  (keep `createdTitles` as a computed shim so existing assertions stay valid)

**Tests**: `ChecklistCreatorTests` — offset carries through to the spy; `nil`
stays `nil`; blank items still skipped with dates present; exact
`DateComponents` for `0`/`1`/`-1` under a fixed calendar. `EventKitReminderCreatorTests`
— crash-canary extended to build a reminder with `dueDateComponents` against
`sharedTestEventStore` and read it back (no `save`).
`ChecklistViewModelTests` needs only the fixture shim, no assertion changes.
**Verify**: `make test-unit`, then `bash scripts/test.sh`; manual check —
`make run`, run a checklist with a `0`/`1` item, confirm the reminder shows
today/tomorrow in Reminders and an unnumbered item has no date.

---

## Stage 6: Detail-row date field

One control per item row, bound through Stage 4's store API.

**Files**: `CheckStitch/ChecklistDetailView.swift`,
`CheckStitchTests/ChecklistDetailViewTests.swift`

**Key changes**:
- `func relativeDateBinding(checklistID: UUID, itemID: UUID) -> Binding<String>`
  beside `titleBinding` (`:152`) — `get` formats `Int?` (nil → `""`), `set`
  parses `Int(text)` and maps unparseable text to `nil`
- the `Section("Items")` row (`:36-43`) gains a compact `TextField("Days", text:)`
  with `.keyboardType(.numberPad)`, `.multilineTextAlignment(.trailing)` and
  `.accessibilityIdentifier("itemRelativeDateField")`

**Tests**: `ChecklistDetailViewTests` — value-description assertion that the new
row control and id are present; the parse/format behaviour is covered by the
store tests from Stage 4 (SwiftUI bodies cannot be staged headless).
**Verify**: `make test-unit`; `bash scripts/test.sh` (this is the stage that
compiles the real UI, so the gate — not just the fast loop — is required);
manual `make run` typing check.

---

## Testing Checkpoints

- After Stage 1: `make test-unit` — item round-trip incl. absent-key decode.
- After Stage 2: `make test-unit` + `bash scripts/test.sh` — v2 loads unstamped;
  watch decoder compiles and accepts v2.
- After Stage 3: `make test-unit` — deterministic offset arithmetic.
- After Stage 4: `make test-unit` — revision bump, no-op on unchanged value.
- After Stage 5: `make test-unit` + gate + manual Reminders check — both paths date.
- After Stage 6: gate green + manual typing check. Only then is the ticket done.

## Cross-Cutting Notes

- **The live reminder path is not unit-testable** (fresh `EKEventStore`, real
  permissions). Its assurance is Stage 3's tested function plus Stage 5's parity
  test through `SpyReminderCreator`; keep its added code to a nil-guarded
  assignment so there is nothing unverified beyond that.
- **UI interaction is only fully exercisable on a simulator.** Stage 6 tests
  assert on the view *description*; real typing is the manual check and the
  existing UI smoke (`make test-ui`) is unchanged. If the user wants the
  per-keystroke `""`/`"-"` transient handled without a store round-trip, that
  needs a buffered `ItemRow` subview (mirroring the existing `draftName`
  precedent) instead of the unbuffered binding above — a split of Stage 6 that
  should be decided before implementation.
- **`EKReminder.dueDateComponents` + a deallocated store crashes** — any new
  EventKit-touching test must use `sharedTestEventStore`.