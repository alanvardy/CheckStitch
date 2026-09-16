# Structure Outline

## Approach

Add priority as a fourth per-field-clock axis on `ChecklistItem`, exactly like
`relativeDate`: a `ChecklistItemPriority` enum (raw value = EventKit's scale) as
the value, `priorityRevision`/`priorityModifiedAt` as its clocks, an additive
non-optional key written unconditionally and defaulted on decode. The user sets
it from a `Menu` in a new `ItemEditView` section; the store persists it, merge
reconciles it independently, and a checklist run writes it to `EKReminder`.

Slices are ordered dependency → risk → value: merge (the only real integration
risk) lands inside the walking skeleton, so no invariant is ever shipped broken.

---

## Phase 1: Walking skeleton — pick a priority that persists end to end

A user opens an item, taps the priority row's info button, picks one of
None/Low/Medium/High; the label updates, the value survives relaunch, and two
devices converge on it without dragging the title/description/date edits along.
Green tests prove: model + codec round-trip, store clock stamping and no-op
guard, merge as an independent axis, and the row rendering.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistItemPriority.swift`
(new), `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`CheckStitch/ChecklistStore.swift`, `CheckStitch/ChecklistMerge.swift`,
`CheckStitch/ItemEditView.swift`

**Key changes**:
- `public enum ChecklistItemPriority: Int, Codable, CaseIterable, Hashable, Sendable`
  — `case none = 0, low = 9, medium = 5, high = 1`; declaration order **is**
  `allCases` order, raw value **is** the EventKit scale. Add a
  `var label: String` (or equivalent) so no view branch maps cases.
- `ChecklistItem.priority: ChecklistItemPriority`,
  `priorityRevision: Int`, `priorityModifiedAt: Date` — new stored properties;
  init params default `nil` and seed from the coarse clock (`:22-29` pattern);
  `CodingKeys` member; decode `decodeIfPresent ?? .none`; encode unconditionally.
- `ChecklistStore.updateItem(checklistID: UUID, itemID: UUID, priority: ChecklistItemPriority)`
  — no-op guard (`item.priority != priority`), coarse + field clock stamp,
  `scheduleSave()`; mirrors the `relativeDate` overload (`:319-330`).
- `ChecklistMerge.mergedItems(...)`: a `priorityRevision`/`priorityModifiedAt`
  axis block beside `:147-152`, and `priorityRevision` added to the high-water
  `max` (`:160-163`).
- `ItemEditView`: new `Section("Priority")` (header + row), identifier
  `itemEditPriorityRow` on the row and `itemEditPriorityMenu` on the `Menu`
  label; menu lists `ChecklistItemPriority.allCases` with a checkmark on the
  current value, writing through a `priorityBinding` like `titleBinding`; no
  `ItemRow`/`ChecklistDetailView` change.

**Contract** (everything later phases may assume):
- `ChecklistItemPriority` is public, `CaseIterable`, and its `rawValue` is the
  `EKReminder.priority` scale.
- `ChecklistItem.priority` is public, non-optional, defaults to `.none`; the
  `priority` key is always written by the encoder.
- `updateItem(checklistID:itemID:priority:)` is the only write path.
- Identifiers `itemEditPriorityRow` / `itemEditPriorityMenu` exist.

**Tests** (Swift Testing unless noted):
- `ChecklistItemTests.swift` — `priorityDefaultsToNoneWhenKeyAbsent`,
  priority round-trips, `encodeAlwaysEmitsPriorityKey` (`:50` precedent).
- `ChecklistCodecTests.swift` (XCTest) — `testPriorityKeyAbsentStaysLoaded`,
  malformed priority value → `.unreadable`, and `:253`
  `testV1V2V3ClassificationUnchanged` extended, not altered.
- `ChecklistStoreTests.swift` (XCTest) — mutator stamps both clocks + coarse
  revision; re-selecting the same value bumps nothing; value survives reload
  under `"checklists.v1"`; v1 payload migration yields `priorityRevision ==
  revision` (the `migrated(at:)` open risk).
- `ChecklistMergeTests.swift` — priority-only remote edit wins; concurrent title
  + priority edits both survive (independent axes); high-water `max` includes
  `priorityRevision`; merge stays symmetric.
- `ChecklistDetailViewTests.swift` — `itemEditViewRendersPriorityRow` via
  `String(describing:)`.

**Verify**: `make test-unit` green, then `make build` (the `Menu`-in-`Form`
compile is the API oracle) — iOS leg only.

---

## Phase 2: Running a checklist writes the priority to the reminder

A user marks an item High, runs the checklist, and the created reminder appears
flagged High in Reminders (`none→0, low→9, medium→5, high→1`). Green tests prove
the whole mapping table crosses the seam into `EKReminder.priority`.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift`,
`CheckStitch/EventKitReminderDestination.swift`, `CheckStitch/ChecklistReminders.swift`,
`CheckStitchTests/TestFixtures.swift`

**Key changes**:
- `ReminderDestinationTargeting.create(title:notes:priority:in:dueDateComponents:)`
  — add the `priority: ChecklistItemPriority` parameter to the protocol (`:87`).
- `EventKitReminderDestination.create(...)` sets `reminder.priority =
  priority.rawValue` before `save(commit: true)`.
- `ChecklistReminders.create(from:)` (`:30-34`) forwards `item.priority`.
- `RecordingReminderDestination` (`TestFixtures.swift:73-84`) gains
  `createdPriorities` alongside `createdDates`.

**Contract**: the `priority:` parameter is the destination seam's priority
contract; any future conformance must supply it (compiler-enforced across the
app, watch, and test targets).

**Tests**:
- Destination/`ChecklistReminders` suite — `@Test(arguments:)` over
  `ChecklistItemPriority.allCases` asserting `createdPriorities` matches the
  item's priority and `priority.rawValue` is the EventKit value.
- `none` path asserted explicitly (default items create `priority == 0`).

**Verify**: `make test-unit` green; `make watch-build` green (every conformance
updated). Manual: `make run`, run a checklist with one High item, confirm the
reminder is flagged High in Reminders.app.

---

## Phase 3: Hardening — back-compat closure and the visible outcome

Legacy and round-tripped payloads are proven to carry priority, malformed
priority fails closed, and the installed bundle is seen to show the row, menu,
and label.

**Files**: `CheckStitchTests/ChecklistCodecTests.swift`,
`CheckStitchTests/ChecklistStoreTests.swift`,
`CheckStitchTests/ChecklistExportTests.swift`,
`CheckStitchTests/ChecklistImportSessionTests.swift`,
`CheckStitchTests/ChecklistItemTests.swift` (tests only; driven fixes if any)

**Key changes**: none expected — this phase closes evidence gaps and fixes
anything the sad-path tests surface (e.g. a migration path that constructs items
with explicit clocks).

**Contract**: back-compat is now test-enforced: absent priority key → `.none`;
exported bytes classify `.loaded`; duplicate/import preserve priority through
the codec; unknown raw value → `.unreadable`.

**Tests**:
- `testExportedBytesClassifyLoadedWithPriority` (`ChecklistExportTests.swift:27`
  pattern); duplicate/import round-trip keeps priority.
- v1-vs-v4 migration parity: a v1 payload and a current-version payload with the
  same logical item produce the same `priority` + `priorityRevision`.
- Malformed/unknown priority raw values → `.unreadable` (sad path).

**Verify**: `make test-unit`, then the full gate `bash scripts/test.sh` ending
`gate: ok`. Live check: install the built app on the pinned simulator and
confirm the item screen shows the Priority row with the current value and a
working menu — static evidence is not sufficient for this ticket.

---

## Testing Checkpoints

- **After Phase 1**: `make test-unit` + `make build` green — priority persists,
  merges per-field, and the section renders. If red, stop.
- **After Phase 2**: `make test-unit` + `make watch-build` green — the created
  reminder carries the mapped priority.
- **After Phase 3**: `bash scripts/test.sh` prints `gate: ok`, and the installed
  bundle shows the priority row + menu.

## Notes

- Nothing here is genuinely horizontal: the only cross-cutting change is the
  `ReminderDestinationTargeting` protocol signature, which stays inside Phase 2
  because the compiler forces every conformance to be updated in that commit.
- No schema/envelope version bump and no `classify` change — `relativeDate` is
  the additive-field precedent (`ChecklistCodecTests.swift:171,:253`).
- The legacy core seam (`ReminderCreating`/`ChecklistCreator`/`ChecklistViewModel`)
  is intentionally untouched; call that out in the PR.