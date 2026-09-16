# Implementation Plan

## Overview

Add a per-item priority (`none`/`low`/`medium`/`high`) modeled as a fourth
per-field-clock axis on `ChecklistItem`, picked from a `Menu` in a new
`ItemEditView` section, persisted through the codec/store/merge, and written to
`EKReminder.priority` (raw value = EventKit scale) when a checklist runs. No
version bump: `priority` is another additive key defaulted to `.none` on decode.

Deviations from `structure.md` (all noted inline): the reminder test double is
`SpyReminderDestination`, not `RecordingReminderDestination`; the migrated-item
fix and the `duplicate`/`freshCopy` forwarding are explicit Phase 1 changes; the
priority-row identifier is not observable through `String(describing:)`, so the
row test uses `ImageRenderer` instead.

---

## Phase 1: Walking skeleton — pick a priority that persists end to end

A user opens an item, opens the priority menu, picks one of None/Low/Medium/High;
the row label updates, the value survives relaunch, and two devices converge on
it without dragging title/description/date edits along.

### Changes

#### 1. New priority enum

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistItemPriority.swift`
**Action**: create

```swift
import Foundation

/// A checklist item's priority. Declaration order **is** `allCases` order
/// (the menu order); the raw value **is** `EKReminder.priority`'s scale, so
/// writing a reminder needs no switch.
public enum ChecklistItemPriority: Int, Codable, CaseIterable, Hashable, Sendable {
    case none = 0
    case low = 9
    case medium = 5
    case high = 1

    /// User-facing name, kept on the model so no view branches over the cases.
    public var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}
```

No `project.pbxproj` edit: `CheckStitchCore` is a sources-only SPM package (auto-included).

#### 2. Model: value + two clocks

**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

In `ChecklistItem`:

- Init signature — after `relativeDate: Int? = nil` add `priority: ChecklistItemPriority = .none`, and after the `relativeDateModifiedAt` param add `priorityRevision: Int? = nil, priorityModifiedAt: Date? = nil`.
- Init body — after the `relativeDateModifiedAt` seed:
  ```swift
  self.priority = priority
  self.priorityRevision = priorityRevision ?? revision
  self.priorityModifiedAt = priorityModifiedAt ?? modifiedAt
  ```
- Stored properties — after `relativeDateModifiedAt`:
  ```swift
  public var priority: ChecklistItemPriority
  public var priorityRevision: Int
  public var priorityModifiedAt: Date
  ```
- `CodingKeys` — add `case priority, priorityRevision, priorityModifiedAt`.
- `init(from:)` — after the `relativeDateModifiedAt` line:
  ```swift
  // Additive, defaulted on absence — no version bump (relativeDate precedent).
  priority = try container.decodeIfPresent(ChecklistItemPriority.self, forKey: .priority) ?? .none
  priorityRevision = try container.decodeIfPresent(Int.self, forKey: .priorityRevision) ?? revision
  priorityModifiedAt = try container.decodeIfPresent(Date.self, forKey: .priorityModifiedAt) ?? modifiedAt
  ```
- `encode(to:)` — after `relativeDateModifiedAt`:
  ```swift
  try container.encode(priority, forKey: .priority)
  try container.encode(priorityRevision, forKey: .priorityRevision)
  try container.encode(priorityModifiedAt, forKey: .priorityModifiedAt)
  ```

In `Checklist.migrated(at:)` (the confirmed open risk — it restamps every field
clock explicitly, so priority must be added or v1 migration leaves it at 0):
inside the `copy.items = copy.items.map { ... }` closure, after
`upgraded.relativeDateModifiedAt = date`:
```swift
upgraded.priorityRevision = upgraded.revision
upgraded.priorityModifiedAt = date
```

`classify` / `currentVersion` are untouched (still 4).

#### 3. Store: mutator + forwarding in structural copies

**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

- New mutator, immediately after `updateItem(checklistID:itemID:relativeDate:)`,
  mirroring it exactly:
  ```swift
  /// Sets an item's priority. A discrete pick, so like `relativeDate` an
  /// unchanged value is a no-op (never a spurious LWW win), and the save
  /// debounces like the other field edits.
  func updateItem(checklistID: UUID, itemID: UUID, priority: ChecklistItemPriority) {
      guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
            let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
      else { return }
      guard checklists[checklistIndex].items[itemIndex].priority != priority else { return }
      let revisedAt = now()
      checklists[checklistIndex].items[itemIndex].priority = priority
      checklists[checklistIndex].items[itemIndex].revision += 1
      checklists[checklistIndex].items[itemIndex].modifiedAt = revisedAt
      checklists[checklistIndex].items[itemIndex].priorityRevision = checklists[checklistIndex].items[itemIndex].revision
      checklists[checklistIndex].items[itemIndex].priorityModifiedAt = revisedAt
      scheduleSave()
  }
  ```
- `duplicate(id:name:)` — the item rebuild drops every field not spelled out;
  add `priority: $0.priority` to the `ChecklistItem(...)` initializer (keeps
  `relativeDate: $0.relativeDate`).
- `freshCopy(of:)` — same: add `priority: $0.priority` to the `ChecklistItem(...)`.

Without these two, duplicate/import would silently reset priority to `.none`.

#### 4. Merge: an independent priority axis

**File**: `CheckStitch/ChecklistMerge.swift`
**Action**: modify

In `mergedItems`, after the `relativeDate` block (the `if wins(revision: remoteItem.relativeDateRevision, ...)` block) add:

```swift
if wins(revision: remoteItem.priorityRevision, date: remoteItem.priorityModifiedAt, device: remoteDevice,
        overRevision: localItem.priorityRevision, overDate: localItem.priorityModifiedAt, overDevice: localDevice) {
    merged.priority = remoteItem.priority
    merged.priorityRevision = remoteItem.priorityRevision
    merged.priorityModifiedAt = remoteItem.priorityModifiedAt
}
```

And in the high-water `max`, add `merged.priorityRevision`:

```swift
merged.revision = max(
    merged.revision,
    merged.titleRevision, merged.descriptionRevision, merged.relativeDateRevision, merged.priorityRevision
)
```

#### 5. View: priority section + menu

**File**: `CheckStitch/ItemEditView.swift`
**Action**: modify

Insert a new section between `Section("Description")` and the due-date section:

```swift
Section("Priority") {
    Menu {
        ForEach(ChecklistItemPriority.allCases, id: \.self) { priority in
            Button {
                priorityBinding.wrappedValue = priority
            } label: {
                if priority == item.priority {
                    Label(priority.label, systemImage: "checkmark")
                } else {
                    Text(priority.label)
                }
            }
        }
    } label: {
        HStack {
            Text(item.priority.label)
            Spacer()
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("itemEditPriorityMenu")
    }
    .accessibilityIdentifier("itemEditPriorityRow")
}
```

Add the binding beside `titleBinding`:

```swift
/// Writes through the store's no-op-guarded priority mutator.
private var priorityBinding: Binding<ChecklistItemPriority> {
    Binding(
        get: {
            store.checklist(id: checklistID)?
                .items.first { $0.id == itemID }?.priority ?? .none
        },
        set: {
            store.updateItem(checklistID: checklistID, itemID: itemID, priority: $0)
        }
    )
}
```

No `ItemRow`/`ChecklistDetailView` change.

### Contract (everything later phases may assume)

- `ChecklistItemPriority` is public, `CaseIterable`, and its `rawValue` is the
  `EKReminder.priority` scale.
- `ChecklistItem.priority` is public, non-optional, defaults to `.none`; the
  `priority` key is always written by the encoder.
- `updateItem(checklistID:itemID:priority:)` is the only write path.
- Identifiers `itemEditPriorityRow` / `itemEditPriorityMenu` exist.

### Tests (Swift Testing unless noted)

**`CheckStitchTests/ChecklistItemTests.swift`** (`@testable import CheckStitchCore`):
- `priorityDefaultsToNoneWhenKeyAbsent` — decode `{"id":...,"title":"one"}` → `priority == .none`.
- `priorityRoundTripsThroughCodable` — `@Test(arguments: ChecklistItemPriority.allCases)`.
- `encodeAlwaysEmitsPriorityKey` — mirror `encodeAlwaysEmitsRelativeDateKey` via `JSONSerialization.jsonObject` and assert the `"priority"` key is present.
- `everyPriorityHasALabel` — `@Test(arguments: ChecklistItemPriority.allCases)`, label non-empty.
- `priorityRawValuesAreTheEventKitScale` — `#expect(ChecklistItemPriority.none.rawValue == 0)` etc., and `allCases == [.none, .low, .medium, .high]`.

**`CheckStitchTests/ChecklistCodecTests.swift`** (XCTest, `@MainActor`):
- `testPriorityKeyAbsentStaysLoaded` — v4 payload without `priority` classifies `.loaded` with `.none` (mirror `testItemWithoutDescriptionClassifiesLoadedAsEmpty`).
- `testMalformedPriorityMakesPayloadUnreadable` — `"priority":"high"` (string, not raw int) → `.unreadable` (mirror `testMalformedDescriptionMakesPayloadUnreadable`); add an `"priority":99` unknown-raw case too.
- Extend `testFieldClocksSurviveEnvelopeRoundTrip` to include `priorityRevision`/`priorityModifiedAt`; extend `testItemWithoutFieldClocksSeedsFromCoarseClock` to assert `priorityRevision == revision`. Leave `testV1V2V3ClassificationUnchanged` assertions intact (they still hold) — no alteration.

**`CheckStitchTests/ChecklistStoreTests.swift`** (XCTest, `@MainActor`):
- `testUpdateItemPriorityStampsBothClocks` — coarse `revision` bumps, `modifiedAt == priorityModifiedAt`, `priorityRevision == revision`, title/description/relativeDate clocks untouched.
- `testUpdateItemPriorityNoOpsWhenUnchanged` — re-setting the same value bumps nothing (mirror `testUnchangedRelativeDateIsANoOpForEveryClock`).
- `testUpdateItemPriorityPersistsAndReloads` — value survives a new store under `"checklists.v1"`.
- Extend `testLegacyPayloadIsMigratedAndSavable` with `priorityRevision == 1`, `priorityModifiedAt == modifiedAt`, `priority == .none`.

**`CheckStitchTests/ChecklistMergeTests.swift`** (`@MainActor`):
- `priorityRemoteEditWins` — priority-only remote edit wins.
- `concurrentTitleAndPriorityEditsBothSurvive` — independent axes (mirror `sameFieldEditsStillResolveByFieldLWW`).
- Symmetry: `#expect(merge(local: a, remote: b) == merge(local: b, remote: a))` for a priority-only edit.
- Extend `mergedCoarseClockCoversEveryAdoptedFieldClock` to include `priorityRevision`.

**`CheckStitchTests/ChecklistDetailViewTests.swift`** (`@MainActor`):
- `itemEditViewRendersPriorityRow` — build the store (isolated defaults, `textEditDelay: nil`), set a priority via `store.updateItem(checklistID:itemID:priority:)`, then `ImageRenderer(content: ItemEditView(...).environment(store))` non-nil under `#if os(macOS)`/`#else` (mirror `itemEditViewRendersForAnExistingItem`). This is the deviation from structure's `String(describing:)` assertion: `String(describing:)` reflects stored properties only and cannot see a body identifier.

### Verification

#### Automated
- [x] `make test-unit` passes (compile + all new cases green)
- [x] `make build` passes — the `Menu`-in-`Form` compile is the API oracle

#### Manual
- [ ] `make run`; open a checklist → item → confirm a **Priority** section shows `None` with an info icon on the right; tapping it opens a menu listing None/Low/Medium/High with a checkmark on the current value; picking `High` updates the row label
- [ ] Relaunch the app and reopen the item — the value is still `High`

---

## Phase 2: Running a checklist writes the priority to the reminder

A user marks an item High, runs the checklist, and the created reminder appears
flagged High in Reminders (mapping `none→0, low→9, medium→5, high→1`).

### Changes

#### 1. Seam signature

**File**: `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift`
**Action**: modify

Add `priority: ChecklistItemPriority` to the protocol requirement:

```swift
func create(title: String, notes: String?, priority: ChecklistItemPriority,
            in list: ReminderListOption, dueDateComponents: DateComponents?) async throws
```

Update the doc comment to note the raw value is written to `EKReminder.priority`.

#### 2. Real adapter

**File**: `CheckStitch/EventKitReminderDestination.swift`
**Action**: modify

```swift
func create(title: String, notes: String?, priority: ChecklistItemPriority,
            in list: ReminderListOption, dueDateComponents: DateComponents?) async throws {
    // ... existing calendar resolution ...
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = title
    if let notes { reminder.notes = notes }
    reminder.calendar = calendar
    reminder.priority = priority.rawValue
    if let dueDateComponents {
        reminder.dueDateComponents = dueDateComponents
    }
    // ... existing watchOS/save guard ...
}
```

#### 3. Orchestrator call site

**File**: `CheckStitch/ChecklistReminders.swift`
**Action**: modify

In the item loop, forward the field:

```swift
try await targeting.create(
    title: item.title,
    notes: item.hasDescription ? item.description : nil,
    priority: item.priority,
    in: destination,
    dueDateComponents: dueDateComponents)
```

#### 4. Test double

**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify

In `SpyReminderDestination` (**not** `RecordingReminderDestination` — that name
does not exist in the repo):
- Add `private(set) var createdPriorities: [ChecklistItemPriority] = []`.
- In `create(...)`, after `createdNotes.append(notes)` add `createdPriorities.append(priority)`.
- Update the method signature to include `priority: ChecklistItemPriority`.

`EventKitReminderDestinationTests.swift` only constructs the adapter and never
calls `create`, so it needs no edit.

### Contract

The `priority:` parameter is the destination seam's priority contract; every
conformance must supply it (compiler-enforced across app, watch, and test
targets).

### Tests

**`CheckStitchTests/ChecklistRemindersTests.swift`** (`@MainActor`):
- `prioritiesCarryToTheSeam` — `@Test(arguments: ChecklistItemPriority.allCases)`: a checklist of one item with that priority yields `spy.createdPriorities == [priority]` and `priority.rawValue` equals the EventKit value.
- `defaultItemsSendNonePriority` — `makeItem("Milk")` → `spy.createdPriorities == [.none]` (`rawValue == 0`).
- Extend `relativeDatesCarryToTheSeam` / `blankTitlesAreSkipped` if needed so the new parameter does not change their expectations (index alignment with `createdTitles`).

### Verification

#### Automated
- [ ] `make test-unit` passes
- [ ] `make watch-build` passes (the Core protocol change compiles under the watchOS SDK)

#### Manual
- [ ] `make run`; create an item, set it High, run the checklist; in Reminders.app the created reminder is flagged High (and a `none` item is not flagged)

---

## Phase 3: Hardening — back-compat closure and the visible outcome

Legacy and round-tripped payloads are proven to carry priority, malformed
priority fails closed, and the installed bundle is seen to show the row, menu,
and label.

### Changes

No new production code expected. Fix anything these sad-path tests surface — the
most likely candidates are already folded into Phase 1 (`migrated(at:)`,
`duplicate`, `freshCopy`); if a further explicit-clock construction is found,
forward `priority`/`priorityRevision`/`priorityModifiedAt` there.

### Tests

**`CheckStitchTests/ChecklistExportTests.swift`** (`@MainActor`):
- `testExportPreservesPriority` — export a checklist with a `.high` item, classify the bytes `.loaded`, decode, assert `priority == .high` and `priorityRevision == revision` (mirror `testExportOfSubsetRoundTripsThroughCodec`).
- Extend `testExportEmptySelectionClassifiesLoadedWithNoChecklists` only if the new key changes its byte expectation (it should not).

**`CheckStitchTests/ChecklistImportSessionTests.swift`** (`@MainActor`):
- `importPreservesPriority` — a payload whose item is `.medium` imports (insert and replace) with `priority == .medium` (this is the test that would have caught the `freshCopy` drop).
- Extend `keepBothDisambiguates` if convenient.

**`CheckStitchTests/ChecklistStoreTests.swift`** (`@MainActor`):
- `testV1AndV4MigrationAgreeOnPriority` — a v1 payload and a current-version payload for a logically-equivalent revision-1 item both decode to `priority == .none` and `priorityRevision == revision`.
- `prioritySurvivesDuplicateAndImport` — `duplicate(id:name:)` keeps the source item's priority.
- Extend `testDuplicateCopiesRelativeDate` sibling assertions for priority.

**`CheckStitchTests/ChecklistItemTests.swift`**:
- Extend the codec-level edge cases so a round-tripped item preserves priority through duplicate/import payload rebuilds (pure codec: encode → decode → `priority` equal).

### Verification

#### Automated
- [ ] `make test-unit` passes
- [ ] `bash scripts/test.sh` prints `gate: ok` (all four platform legs + shell tests + shellcheck)

#### Manual
- [ ] Install the built app on this worktree's pinned simulator and confirm the **Priority** row renders the current value with a working menu — static evidence is not sufficient for this ticket (see the `devicectl`/`simulator` skills). Expected: item screen shows `Priority` section, label on the left, a tappable info control on the right, checkmark on the selected option.

---

## Testing Checkpoints

- **After Phase 1**: `make test-unit` + `make build` green — priority persists, merges per-field, and the section renders. If red, stop.
- **After Phase 2**: `make test-unit` + `make watch-build` green — the created reminder carries the mapped priority.
- **After Phase 3**: `bash scripts/test.sh` prints `gate: ok`, and the installed bundle shows the priority row + menu.

## Notes

- The only cross-cutting change is the `ReminderDestinationTargeting` protocol
  signature, which stays inside Phase 2 because the compiler forces every
  conformance (all two of them) to be updated in that commit.
- No schema/envelope version bump and no `classify` change.
- The legacy core seam (`ReminderCreating` / `ChecklistCreator` /
  `ChecklistViewModel`) is intentionally untouched; call that out in the PR.
- No `project.pbxproj` edit is needed for the new `CheckStitchCore` file.
- Do not rely on `String(describing:)` to observe the new identifiers — it
  reflects stored properties, not the rendered body; the row render test and the
  manual/live check are the verification.
