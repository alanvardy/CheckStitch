# Implementation Plan

## Overview

Add reversible **archive** bookkeeping to `Checklist` (two additive optional
fields `isArchived`/`archivedAt`, no codec version bump) with a `ChecklistStore`
chokepoint pair (`archive`/`restore`/`removeArchived` + the
`activeChecklists`/`archivedChecklists` filters) and a Settings **Archived
Checklists** subscreen. Archived checklists disappear from the phone list, watch,
export, Siri/App Intents and widgets, but never touch Reminders.

Ordering rule for every phase: **new localized strings ship inside the slice
that introduces them**, never in a trailing phase.

> Note on paths: structure.md said the Settings entry lives in
> `CheckStitch/ContentView.swift`. The Settings rows actually live in
> `CheckStitch/SettingsView.swift`; the entry is added there (see Phase 3).

---

## Phase 1: Walking skeleton — archive one checklist and watch it leave the main list

**Vertical slice**: tap Archive in a checklist's detail screen → it vanishes from
the phone main list → still gone after relaunch.

### Changes

#### 1. `Checklist` fields + codec (core)
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Add two stored properties and thread them through the public init, `CodingKeys`,
decode, and encode. Follow the `showsOnWatch`/`prefixesReminderNumbers`
additive-optional precedent exactly (no version bump; `currentVersion` stays 5).
`migrated(at:)`, `seededOrder()`, `normalizedOrder()` all use `var copy = self`
and need no change.

```swift
// init(...) — insert after `folderID: UUID? = nil,`
isArchived: Bool = false,
archivedAt: Date? = nil,
```

```swift
// stored properties — after `folderID`
/// Whether this checklist is archived: hidden from every run/list surface but
/// still stored, restorable, and synced. Shares the checklist's coarse
/// `revision`/`modifiedAt` clock (like the name and destination), so an archive
/// is decided by the same last-write-wins rule. Additive optional key: absent in
/// v5-and-earlier payloads decodes to `false` with no version bump.
public var isArchived: Bool
/// When the checklist was archived, for the Archived Checklists screen. `nil`
/// for active checklists and for hand-written payloads that omit it. Additive
/// optional key, no version bump.
public var archivedAt: Date?
```

```swift
// CodingKeys
case id, name, items, destinationListIdentifier, prefixesReminderNumbers, showsOnWatch, folderID
case isArchived, archivedAt
case modifiedAt, revision, itemOrder, orderRevision, orderModifiedAt
```

```swift
// init(from:) — after `folderID`
// Additive optional field: absent key decodes to false, matching the
// `showsOnWatch`/`folderID` precedent — no version bump.
let isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
let archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
```

Pass both through the trailing `Checklist(...)` re-entry init (add
`isArchived: isArchived, archivedAt: archivedAt,` before `folderID:` or in the
same labelled group) so the value is assigned at once, then `.normalizedOrder()`.

```swift
// encode(to:) — after folderID
try container.encode(isArchived, forKey: .isArchived)
if let archivedAt {
    try container.encode(archivedAt, forKey: .archivedAt)
} else {
    try container.encodeNil(forKey: .archivedAt)
}
```

#### 2. `ChecklistStore` filters + `archive(id:)`
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

Add the two computed filters and the archive mutation. `checklists` stays the
full set (persistence/sync), which is why `checklist(id:)` keeps resolving
archived records.

```swift
/// Active (non-archived) checklists. The single source every listing/run/query
/// surface reads instead of `checklists`.
public var activeChecklists: [Checklist] { checklists.filter { !$0.isArchived } }

/// Archived checklists, newest `archivedAt` first; a `nil` date sorts last so
/// the ordering is total.
public var archivedChecklists: [Checklist] {
    checklists.filter(\.isArchived).sorted { lhs, rhs in
        switch (lhs.archivedAt, rhs.archivedAt) {
        case let (l?, r?): return l > r
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return false
        }
    }
}

/// Archives a checklist: sets `isArchived`/`archivedAt` and bumps the coarse
/// clock. An already-archived or unknown id is a no-op returning `false`.
@discardableResult
public func archive(id: UUID) -> Bool {
    guard let index = checklists.firstIndex(where: { $0.id == id }),
          !checklists[index].isArchived else { return false }
    checklists[index].isArchived = true
    checklists[index].archivedAt = now()
    checklists[index].revision += 1
    checklists[index].modifiedAt = now()
    save()
    return true
}
```

#### 3. Phone list reads active only
**File**: `CheckStitch/ChecklistListViewModel.swift`
**Action**: modify

```swift
var checklists: [Checklist] { store.activeChecklists }
```

Also change both `store.checklists` enumerations inside `checklists(in folder:)`
to `store.activeChecklists` — otherwise an archived checklist filed in a folder
still renders in the folder row. Do **not** touch `moveChecklist`/`removeChecklist`
index arithmetic (they need the full array).

#### 4. Detail-screen Archive action
**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

Add `@State private var isArchiveConfirmPresented = false`. Add an overflow
`Menu` toolbar item before the existing `Done` item (use `.primaryAction`, which
is cross-platform; `.topBarLeading` is iOS-only here).

```swift
ToolbarItem(placement: .primaryAction) {
    Menu {
        Button {
            isArchiveConfirmPresented = true
        } label: {
            Label("Archive Checklist", systemImage: "archivebox")
        }
        .accessibilityIdentifier("archiveChecklistButton")
    } label: {
        Image(systemName: "ellipsis.circle")
    }
    .accessibilityLabel(Text("Archive Checklist"))
}
```

Use a bare `Image` label (no `"More"` string) so no ninth catalog key is
introduced — design decision 11 caps the new strings at eight. The
`accessibilityLabel` reuses the already-catalogued `"Archive Checklist"`.

Add the dialog alongside the existing `.confirmationDialog(...)` modifiers.
The checklist still resolves after archiving (`checklist(id:)` is unfiltered), so
no "not found" flash guard is needed.

```swift
.confirmationDialog("Archive this checklist?", isPresented: $isArchiveConfirmPresented) {
    Button("Cancel", role: .cancel) {}
    Button("Archive Checklist", role: .destructive) {
        store.archive(id: checklistID)
        dismiss()
    }
    .accessibilityIdentifier("confirmArchiveChecklistButton")
} message: {
    Text("You can restore it later from Settings.")
}
```

#### 5. Localization — Phase 1 strings (App catalog)
**Files**: `CheckStitch/Localizable.xcstrings`, `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add these three keys to the App catalog and to
`LocalizationFixtures.requiredKeys` `("App", [...])`. Each key carries
`"extractionState": "manual"` and six `stringUnit.value` entries.

JSON shape (all keys identical shape; insert alphabetically/next to peers):

```json
"Archive Checklist" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Archive Checklist" } },
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Checkliste archivieren" } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Archivar lista" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Archiver la liste" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "チェックリストをアーカイブ" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "归档清单" } }
  }
}
```

| Key | de | es | fr | ja | zh-Hans |
| --- | --- | --- | --- | --- | --- |
| `Archive Checklist` | `Checkliste archivieren` | `Archivar lista` | `Archiver la liste` | `チェックリストをアーカイブ` | `归档清单` |
| `Archive this checklist?` | `Diese Checkliste archivieren?` | `¿Archivar esta lista?` | `Archiver cette liste ?` | `このチェックリストをアーカイブしますか？` | `归档此清单？` |
| `You can restore it later from Settings.` | `Du kannst sie später in den Einstellungen wiederherstellen.` | `Puedes restaurarla más tarde en Ajustes.` | `Vous pouvez la restaurer plus tard dans Réglages.` | `後で設定から復元できます。` | `你可以稍后在“设置”中恢复。` |

No `excludedIdentities` entries (no non-English value equals English). The
overflow menu uses a bare system `Image` label, so no `"More"` key is needed.

### Verification

#### Automated
- [x] `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] `make test-unit` passes, including new tests below

#### New tests
- `CheckStitchTests/ChecklistCodecTests.swift` (XCTest, `@MainActor`):
  - [x] `testDecodesV5PayloadWithoutArchiveKeysAsActive` — a v5 payload omitting
    `isArchived`/`archivedAt` decodes `isArchived == false` / `archivedAt == nil`
    and still classifies `.loaded`.
  - [x] `testArchiveFlagsSurviveEnvelopeRoundTrip` — encode/decode preserves both.
- `CheckStitchTests/ChecklistStoreTests.swift` (XCTest, `@MainActor`):
  - [x] `testArchiveSetsBothFlagsAndBumpsClock` — archive sets `isArchived` +
    non-nil `archivedAt`, `revision + 1`, `modifiedAt == now()`.
  - [x] `testArchiveIsIdempotentNoOp` — a second archive returns `false` and
    leaves revision/date unchanged.
  - [x] `testArchivedChecklistStillResolvesByID` — `checklist(id:)` returns it;
    `activeChecklists` excludes it; `archivedChecklists` includes it.
  - [x] `testArchivePersistsAcrossReload`.
- `CheckStitchTests/ChecklistListViewModelTests.swift`:
  - [x] `archivedChecklistsAreExcludedFromTheList`.
  - [x] `emptyStateFollowsActiveChecklists` (archiving the only checklist makes
    `checklists.isEmpty`).

#### Manual
- [ ] `make run`; create a checklist, open it, Archive from the overflow menu,
      confirm; it leaves the main list; kill and relaunch the app; it is still
      gone. Confirm no Reminders were created/deleted.

---

## Phase 2: Archive state converges across devices

**Vertical slice**: archive on one device → the checklist disappears on the
other (through the existing coarse-clock LWW merge). No codec change.

### Changes

#### 1. Merge the flags inside the existing coarse-clock block
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistMerge.swift`
**Action**: modify

Inside `mergedChecklists`'s single `if wins(...)` block (alongside
`name`/`destinationListIdentifier`/`prefixesReminderNumbers`/`showsOnWatch`/
`folderID`/`revision`/`modifiedAt`) add:

```swift
merged.isArchived = remoteChecklist.isArchived
merged.archivedAt = remoteChecklist.archivedAt
```

No new clock, no `ChecklistMerge` signature change, no per-field `if wins(...)`.

### Verification

#### Automated
- [x] `make test-unit` passes, including new tests below

#### New tests
- `CheckStitchTests/ChecklistMergeTests.swift` (Swift Testing, `@MainActor`):
  - [x] `archiveFlagIsCopiedWhenRemoteWins` — remote has higher revision and
    `isArchived == true`; merged result archived.
  - [x] `archiveFlagIsCopiedWhenLocalWins` — local higher revision; merged stays
    active (remote's archive loses).
  - [x] `concurrentRenameSupersedesAnArchive` — local rename with later
    `modifiedAt` beats remote's archive: merged stays active + renamed.
  - [x] `archiveConvergesInEitherArgumentOrder` — merging the same pair with
    `local`/`remote` swapped yields equal archive flags (symmetry/idempotence).
  - [x] `tombstoneSuppressesArchivedRecord` — a whole-checklist tombstone beats
    an archived live record.

#### Manual
- [ ] Not manually reproducible without two devices; rely on unit evidence.

---

## Phase 3: Archived Checklists screen with Restore

**Vertical slice**: Settings gains an **Archived Checklists** screen listing
archived checklists (newest first, nil last) with swipe **Restore**; restoring a
name that collides with an active checklist auto-renames via `uniqueName`.

### Changes

#### 1. Restore + archive-aware uniqueness
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

`sameName` is a pure two-string predicate and cannot know about archive state, so
archive-awareness lives at the enumeration call sites. Introduce a small private
helper and switch every uniqueness enumeration to it:

```swift
/// Names an active checklist currently owns. Archived names are deliberately
/// free: an active checklist may reuse the name of an archived one.
private var activeNames: [String] { activeChecklists.map(\.name) }
```

- `create(name:)`, `duplicate(id:name:)`, `importInsert(_:as:)` — replace
  `checklists.map(\.name)` with `activeNames`.
- `conflictingChecklist(named:)` — filter `activeChecklists` instead of
  `checklists`.
- `rename(id:to:)`'s collider guard — add `&& !$0.isArchived`:
  `checklists.first(where: { $0.id != id && !$0.isArchived && Self.sameName($0.name, name) })`.

Add `restore(id:)` — clears both flags, auto-renames on a collision against an
active checklist, bumps the coarse clock.

```swift
/// Restores an archived checklist. When its name now collides with an active
/// checklist the name is disambiguated through `uniqueName`. Unknown or
/// already-active ids are a no-op returning `false`.
@discardableResult
public func restore(id: UUID) -> Bool {
    guard let index = checklists.firstIndex(where: { $0.id == id }),
          checklists[index].isArchived else { return false }
    if conflictingChecklist(named: checklists[index].name) != nil {
        checklists[index].name = Self.uniqueName(
            basedOn: checklists[index].name,
            taken: activeNames.filter { $0 != checklists[index].name })
    }
    checklists[index].isArchived = false
    checklists[index].archivedAt = nil
    checklists[index].revision += 1
    checklists[index].modifiedAt = now()
    save()
    return true
}
```

Note: `conflictingChecklist` excludes the still-archived target automatically, so
the collision check is against active checklists only.

#### 2. Archived screen
**File**: `CheckStitch/ArchivedChecklistsView.swift`
**Action**: create

Model on the pushed-subscreen precedent (`PrivacySettingsView`/`AboutView`):
`Form`/`ForEach`, `.navigationTitle(...)`, `.settingsSubscreenLayout()`. Reads the
store from the environment (already injected by `MyApp`; the Settings sheet
inherits it).

```swift
import CheckStitchCore
import SwiftUI

/// The only surface that lists archived checklists. Rows show the name and the
/// archive date; swipe to Restore or Delete Permanently (Phase 4).
struct ArchivedChecklistsView: View {
    @Environment(ChecklistStore.self) private var store

    var body: some View {
        Form {
            if store.archivedChecklists.isEmpty {
                ContentUnavailableView("No Archived Checklists", systemImage: "archivebox")
            } else {
                ForEach(store.archivedChecklists) { checklist in
                    VStack(alignment: .leading) {
                        Text(checklist.name)
                        if let archivedAt = checklist.archivedAt {
                            Text("Archived \(archivedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            store.restore(id: checklist.id)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("Archived Checklists")
        .settingsSubscreenLayout()
    }
}
```

`store.archivedChecklists` is already sorted newest-first (Phase 1), so no
view-side sort. `"Archived %@"` is produced by the `Text("Archived \(String)")`
interpolation.

#### 3. Settings entry
**File**: `CheckStitch/SettingsView.swift`
**Action**: modify

Add a new `Section` (place it after the Interface section, before Import and
Export):

```swift
Section {
    NavigationLink {
        ArchivedChecklistsView()
    } label: {
        Label("Archived Checklists", systemImage: "archivebox")
    }
    .accessibilityIdentifier("settingsArchivedRow")
}
```

#### 4. Localization — Phase 3 strings (App catalog)
**Files**: `CheckStitch/Localizable.xcstrings`, `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add four keys (same JSON shape as Phase 1) + `requiredKeys` entries.

| Key | de | es | fr | ja | zh-Hans |
| --- | --- | --- | --- | --- | --- |
| `Archived Checklists` | `Archivierte Checklisten` | `Listas archivadas` | `Listes archivées` | `アーカイブ済みチェックリスト` | `已归档的清单` |
| `Restore` | `Wiederherstellen` | `Restaurar` | `Restaurer` | `復元` | `恢复` |
| `No Archived Checklists` | `Keine archivierten Checklisten` | `No hay listas archivadas` | `Aucune liste archivée` | `アーカイブ済みチェックリストはありません` | `没有已归档的清单` |
| `Archived %@` | `Archiviert am %@` | `Archivada el %@` | `Archivée le %@` | `%@ にアーカイブ` | `归档于 %@` |

No `excludedIdentities` entries.

### Verification

#### Automated
- [x] `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] `make test-unit` passes
- [x] `make build-mac` compiles the new view (macOS leg of the gate)

#### New tests
- `CheckStitchTests/ChecklistStoreTests.swift`:
  - [x] `testRestoreClearsBothFlagsAndBumpsClock`.
  - [x] `testRestoreIsIdempotentNoOp` — restoring an active/unknown id returns
    `false` unchanged.
  - [x] `testRestoreAutoRenamesOnActiveCollision` — archived "Groceries" +
    active "Groceries" → restored name "Groceries 2".
  - [x] `testActiveChecklistMayReuseAnArchivedName` — `create`/`rename`/`importInsert`
    accept a name only an archived checklist owns; `conflictingChecklist` returns
    nil for it.
  - [x] `testArchivedChecklistsSortNewestFirstNilLast`.

#### Manual
- [ ] `make run`; archive two checklists; Settings → Archived Checklists lists
      both newest-first; swipe Restore pops one back to the main list with its
      items intact; archive "X" + create active "X", restore → appears as "X 2".

---

## Phase 4: Permanent delete from the archived screen

**Vertical slice**: delete an archived checklist forever behind a destructive
confirmation — remove the record and tombstone it so sync can never resurrect it.

### Changes

#### 1. `removeArchived(id:)`
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

Exact mirror of `delete(id:)`'s tombstone shape.

```swift
/// Permanently removes a checklist and tombstones the deletion at
/// `revision + 1`, so sync can never resurrect it. Intended for the Archived
/// screen; unknown ids are a no-op returning `false`.
@discardableResult
public func removeArchived(id: UUID) -> Bool {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return false }
    let removed = checklists.remove(at: index)
    tombstones.append(ChecklistTombstone(
        checklistID: id, itemID: nil, deletedAt: now(), revision: removed.revision + 1))
    save()
    return true
}
```

#### 2. Destructive swipe + confirmation
**File**: `CheckStitch/ArchivedChecklistsView.swift`
**Action**: modify

Add `@State private var pendingDeletion: UUID?`; add a destructive
`swipeActions` button alongside Restore and a `.confirmationDialog`:

```swift
Button(role: .destructive) {
    pendingDeletion = checklist.id
} label: {
    Label("Delete Permanently", systemImage: "trash")
}
```

```swift
.confirmationDialog(
    "Delete Permanently",
    isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } }),
    presenting: pendingDeletion
) { id in
    Button("Cancel", role: .cancel) { pendingDeletion = nil }
    Button("Delete Permanently", role: .destructive) {
        store.removeArchived(id: id)
        pendingDeletion = nil
    }
}
```

#### 3. Localization — Phase 4 string (App catalog)
**Files**: `CheckStitch/Localizable.xcstrings`, `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

| Key | de | es | fr | ja | zh-Hans |
| --- | --- | --- | --- | --- | --- |
| `Delete Permanently` | `Endgültig löschen` | `Eliminar permanentemente` | `Supprimer définitivement` | `完全に削除` | `永久删除` |

Add to `requiredKeys`. No `excludedIdentities` entry.

### Verification

#### Automated
- [x] `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] `make test-unit` passes

#### New tests
- `CheckStitchTests/ChecklistStoreTests.swift`:
  - [x] `testRemoveArchivedTombstonesAtRevisionPlusOne` — record gone, tombstone
    has `checklistID`, `itemID == nil`, `revision == removed.revision + 1`.
  - [x] `testRemoveArchivedIsIdempotentNoOp` — second call `false`, no second
    tombstone.
- `CheckStitchTests/ChecklistMergeTests.swift`:
  - [x] `tombstonedArchivedRecordStaysDeleted` — a tombstone + an archived remote
    record converge deleted; a re-merge does not resurrect it.

#### Manual
- [ ] `make run`; archive a checklist, swipe Delete Permanently, confirm; it is
      gone from the Archived screen after relaunch and a merge; no Reminders
      touched.

---

## Phase 5: Archived checklists are invisible everywhere else

**Vertical slice**: one capability — archival — applied across the remaining
enumeration sites: watch, export, Siri/App Intents, widgets.

### Changes

#### 1. Watch `visible*` predicates
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Add `!$0.isArchived` to all three helpers so folder-collapse behavior is
inherited. `WatchChecklistViewModel` and `WatchChecklistListView` are unchanged.

```swift
public static func visibleLooseChecklists(
    _ checklists: [Checklist], knownFolderIDs: Set<UUID>
) -> [Checklist] {
    checklists.filter { isLoose($0, knownFolderIDs: knownFolderIDs) && $0.showsOnWatch && !$0.isArchived }
}

public static func visibleChecklists(
    in folder: Folder, from checklists: [Checklist]
) -> [Checklist] {
    checklists.filter { $0.folderID == folder.id && $0.showsOnWatch && !$0.isArchived }
}

public static func visibleFolders(
    _ folders: [Folder], checklists: [Checklist]
) -> [Folder] {
    folders.filter { folder in
        let members = checklists.filter { $0.folderID == folder.id }
        return members.isEmpty || members.contains { $0.showsOnWatch && !$0.isArchived }
    }
}
```

#### 2. Export rows + selection
**Files**: `CheckStitch/ExportChecklistsView.swift`,
`CheckStitch/ChecklistImportExportViewModel.swift`
**Action**: modify

```swift
// ExportChecklistsView — rows
rows: store.activeChecklists.map {
    ChecklistSelectionRow(id: $0.id, name: $0.name, detail: nil)
},
```

```swift
// ChecklistImportExportViewModel — exportSelected() and shareSelected()
let selected = store.activeChecklists.filter { exportSelection.contains($0.id) }
```

#### 3. Entity query (Siri/App Intents)
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistEntity.swift`
**Action**: modify

Switch all three methods from `currentStore().checklists` to
`currentStore().activeChecklists`:
`entities(for:)` (filter), `entities(matching:)` (filter), `suggestedEntities()`
(map).

#### 4. Run intent guard
**File**: `CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift`
**Action**: modify

Add the explicit guard after the existing id-resolution guard (belt-and-braces;
no new error string):

```swift
guard let uuid = UUID(uuidString: checklist.id),
      let stored = store.checklist(id: uuid),
      !stored.isArchived
else { throw RunChecklistIntentError.checklistNotFound }
```

#### 5. Widget display model
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistWidgetDisplayModel.swift`
**Action**: modify

Exclude archived in both the resolution map and `hasChecklists`, so an archived
configured id is unresolvable and falls into the existing empty state:

```swift
let visible = checklists.filter { !$0.isArchived }
let byID = Dictionary(visible.map { ($0.id.uuidString, $0) },
                      uniquingKeysWith: { first, _ in first })
// ...
self.hasChecklists = !visible.isEmpty
```

### Verification

#### Automated
- [x] `make test-unit` passes
- [x] `make watch-build` compiles (watchOS slice) and `make widget-build`
      compiles (widget slice)

#### New tests
- `CheckStitchTests/ChecklistGroupingTests.swift`:
  - [x] `archivedChecklistIsHiddenFromVisibleLooseChecklists`.
  - [x] `archivedChecklistIsHiddenFromVisibleFolderMembers`.
  - [x] `folderOfOnlyArchivedMembersIsHidden`.
- `CheckStitchTests/ChecklistListViewModelTests.swift`:
  - [x] `archivedChecklistsAreHiddenInsideFolders` (folder `checklists(in:)`).
- `CheckStitchTests/ChecklistEntityQueryTests.swift` (`@MainActor`, Swift Testing):
  - [x] `entitiesForIdentifiersExcludeArchived`.
  - [x] `entitiesMatchingExcludesArchived`.
  - [x] `suggestedEntitiesExcludesArchived`.
- `CheckStitchTests/RunChecklistIntentTests.swift`:
  - [x] `archivedChecklistThrowsNotFound`.
- `CheckStitchTests/ChecklistWidgetDisplayModelTests.swift`:
  - [x] `archivedConfiguredChecklistProducesNoRows`.
  - [x] `hasChecklistsIsFalseWhenOnlyArchivedAreConfigured`.

#### Manual
- [ ] Not device-verifiable here; the gate's watch/widget builds plus unit
      evidence are the proof. State this in the completion artifact.

---

## Phase 6: Import lands active + hardening

**Vertical slice**: imported checklists always arrive active; pin the accepted
edge cases; run the full gate.

### Changes

#### 1. `freshCopy` strips archive state
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

`freshCopy` already constructs a new `Checklist` whose init defaults are
`isArchived = false` / `archivedAt = nil`, so imports are active by default. Make
it explicit (and future-proof) by passing the two params:

```swift
private func freshCopy(of checklist: Checklist) -> Checklist {
    Checklist(
        name: checklist.name,
        items: /* unchanged */,
        destinationListIdentifier: checklist.destinationListIdentifier,
        prefixesReminderNumbers: checklist.prefixesReminderNumbers,
        showsOnWatch: checklist.showsOnWatch,
        isArchived: false,
        archivedAt: nil,
        modifiedAt: now(),
        revision: 1
    )
}
```

No change needed to `importInsert`/`importReplace` beyond their existing use of
`freshCopy`.

#### 2. Pin the accepted risks in tests
**Files**: `CheckStitchTests/ChecklistImportSessionTests.swift`,
`CheckStitchTests/ChecklistCodecTests.swift`
**Action**: modify (tests only)

### Verification

#### Automated
- [x] `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] `bash scripts/test.sh` prints `gate: ok` (the release gate)

#### New tests
- `CheckStitchTests/ChecklistImportSessionTests.swift` (Swift Testing):
  - [x] `importInsertLandsActive` — an archived source imports with
    `isArchived == false` / `archivedAt == nil` (Keep Both).
  - [x] `importReplaceLandsActive` — Replace also lands active.
- `CheckStitchTests/ChecklistCodecTests.swift` (XCTest):
  - [x] `testV5PayloadWithoutArchiveKeysStaysLoaded` — downgrade/absent-key
    classification is `.loaded` (documents the accepted downgrade risk).

#### Manual
- [ ] n/a (full gate).

---

## Full-file checklist (every file named in structure.md)

| File | Phase | Action |
| --- | --- | --- |
| `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` | 1, 5 | modify |
| `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift` | 1, 3, 4, 6 | modify |
| `CheckStitch/ChecklistListViewModel.swift` | 1, 5 | modify |
| `CheckStitch/ChecklistDetailView.swift` | 1 | modify |
| `CheckStitch/Localizable.xcstrings` | 1, 3, 4 | modify |
| `CheckStitchTests/LocalizationFixtures.swift` | 1, 3, 4 | modify |
| `CheckStitchCore/Sources/CheckStitchCore/ChecklistMerge.swift` | 2 | modify |
| `CheckStitch/ArchivedChecklistsView.swift` | 3, 4 | create |
| `CheckStitch/SettingsView.swift` | 3 | modify (structure said `ContentView.swift`) |
| `CheckStitch/ExportChecklistsView.swift` | 5 | modify |
| `CheckStitch/ChecklistImportExportViewModel.swift` | 5 | modify |
| `CheckStitchCore/Sources/CheckStitchCore/ChecklistEntity.swift` | 5 | modify |
| `CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift` | 5 | modify |
| `CheckStitchCore/Sources/CheckStitchCore/ChecklistWidgetDisplayModel.swift` | 5 | modify |
| `CheckStitchTests/ChecklistCodecTests.swift` | 1, 6 | modify |
| `CheckStitchTests/ChecklistStoreTests.swift` | 1, 3, 4 | modify |
| `CheckStitchTests/ChecklistListViewModelTests.swift` | 1, 5 | modify |
| `CheckStitchTests/ChecklistMergeTests.swift` | 2, 4 | modify |
| `CheckStitchTests/ChecklistGroupingTests.swift` | 5 | modify |
| `CheckStitchTests/ChecklistEntityQueryTests.swift` | 5 | modify |
| `CheckStitchTests/RunChecklistIntentTests.swift` | 5 | modify |
| `CheckStitchTests/ChecklistWidgetDisplayModelTests.swift` | 5 | modify |
| `CheckStitchTests/ChecklistImportSessionTests.swift` | 6 | modify |
| `CheckStitchTests/ChecklistExportTests.swift` | 6 | modify (only if an export-selection assertion needs the active set; otherwise no change) |

## Deviations from structure.md

1. **Settings row file**: structure said `CheckStitch/ContentView.swift`; the
   actual Settings rows live in `CheckStitch/SettingsView.swift`. Phase 3 adds the
   `NavigationLink` there.
2. **`ChecklistListViewModel.checklists(in:)`** must also read
   `activeChecklists` (structure only named the `checklists` property). Without
   it, archived checklists filed in folders stay visible on the phone in Phase 1.
3. **Uniqueness**: `sameName` is a pure two-string predicate and cannot be made
   archive-aware; archive-awareness is applied at the enumeration sites via a new
   private `activeNames` helper, `conflictingChecklist`, and `rename`'s collider
   guard. This preserves design decision 4's intent.
4. **`ChecklistExportTests.swift`**: listed in structure Phase 6, but the export
   selection change already lands in Phase 5; add/adjust an assertion there only
   if the existing suite reads `store.checklists` directly. Otherwise it stays
   untouched.
