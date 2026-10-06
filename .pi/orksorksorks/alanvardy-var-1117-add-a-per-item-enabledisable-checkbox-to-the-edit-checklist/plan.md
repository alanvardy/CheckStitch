# Implementation Plan

## Overview

Add a durable per-item `isEnabled` flag to `ChecklistItem`, synced and merged
like the existing per-field clocks, and surface it as a leading checkbox on the
Items list of the "Edit checklist" screen. Disabled items are kept (export,
watch storage) but excluded from every run path; a checklist with zero enabled
non-blank items cannot be run on phone, watch, or widget.

The whole change rides the exact `prefixesReminderNumbers` precedent: additive
`Bool`, `decodeIfPresent ?? true`, a per-field LWW clock seeded from the coarse
clock, **no envelope bump** (`ChecklistCodec.currentVersion` stays `5`), and no
backfill/reformat.

A single core predicate unifies every gate and keeps them from diverging:

```swift
// ChecklistItem (Checklist.swift)
public var isRunnable: Bool { !isBlank && isEnabled }

// Checklist (Checklist.swift) — "a run would create >=1 reminder"
public var hasRunnableItems: Bool { items.contains(where: \.isRunnable) }
```

Recon changed two things from `medium.md` and this plan follows the code, not
the prose:
- The phone run button is **not** in `ChecklistRunViewModel` — it is a per-row
  button in `ContentView.swift:713` (`createRemindersButton(for:)`, gated at
  `:728` by `.disabled(runVM.creating.contains(id))`). The VM still gets a
  guard so the deep-link path shares it.
- The `RunChecklistIntent` (Siri/Shortcuts) calls `ChecklistReminders.create`
  directly, but it is already safe: with the run filter in Phase 4 a
  disabled-only checklist creates zero reminders and the gate is released.

---

## Phase 1: Walking skeleton — model + codec

The flag persists through encode/decode and migration. Thinnest end-to-end
outcome: an `isEnabled` value survives a codec round-trip with the envelope
version unchanged.

### Changes

#### 1. `ChecklistItem` model, coder, migration
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Add the stored flag, its per-field clock, and the shared run predicate.

```swift
// init(...) — add isEnabled after description, clocks at the end, before `) {`
id: UUID = UUID(), title: String, description: String = "",
isEnabled: Bool = true,
modifiedAt: Date = .distantPast, revision: Int = 0, relativeDate: Int? = nil,
...
priorityRevision: Int? = nil, priorityModifiedAt: Date? = nil,
enabledRevision: Int? = nil, enabledModifiedAt: Date? = nil
) {
    ...
    self.isEnabled = isEnabled
    ...
    self.enabledRevision = enabledRevision ?? revision
    self.enabledModifiedAt = enabledModifiedAt ?? modifiedAt
}

// stored properties
public var isEnabled: Bool
public var enabledRevision: Int
public var enabledModifiedAt: Date

// true when the item will produce a reminder
public var isRunnable: Bool { !isBlank && isEnabled }
```

```swift
// CodingKeys — add the three keys
case isEnabled, enabledRevision, enabledModifiedAt

// init(from decoder:) — after the priority block, mirroring priorityRevision/priorityModifiedAt
// Additive key: absent in earlier payloads decodes to true (the
// `prefixesReminderNumbers` precedent) — no version bump.
isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
enabledRevision = try container.decodeIfPresent(Int.self, forKey: .enabledRevision) ?? revision
enabledModifiedAt = try container.decodeIfPresent(Date.self, forKey: .enabledModifiedAt) ?? modifiedAt

// encode(to:) — write unconditionally, after priorityModifiedAt
try container.encode(isEnabled, forKey: .isEnabled)
try container.encode(enabledRevision, forKey: .enabledRevision)
try container.encode(enabledModifiedAt, forKey: .enabledModifiedAt)
```

In `Checklist.migrated(at:)`, inside the `copy.items = copy.items.map { item in ... }`
block (next to `priorityRevision`/`priorityModifiedAt`), seed the new clocks:

```swift
upgraded.enabledRevision = upgraded.revision
upgraded.enabledModifiedAt = date
```

On `Checklist` (same file), add:

```swift
/// True when at least one item would produce a reminder on a run.
public var hasRunnableItems: Bool { items.contains(where: \.isRunnable) }
```

**Do not** touch `ChecklistCodec.currentVersion` (stays `5`) and **do not**
touch `ChecklistExport.swift` / `ChecklistEntity.swift` — export encodes the
full envelope, so the flag round-trips automatically.

#### 2. Test fixture
**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify

Give the `ChecklistItem(title:description:)` factory an `isEnabled: Bool = true`
parameter forwarded to the memberwise init, so tests can build disabled items.

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `ChecklistCodecTests`: an envelope encoded from an item with
      `isEnabled == false` decodes back to `false`; an item JSON without the
      key decodes to `true`; the encoded item payload contains the
      `isEnabled`/`enabledRevision`/`enabledModifiedAt` keys; the envelope
      version is still `5` (mirror the `prefixesReminderNumbers` cases at
      `ChecklistCodecTests.swift:175-186`)
- [x] `ChecklistItemTests`: `isRunnable` is `false` for a disabled item, `false`
      for a blank item, `true` for a non-blank enabled item; `Checklist.hasRunnableItems`
      is `false` for `[]`, all-blank, and all-disabled, `true` when one
      non-blank enabled item exists
- [x] `ChecklistExportTests`: a checklist containing a disabled item exports
      and imports with the flag intact

#### Manual
- [ ] None (no UI yet)

---

## Phase 2: Merge — LWW branch + coarse high-water

The flag converges under sync without disturbing the tombstone invariant.

### Changes

#### 1. `mergedItems`
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistMerge.swift`
**Action**: modify

After the `priority` LWW branch in `mergedItems` (around `:217-222`), add an
identical branch for `isEnabled`:

```swift
if wins(revision: remoteItem.enabledRevision, date: remoteItem.enabledModifiedAt, device: remoteDevice,
        overRevision: localItem.enabledRevision, overDate: localItem.enabledModifiedAt, overDevice: localDevice) {
    merged.isEnabled = remoteItem.isEnabled
    merged.enabledRevision = remoteItem.enabledRevision
    merged.enabledModifiedAt = remoteItem.enabledModifiedAt
}
```

Add `merged.enabledRevision` to the defensive coarse high-water `max(...)`
(around `:228-229`) so the tombstone invariant (`removed.revision + 1`) holds:

```swift
merged.revision = max(
    merged.revision,
    merged.titleRevision, merged.descriptionRevision, merged.relativeDateRevision,
    merged.priorityRevision, merged.enabledRevision
)
```

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `ChecklistMergeTests`: newest `enabledRevision` wins (toggling on the
      newer device reconciles to that value); an older-revision toggle does not
      leak; merged coarse `revision` is at least `enabledRevision` even when a
      hand-crafted payload has the field clock above the coarse clock
      (mirror the priority/`prefixesReminderNumbers` cases around `:756-779`)

#### Manual
- [ ] None

---

## Phase 3: Store — toggle mutation

The flag is writable in one call, no-ops on unchanged values (no spurious LWW
win), and saves debounced.

### Changes

#### 1. `updateItem(checklistID:itemID:isEnabled:)`
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

Add next to the `priority` overload (`:473`), following its exact shape:

```swift
/// Sets an item's enabled flag. A discrete pick, so like `priority` an
/// unchanged value is a no-op (never a spurious LWW win), and the save
/// debounces like the other field edits.
public func updateItem(checklistID: UUID, itemID: UUID, isEnabled: Bool) {
    guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
          let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
    else { return }
    guard checklists[checklistIndex].items[itemIndex].isEnabled != isEnabled else { return }
    let revisedAt = now()
    checklists[checklistIndex].items[itemIndex].isEnabled = isEnabled
    checklists[checklistIndex].items[itemIndex].revision += 1
    checklists[checklistIndex].items[itemIndex].modifiedAt = revisedAt
    checklists[checklistIndex].items[itemIndex].enabledRevision = checklists[checklistIndex].items[itemIndex].revision
    checklists[checklistIndex].items[itemIndex].enabledModifiedAt = revisedAt
    scheduleSave()
}
```

`addItem(to:title:)` (`:411`) needs no change — `ChecklistItem(title:modifiedAt:revision:)`
defaults `isEnabled` to `true`.

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `ChecklistStoreTests`: a newly added item is enabled; toggling stamps
      `enabledRevision == revision` and `enabledModifiedAt == modifiedAt` and
      bumps `revision`; toggling to the same value is a no-op (revision
      unchanged); unknown checklist/item ids are silent no-ops (mirror the
      relative-date/priority store tests around `:844-870`)
- [x] `ChecklistStoreTests`: item ops still never bump the checklist's own
      `revision`/`modifiedAt`

#### Manual
- [ ] None

---

## Phase 4: Run — exclude disabled items everywhere

A disabled item produces no reminder and no numbering slot; totals reflect
only runnable items.

### Changes

#### 1. Reminders loop and totals
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistReminders.swift`
**Action**: modify

\[:47, :49, :78\]: replace the `!isBlank` predicate with `isRunnable`.

```swift
let itemCount = checklist.items.filter(\.isRunnable).count
...
for item in checklist.items where item.isRunnable {
...
let total = checklist.items.filter(\.isRunnable).count
```

#### 2. Creator numbering
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift`
**Action**: modify

Same substitution in the create-preview path (`itemCount` and its loop):
`!$0.isBlank` → `isRunnable`, and `where !item.isBlank` → `where item.isRunnable`.

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `ChecklistRemindersTests`: a disabled item creates no reminder; numbering
      over `[enabled, disabled, enabled]` is `1, 2` (contiguous, no gap);
      `partiallyCreated(created:total:)` counts only runnable items; an
      all-disabled run returns `.created(count: 0)` and releases the run slot
- [x] `ChecklistCreatorTests`: the preview numbering/total skips disabled items

#### Manual
- [ ] None

---

## Phase 5: Localization key

The checkbox's accessibility label exists in all six languages before the UI
references it.

### Changes

#### 1. String Catalog
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Add key `"Include in reminders"` (app catalog only — the checkbox lives in the
app target; watch hides disabled items and widget shows no per-item label):

| Language | Value |
|---|---|
| en | Include in reminders |
| de | In Erinnerungen aufnehmen |
| es | Incluir en recordatorios |
| fr | Inclure dans les rappels |
| ja | リマインダーに含める |
| zh-Hans | 包含在提醒事项中 |

#### 2. Required-keys fixture
**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add `"Include in reminders"` to the `"App"` list in `requiredKeys` (alphabetical
position, between `"In %lld days"` and `"Interface"`).

### Verification
#### Automated
- [x] `bash scripts/l10n-check.sh` passes
- [x] `make test-unit` passes (`LocalizationTests` required-keys check)

#### Manual
- [ ] None

---

## Phase 6: Phone UI — checkbox, dimming, run gating

The Items list shows a leading checkbox on every row; tapping it toggles
enabled/disabled without navigating; the phone run button is disabled when the
checklist has no runnable items.

### Changes

#### 1. `ItemRow` leading checkbox + dimming
**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

The `Toggle`/`NavigationLink` comment above `ItemRow` (`:330-337`) is why the
checkbox must sit **outside** the `NavigationLink` label. Add `isEnabled` and an
`onToggleEnabled` callback to the row (keep `ItemRow` free of the store), and
wrap the link in an `HStack`:

```swift
struct ItemRow: View {
    let checklistID: UUID
    let itemID: UUID
    let title: String
    let description: String
    let multiple: Int
    let relativeDate: Int?
    let priority: ChecklistItemPriority
    let isEnabled: Bool
    let onToggleEnabled: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleEnabled) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Include in reminders"))
            .accessibilityIdentifier("itemEnabledToggle-\(itemID.uuidString)")

            NavigationLink {
                ItemEditView(checklistID: checklistID, itemID: itemID)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    // existing title/priority/date/description content, unchanged
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Disabled rows dim; the app never marks items complete, so no strikethrough.
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            }
        }
        .accessibilityIdentifier("itemRow-\(itemID.uuidString)")
    }
}
```

The per-item clock write goes through the store, mirroring `numberingBinding`:

```swift
// ForEach(checklist.items) { item in
ItemRow(
    ...
    isEnabled: item.isEnabled,
    onToggleEnabled: {
        store.updateItem(checklistID: checklistID, itemID: item.id, isEnabled: !item.isEnabled)
    }
)
```

The checkbox renders for every row (including blank/placeholder items) because
every row is an `ItemRow`.

#### 2. Phone run button gating
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Change `createRemindersButton(for id: UUID)` (`:713`) to take the checklist so
it can read the predicate; update the call site at `:538` to
`createRemindersButton(for: checklist)`:

```swift
private func createRemindersButton(for checklist: Checklist) -> some View {
    Button {
        Task { await runVM.createReminders(for: checklist.id) }
    } label: { /* unchanged, using checklist.id */ }
    ...
    .disabled(runVM.creating.contains(checklist.id) || !checklist.hasRunnableItems)
    ...
}
```

#### 3. Run view-model guard (shared deep-link path)
**File**: `CheckStitch/ChecklistRunViewModel.swift`
**Action**: modify

Extend the existing guard in `createReminders(for:)` (`:33`) so a zero-runnable
checklist is a no-op even when reached off the button:

```swift
guard !creating.contains(id),
      let checklist = store.checklist(id: id),
      checklist.hasRunnableItems
else { return }
```

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `ChecklistRunViewModelTests`: `createReminders` proceeds when at least one
      item is runnable; it is a silent no-op (nothing created, `creating` never
      set) when every item is disabled or blank (sad path)
- [x] `ChecklistItemTests` still green (predicate covered in Phase 1)

#### Manual
- [ ] Build/run, open "Edit checklist": every item row has a leading circle;
      tapping the circle toggles to a filled check and dims the row
      (title + description secondary, no strikethrough); tapping the rest of the
      row still pushes "Edit item"
- [ ] Uncheck every item: the row's run button becomes disabled; re-check one and
      it re-enables

---

## Phase 7: Watch + widget gating

Disabled items are hidden on the watch and cannot be run from either surface.

### Changes

#### 1. Watch `visibleItems`
**File**: `CheckStitchWatch/WatchChecklistViewModel.swift`
**Action**: modify

`visibleItems` (`:62-63`) already hides blank rows; extend to runnable rows. The
watch's `buttonDisabled` reads `visibleItems.isEmpty`
(`WatchChecklistDetailView.swift:43-46`), so this single change also disables
the run button when nothing is enabled:

```swift
/// Blank rows and disabled rows are never turned into reminders, so the watch hides them too.
func visibleItems(of checklist: Checklist) -> [ChecklistItem] {
    current(checklist).items.filter(\.isRunnable)
}
```

#### 2. Widget runnable gate
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistWidgetDisplayModel.swift`
**Action**: modify

Extend the per-row `isRunnable` (`:55`); the widget run buttons already key off
it (`SingleChecklistWidget.swift:122`, `MultiChecklistWidget.swift:64`):

```swift
isRunnable: access == .ready && checklist.hasRunnableItems,
```

### Verification
#### Automated
- [x] `make test-unit` passes
- [ ] `WatchChecklistStoreTests`: `visibleItems` omits disabled items while
      keeping enabled non-blank ones; it is empty for an all-disabled checklist
      — not added: `WatchChecklistViewModel` is in the watchOS target, excluded
      from the macOS-hosted `CheckStitchTests` build; the filter's predicate
      (`ChecklistItem.isRunnable` / `Checklist.hasRunnableItems`) is unit-tested
      in `ChecklistItemTests`, and the watch's visible behaviour is the Manual item below
- [x] `ChecklistWidgetDisplayModelTests`: a ready checklist with zero enabled
      non-blank items yields a row with `isRunnable == false`; adding one
      enabled item flips it to `true`; the access gate still dominates (not
      `.ready` ⇒ `false`)

#### Manual
- [ ] Watch: a checklist whose items are all disabled shows no rows and a
      disabled run button; a single enabled item restores both
- [ ] Widget: a fully-disabled checklist shows the run control disabled

---

## Phase 8: Full gate

- [x] `bash scripts/test.sh` prints `gate: ok`
      (simulator build → headless pre-boot → unit + UI tests → `build-mac` →
      `watch-build` → shell tests → shellcheck)
- [x] `git status` clean of stray `.pi/orksorksorks/` artifacts before each
      phase commit; one commit per phase
