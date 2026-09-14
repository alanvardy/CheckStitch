# Structure Outline

## Approach
Add one additive optional field (`ChecklistItem.description`, a non-optional
`String` defaulting to `""`, encoded unconditionally, decoded with
`decodeIfPresent ?? ""`) and let it ride the existing whole-item LWW merge with
**no version bump**. Build bottom-up: model/codec → store mutator → a
test-only sync/merge hardening pass → the reminder-notes seam → iOS editor →
watch row. Every stage ships its tests and must be green before the next.

**Stage 0 (prerequisite, not a code layer):** rebase this branch on
`origin/main` (VAR-991 destination seam + VAR-995 v3). All stages target the
post-rebase tree; `ChecklistItem` is conflict-free, `ChecklistDetailView` /
`ChecklistReminders` / the destination protocol are edited against main.

## Stage 1: Model & codec — the schema layer
`ChecklistItem` gains the field and its wire representation. Green tests prove
existing v2/v3 item JSON without a `"description"` key decodes to `""`, that a
present value round-trips, and that the field changes nothing else.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`CheckStitchTests/ChecklistItemTests.swift`, `CheckStitchTests/ChecklistCodecTests.swift`

**Key changes**:
- `ChecklistItem.description: String` — new stored property, default `""`
- `init(id: UUID = UUID(), title: String, description: String = "", modifiedAt: Date = .distantPast, revision: Int = 0)` — new defaulted param (label added, so existing call sites compile)
- `ChecklistItem.hasDescription: Bool { !description.isEmpty }` — new computed helper (consumed by the watch row in Stage 6 and as the notes-nil predicate in Stage 4)
- `CodingKeys` gains `case description`; encode adds `try container.encode(description, forKey: .description)`; decode adds `description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""`
- `currentVersion` **unchanged** (stays v3 post-rebase); `migrated(at:)` unchanged

**Tests**: `ChecklistItemTests` — absent-key JSON ⇒ `""`, encode/decode round-trip preserves description, blank-title + populated-description still `isBlank`; `ChecklistCodecTests` — a version-3 envelope whose item lacks the key stays `.loaded` (sad path: malformed `"description": 42` throws → `.unreadable`) and an envelope with the key decodes it
**Verify**: `make test-unit` passes for this stage.

---

## Stage 2: Store — description mutation & duplication
The store can edit a description and copy it on duplicate, using the existing
item-mutation contract. Green tests prove the edit stamps `revision` /
`modifiedAt`, debounces, and survives a persist/reload round trip.

**Files**: `CheckStitch/ChecklistStore.swift`, `CheckStitchTests/ChecklistStoreTests.swift`

**Key changes**:
- `func updateItemDescription(checklistID: UUID, itemID: UUID, description: String)` — new sibling of `updateItem`; sets the field, `revision += 1`, `modifiedAt = now()`, then `scheduleSave()`; never touches the checklist's `revision`/`modifiedAt`
- `duplicate(id:name:)` — item construction gains `description: $0.description`
- `updateItem(checklistID:itemID:title:)` unchanged (never clears the description); `addItem` unchanged (new items start `""`)

**Tests**: `ChecklistStoreTests` — `descriptionEditBumpsItemRevision`, `descriptionEditPersistsAndReloads`, `duplicateCopiesDescription`, `titleEditLeavesDescriptionIntact` (sad path: unknown item/checklist ids are no-ops)
**Verify**: `make test-unit` passes for this stage.

---

## Stage 3: Sync & merge hardening — tests only, no production change
Whole-item LWW and the envelope codec already carry the field; this stage pins
that with tests so later layers can assume round-trip stability across
UserDefaults/KVS/WCSession bytes. No production files change.

**Files**: `CheckStitchTests/ChecklistMergeTests.swift`, `CheckStitchTests/ChecklistSyncServiceTests.swift`, `CheckStitchTests/WatchChecklistStoreTests.swift`

**Key changes**: none (test additions only); fixtures `makeItem` may gain an optional description argument
**Tests**: same-item LWW keeps the winner's whole struct (remote-wins ⇒ remote description; local-wins ⇒ local description); distinct-item union preserves each description; `ChecklistCodec.encode` → `classify` round-trips the description; watch `.context` decode surfaces the description and ignores an unsupported-version context
**Verify**: `make test-unit` passes; description bytes survive an encode/decode round trip unchanged.

---

## Stage 4: Reminder destination seam — description → `EKReminder.notes`
The production run path forwards an item's description as reminder notes.
Green tests prove the fake receives the notes and that blank descriptions pass
`nil`, with zero behaviour change for titles, destinations, and errors.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift`, `CheckStitch/EventKitReminderDestination.swift`, `CheckStitch/ChecklistReminders.swift`, `CheckStitchTests/TestFixtures.swift`, `CheckStitchTests/ChecklistRemindersTests.swift`

**Key changes**:
- `protocol ReminderDestinationTargeting.create(title: String, notes: String?, in list: ReminderListOption) async throws` — signature change; every conformance/paid caller updates
- `EventKitReminderDestination.create(title:notes:in:)` — `reminder.notes = notes` when non-nil, leaving it unset otherwise
- `ChecklistReminders.create(from:targeting:)` — passes `item.description.isEmpty ? nil : item.description` (the one nil-normalisation point)
- `SpyReminderDestination` — records `createdNotes: [String?]`
- **Unchanged**: legacy core `ChecklistCreator` / `ReminderCreating` (test-only, off the production path)

**Tests**: `ChecklistRemindersTests` — `notesForwardDescription`, `blankDescriptionSendsNilNotes` (sad path: denied access / missing destination still create nothing, notes never leak)
**Verify**: `make test-unit` passes for this stage.

---

## Stage 5: iOS editor — per-row description field
Each Items row gets a multi-line description field bound per keystroke like the
title. Green tests pin the binding's read and write against the store.

**Files**: `CheckStitch/ChecklistDetailView.swift`, `CheckStitchTests/ChecklistDetailViewTests.swift`, localization strings for the new placeholder

**Key changes**:
- `func descriptionBinding(checklistID: UUID, itemID: UUID) -> Binding<String>` — new; getter re-finds the item by id, setter calls `store.updateItemDescription(...)` (mirrors `titleBinding`)
- `Section("Items")` row gains `TextField("Description", text: descriptionBinding(...), axis: .vertical)` beneath the title, with an accessibility identifier for tests
- "Description" placeholder added to the localization inventory; `LocalizationTests` unaffected unless it enumerates item placeholders

**Tests**: `ChecklistDetailViewTests` — binding writes through to the store, reads back the stored description, and keeping the title blank with a description still excludes the item from a run (sad path: missing checklist/item returns `""`)
**Verify**: `make test-unit` passes; manual `make run` confirms both fields on-device without disturbing title editing.

---

## Stage 6: watchOS row — secondary caption line
Watch rows show the description when non-empty, leaving blankness filtering
untouched. This is presentation-only; the decode path was proven in Stage 3.

**Files**: `CheckStitchWatch/WatchChecklistDetailView.swift`

**Key changes**:
- Row body becomes `VStack(alignment: .leading)` with `Text(item.title)` plus a `.font(.caption).foregroundStyle(.secondary)` `Text(item.description)` shown only when `item.hasDescription`
- `visibleItems` unchanged (`filter { !$0.isBlank }`)

**Tests**: no new unit suite (SwiftUI row); consumes the tested `hasDescription` predicate from Stage 1. Sad path is manual: a long description clamps to SwiftUI's line limit and a blank-title item with a description stays hidden.
**Verify**: `make watch-build` passes; manual `bash scripts/run-watch.sh` on the paired watch.

---

## Testing Checkpoints
- After Stage 0: `origin/main` rebased in, `make test-unit` green.
- After Stage 1: codec tests green (`make test-unit`) — old payloads load with `""`.
- After Stage 2: store tests green (`make test-unit`) — edit/duplicate round-trip.
- After Stage 3: merge/sync/watch tests green (`make test-unit`) — bytes survive.
- After Stage 4: reminder-seam tests green (`make test-unit`) — notes arrive.
- After Stage 5: detail-view tests green (`make test-unit`); iOS UI compiles.
- After Stage 6: `bash scripts/test.sh` prints `gate: ok` (sim build, mac leg, watch build, shell tests, shellcheck).
- Cross-cutting note: `description` is both a Swift property and the wire key — renaming it later is a codec change. Older v3 builds will silently drop descriptions on their next save (accepted, no version bump); call this out in the PR.