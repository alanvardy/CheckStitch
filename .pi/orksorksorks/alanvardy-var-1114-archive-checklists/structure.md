# Structure Outline

## Approach
Archive is additive bookkeeping on the existing coarse-clock `Checklist` record:
two additive optional fields (`isArchived`, `archivedAt`) with no codec version
bump, a `ChecklistStore` chokepoint pair (`archive`/`restore`/`removeArchived`)
plus the `activeChecklists`/`archivedChecklists` filters, and a Settings subscreen.
No schema migration or horizontal refactor is needed — every slice below is
vertical and lands green on its own. New localized strings ship inside the slice
that introduces them (never a trailing localization phase).

## Phase 1: Walking skeleton — archive one checklist and watch it leave the main list
User taps **Archive** in a checklist's detail screen; it vanishes from the phone
main list and is still gone after relaunch (flags persisted in the store payload).

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`,
`CheckStitchCore/Sources/CheckStitchCore/ChecklistListViewModel.swift`,
`CheckStitch/ChecklistDetailView.swift`,
`CheckStitch/Localizable.xcstrings` + `CheckStitchTests/LocalizationFixtures.swift`
(3 strings: `"Archive Checklist"`, `"Archive this checklist?"`,
`"You can restore it later from Settings."`).

**Key changes**:
- `Checklist.isArchived: Bool` (default `false`), `Checklist.archivedAt: Date?` (default nil) — `CodingKeys` entries, `decodeIfPresent ?? default`, unconditional `encode`; `currentVersion` stays 5.
- `ChecklistStore.activeChecklists: [Checklist]` / `archivedChecklists: [Checklist]` — computed from `checklists` (which stays the full set).
- `ChecklistStore.archive(id: UUID) -> Bool` — unchanged-guard, set flags, `revision += 1`, `modifiedAt = now()`, structural `save()`; mirrors `rename`'s shape but saves immediately.
- `ChecklistListViewModel.checklists` reads `store.activeChecklists`; `ChecklistDetailView` gains a toolbar overflow `Menu` + `confirmationDialog` calling `store.archive` then dismissing.

**Contract**: the two field names/semantics, `activeChecklists`/`archivedChecklists`,
and `archive(id:) -> Bool`. Later slices depend only on these — never on the
view's internals.

**Tests**: `ChecklistCodecTests` (absent-key defaults, round-trip, still `.loaded`/5);
`ChecklistStoreTests` (archive sets both flags + bumps clock, idempotent no-op, `checklist(id:)` still resolves the archived record); `ChecklistListViewModelTests` (archived excluded from `checklists`, empty-state follows). Localization fixtures for the 3 keys.
**Verify**: `make test-unit` green; `bash scripts/l10n-check.sh` prints `l10n-check: ok`.

---

## Phase 2: Archive state converges across devices (front-loaded sync risk)
Archive on one device; the checklist disappears on the other. A concurrent rename
that wins the coarse clock legitimately supersedes the archive (documented LWW).

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistMerge.swift`, `CheckStitchTests/ChecklistMergeTests.swift`.

**Key changes**:
- `ChecklistMerge.mergedChecklists` copies `isArchived`/`archivedAt` inside the existing single `if wins(...)` block alongside name/destination/flags — no new clock, no codec change.

**Contract**: checklist-level archive state rides the coarse LWW clock; conflict
resolution is "later `revision`/`modifiedAt` wins, then smaller `deviceID`".

**Tests**: `ChecklistMergeTests` — flags copied when remote wins and when local wins; concurrent rename supersedes the archive; convergence/idempotence; a tombstone still suppresses an archived record.
**Verify**: `make test-unit` green.

---

## Phase 3: Archived Checklists screen with Restore
Settings gains an **Archived Checklists** screen listing archived checklists (newest
`archivedAt` first, nil last) with a swipe **Restore**; restoring a name that now
collides with an active checklist auto-renames via `uniqueName`.

**Files**: `ChecklistStore.swift` (`sameName`/`conflictingChecklist`/`restore`),
new `CheckStitch/ArchivedChecklistsView.swift`, the Settings entry in
`CheckStitch/ContentView.swift`, `.xcstrings` + fixtures (4 strings:
`"Archived Checklists"`, `"Restore"`, `"No Archived Checklists"`, `"Archived %@"`).

**Key changes**:
- `ChecklistStore.sameName`/`conflictingChecklist` skip `isArchived` records, so an active checklist may reuse an archived name.
- `ChecklistStore.restore(id: UUID) -> Bool` — unchanged-guard; when the name collides, rewrite via `uniqueName(basedOn:taken:)`; clear flags, `revision += 1`, `modifiedAt = now()`, `save()`.
- `ArchivedChecklistsView` — `NavigationLink` row + `.settingsSubscreenLayout()`, rows `"Archived %@"`, empty state, `swipeActions` Restore.

**Contract**: `restore(id:)` semantics (clear flags, auto-rename on collision) and
the archived screen as the sole listing surface. Rows consume `store.archivedChecklists`.

**Tests**: `ChecklistStoreTests` (restore clears flags + clock, idempotent; restore auto-renames on collision; uniqueness ignores archived); localization fixtures.
**Verify**: `make test-unit` + `bash scripts/l10n-check.sh` green.

---

## Phase 4: Permanent delete from the archived screen
Delete an archived checklist forever, behind a destructive confirmation — remove
the record and tombstone it so sync can never resurrect it.

**Files**: `ChecklistStore.swift`, `ArchivedChecklistsView.swift`, `.xcstrings` + fixtures (`"Delete Permanently"`).

**Key changes**:
- `ChecklistStore.removeArchived(id: UUID) -> Bool` — appends `ChecklistTombstone(checklistID, itemID: nil, deletedAt: now(), revision: removed.revision + 1)`, removes, `save()`; exact mirror of `delete(id:)`.
- `ArchivedChecklistsView` destructive `swipeActions` + `confirmationDialog`.

**Contract**: permanent delete creates the standard whole-checklist tombstone;
restore/archive never do.

**Tests**: `ChecklistStoreTests` (tombstone at `revision + 1`, record removed, idempotent); `ChecklistMergeTests` (tombstoned archived record stays deleted).
**Verify**: `make test-unit` green.

---

## Phase 5: Archived checklists are invisible everywhere else
Archived checklists disappear from the watch, export selection, Siri/App Intents
and widgets — one capability across the remaining enumeration sites.

**Files**: `Checklist.swift` (`visible*` predicates),
`ExportChecklistsView.swift` + `ChecklistImportExportViewModel.swift`,
`ChecklistEntityQuery.swift`, `RunChecklistIntent.swift`,
`ChecklistWidgetDisplayModel.swift`, plus the matching test suites.

**Key changes**:
- `visibleLooseChecklists` / `visibleChecklists(in:)` / `visibleFolders` add `!checklist.isArchived`; `WatchChecklistViewModel` unchanged.
- Export selection maps `store.activeChecklists` instead of `store.checklists`.
- All three `ChecklistEntityQuery` methods exclude archived ids.
- `RunChecklistIntent.perform()` adds `guard !stored.isArchived else { throw .checklistNotFound }` (no new error string).
- `ChecklistWidgetDisplayModel` treats an archived configured id as unresolvable and falls into its existing empty state.

**Contract**: archived records are invisible to watch/export/query/run/widget;
`store.checklist(id:)` stays unfiltered so Phase 3's screen still resolves them.

**Tests**: `ChecklistGroupingTests` + `ChecklistListViewModelTests` (watch predicate); `ChecklistEntityQueryTests` (entities/matching/suggested); `RunChecklistIntentTests` (archived guard throws); `ChecklistWidgetDisplayModelTests` (`hasChecklists` false when only archived are configured).
**Verify**: `make test-unit` green.

---

## Phase 6: Import lands active + hardening
Imported checklists always arrive active, and the edge cases are pinned; the full
gate is the checkpoint.

**Files**: `ChecklistStore.swift` (`freshCopy`), `ChecklistImportSessionTests.swift`, `ChecklistExportTests.swift`.

**Key changes**:
- `freshCopy` sets `isArchived = false`, `archivedAt = nil` for both Keep Both and Replace.
- Pin the accepted risks in tests: nil `archivedAt` sorts last (Phase 3), an older payload still classifies `.loaded` (downgrade accepted by design).

**Contract**: imports never carry archive state.

**Tests**: `ChecklistImportSessionTests` (importInsert + importReplace land active); codec downgrade classification.
**Verify**: `bash scripts/test.sh` prints `gate: ok` (the release gate).

---

## Testing Checkpoints
- After Phase 1: `make test-unit` + `l10n-check.sh` green → flags persist, main list hides.
- After Phase 2: `make test-unit` green → archive converges across merge.
- After Phase 3: `make test-unit` + `l10n-check.sh` green → screen lists/restores, names auto-rename.
- After Phase 4: `make test-unit` green → permanent delete tombstones.
- After Phase 5: `make test-unit` green → all consumers hide archived.
- After Phase 6: `bash scripts/test.sh` → `gate: ok`.
