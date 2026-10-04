# Design Discussion

## Current State

`Checklist` (`Checklist.swift:145`) is an `Identifiable, Codable, Hashable, Sendable`
struct whose stored fields are `id`, `name`, `items`, `destinationListIdentifier`,
`prefixesReminderNumbers`, `showsOnWatch`, `folderID`, `modifiedAt`, `revision`,
`itemOrder`, `orderRevision`, `orderModifiedAt`. Every additive/optional field
decodes with `decodeIfPresent` + a `??` default (`Checklist.swift:214-241`) and
encodes unconditionally (`:245-267`); `folderID` nil writes `encodeNil` rather
than omitting the key. `ChecklistCodec.currentVersion = 5` (`:478`) and `classify`
(`:504-536`) yields `loaded` / `migratable` / `unsupportedVersion` / `unreadable`.
The `showsOnWatch` / `prefixesReminderNumbers` fields were added additively with
no version bump (`:178-182,220-225`) — the exact precedent for archive flags.

`ChecklistStore` mutations bump a coarse `revision`/`modifiedAt` clock and save:
`rename` (`ChecklistStore.swift:232-243`), `setDestination` (`:246-255`), the
toggles (`:258-296`), `moveChecklist` (`:528-540`). Permanent delete creates a
`ChecklistTombstone(checklistID, itemID: nil, deletedAt: now(), revision+1)` then
saves (`:611-617`). Name uniqueness lives in `sameName` (`:321-325`),
`conflictingChecklist` (`:139-141`) and `uniqueName` (`:308-319`); import identity
is `freshCopy` (`:188-205`). `apply(remote:)` guards `canOverwriteStoredPayload`
and `remote.version == currentVersion` before merging (`:619-645`).

`ChecklistMerge.mergedChecklists` (`ChecklistMerge.swift:130-191`) copies the
whole coarse record inside one `if wins(...)` block (name, destination, prefixes,
showsOnWatch, folderID, revision, modifiedAt at `:166-171`); only `ChecklistItem`
has per-field clocks (`:223-243`). Tombstones unconditionally suppress (`:5-8`).

Enumerations are unfiltered everywhere except the watch: the phone main list reads
`store.checklists` (`ChecklistListViewModel.swift:17`), export rows map
`store.checklists` (`ExportChecklistsView.swift:25-29`), all three
`ChecklistEntityQuery` methods read `store.checklists`
(`ChecklistEntityQuery.swift:45-61`), and the widget resolves configured ids into
the store display model (`ChecklistWidgetDisplayModel.swift:46-60`). The only
filter today is `showsOnWatch`, confined to `ChecklistGrouping.visibleLooseChecklists`
/ `visibleChecklists(in:)` / `visibleFolders` (`Checklist.swift:596-633`).
`RunChecklistIntent` refuses by absence — `store.checklist(id:)` nil throws
`.checklistNotFound` (`RunChecklistIntent.swift:56-58`).

Settings subscreens are pushed `NavigationLink` rows using
`.settingsSubscreenLayout()` (research Q5); `SettingsViewModel` does not enumerate
checklists. `ChecklistDetailView` resolves its model by id
(`ChecklistDetailView.swift:44`). Localization is four catalogs, six languages
(`en, de, es, fr, ja, zh-Hans`), each new key joined in
`LocalizationFixtures.requiredKeys` and checked by `scripts/l10n-check.sh`.

## Desired End State

A checklist can be archived instead of deleted. Archiving hides it from the phone
main list, the watch, the widget, export, Siri/App Intents and the run path, but
keeps the record and its `isArchived`/`archivedAt` flags synced through the
existing merge. An **Archived Checklists** screen in Settings is the only surface
that lists archived checklists, offering Restore and permanent Delete. Archive
never touches Reminders: it is reversible bookkeeping only.

Correctness is verified by: `make test-unit` (store, codec, merge, widget, query,
grouping, intent, localization suites), `bash scripts/l10n-check.sh`, and the full
`bash scripts/test.sh` gate printing `gate: ok`.

## Patterns to Follow

- **Additive optional field, no version bump** — `showsOnWatch`,
  `prefixesReminderNumbers`, `folderID`: `CodingKeys` entry, `decodeIfPresent` +
  `?? default`, unconditional `encode` (`Checklist.swift:208-267`).
- **Coarse-clock structural mutation** — `revision += 1`, `modifiedAt = now()`,
  unchanged-guard, structural `save()`; model on `rename`/`setDestination`
  (`ChecklistStore.swift:232-255`).
- **Permanent delete tombstones** — `ChecklistTombstone(... revision + 1)` then
  remove and save, matching `delete(id:)` (`ChecklistStore.swift:611-617`).
- **Uniqueness / import chokepoints** — `uniqueName`/`conflictingChecklist`/
  `sameName` (`ChecklistStore.swift:139-141,308-325`) and `freshCopy`
  (`:188-205`) are the only places archive-aware name/import rules go.
- **Merge coarse block** — new checklist-level fields ride the single
  `if wins(...)` copy (`ChecklistMerge.swift:166-171`), never a new clock.
- **Settings subscreen** — `NavigationLink` row + `.settingsSubscreenLayout()`
  (Background/Interface/Privacy precedent, research Q5).
- **Localization cascade** — `.xcstrings` (six values) → `requiredKeys` →
  `scripts/l10n-check.sh` → `make test-unit` (conventions.md).

Patterns **not** to follow: per-field clocks (item-only machinery), filtering ad
hoc at each consumer, bumping `ChecklistCodec.currentVersion`, and any archived
copy leaking into the watch (the phone intentionally pushes all records —
research Q5).

## Design Decisions

1. **Additive fields, no version bump**: add `isArchived: Bool` (default `false`)
   and `archivedAt: Date?` (default nil) via `decodeIfPresent`, encode
   unconditionally, `currentVersion` stays 5 — follows the `showsOnWatch`
   precedent and keeps old payloads classifying `loaded`.
2. **Single filtering chokepoint**: add `ChecklistStore.activeChecklists` and
   `ChecklistStore.archivedChecklists` computed from `checklists`; `checklists`
   stays the full set for persistence/sync. Every consumer (phone list, export,
   query, widget) reads the appropriate property instead of `store.checklists`.
3. **Store op semantics**: `archive(id:)` sets flags + bumps the coarse clock with
   an unchanged-guard; `restore(id:)` clears flags, applies `uniqueName` on a
   collision, and bumps the clock; `removeArchived(id:)` tombstones at
   `revision + 1` then removes, exactly like `delete(id:)`.
4. **Uniqueness excludes archived**: `sameName`/`conflictingChecklist` skip
   `isArchived` records so an active checklist may reuse an archived name; restore
   resolves the reverse collision by auto-renaming via `uniqueName`.
5. **`freshCopy` strips the flags**: imported checklists (Keep Both and Replace)
   always land active with `archivedAt = nil`.
6. **Merge rides the coarse clock**: `isArchived`/`archivedAt` are copied inside
   the existing `if wins(...)` block; no per-field clocks. A concurrent rename
   that wins the coarse clock legitimately supersedes an archive.
7. **Watch filter in the `visible*` predicates**: add `!checklist.isArchived`
   alongside `showsOnWatch` so folder-collapse behavior is inherited;
   `WatchChecklistViewModel` is unchanged.
8. **Run/query/widget refusal by absence**: all three `ChecklistEntityQuery`
   methods exclude archived; `RunChecklistIntent.perform()` adds an explicit
   `guard !stored.isArchived else { throw .checklistNotFound }`; the widget treats
   an archived configured id as unresolvable and falls into its empty state. No
   new error string.
9. **Archive action in `ChecklistDetailView`**: a toolbar overflow menu item
   ("Archive Checklist") opening a confirmation dialog; confirm calls
   `store.archive` then dismisses the pushed detail. `store.checklist(id:)` stays
   unchanged so restore/test reads still resolve archived records.
10. **Archived screen**: a Settings `NavigationLink` to a pushed "Archived
    Checklists" screen; rows sorted by `archivedAt` descending (nil last) showing
    name + `"Archived %@"`; trailing `swipeActions` Restore and a confirmed,
    destructive Delete (`"Delete Permanently"`); a plain empty state. No bulk
    delete.
11. **Eight new App-catalog strings**: `"Archived Checklists"` (row + title),
    `"Archive Checklist"`, `"Archive this checklist?"`,
    `"You can restore it later from Settings."`, `"Restore"`,
    `"Delete Permanently"`, `"No Archived Checklists"`, `"Archived %@"` — each
    with six values + a `LocalizationFixtures.requiredKeys["App"]` entry.
12. **Test plan**: store (`ChecklistStoreTests`) for flag/clock/idempotence,
    restore rename, tombstoned remove, uniqueness, `freshCopy`; codec
    (`ChecklistCodecTests`) for absent-key defaults, round-trip, still
    `.loaded`/5; merge (`ChecklistMergeTests`) for clock wins/loss, tombstone
    suppression, convergence; widget/query
    (`ChecklistWidgetDisplayModelTests`, `ChecklistEntityQueryTests`) for
    exclusion; grouping (`ChecklistGroupingTests`) for the watch predicate;
    intent (`RunChecklistIntentTests`) for the archived guard; localization
    fixtures. No new UI smoke.

## What We're NOT Doing

- **No codec version bump** and no migration path — the flags are additive
  optionals; an older build decoding and re-encoding them drops them.
- **No per-field revision clocks** for archive state — that machinery stays
  item-only.
- **No new error/dialog strings beyond the eight** — no "Restored" toast, no
  separate delete-confirmation copy, no archived-specific run error.
- **No bulk "Delete All"** affordance on the archived screen.
- **No Reminders interaction** — archive/restore/delete never calls EventKit.
- **No ad hoc filtering** at individual consumers in place of the store
  properties.
- **No new watch-localized strings** — the watch merely hides archived records.
- **No new UI smoke test**; unit/build legs are the evidence.

## Open Risks

- **Downgrade data loss**: an older build classifies the payload `loaded`, drops
  the flags, and re-encodes on its next save, silently un-archiving checklists.
  Accepted intentionally by the no-bump decision.
- **Concurrent edit beats archive**: a rename on another device with a later
  `modifiedAt` wins the coarse clock and loses the archive. Documented and tested
  as intended LWW behavior.
- **`archivedAt == nil` records**: the sort must be total; nil (e.g. a hand-written
  payload) sorts last and renders without a date.
- **Stale widget/Siri configuration** pointing at an archived id: covered by the
  query filter + widget unresolvable branch, but the empty-state copy chosen for
  that case should be confirmed during implementation.
- **Settings registration**: research Q5 did not trace the Settings row
  registration end-to-end; the new subscreen must follow the existing
  `NavigationLink` + `.settingsSubscreenLayout()` shape.
- **Exact JSON key spellings** for `isArchived`/`archivedAt` in `CodingKeys` were
  not enumerated by research (`Checklist.swift:208-209`); follow the surrounding
  camelCase convention.
