# Design Discussion

## Current State

CheckStitch syncs `Checklist` / `Folder` / `ChecklistItem` values from the phone
to the Apple Watch as one serialized `ChecklistEnvelope`, versioned at
`currentVersion = 5` (`CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:465`).

- **Codec convention for additive booleans.** `Checklist.prefixesReminderNumbers`
  (`Checklist.swift:222,234,254-255,269`) is the precedent: decode
  `decodeIfPresent(Bool.self, ...) ?? <default>`, encode unconditionally, and
  **no** `currentVersion` bump. The version bumps only when the wire shape or a
  closed domain changes so an absent key can no longer be represented
  (research Q1). `Folder.isCollapsed` (`:284,294,300-301,306`) follows the same
  rule. Every existing stored boolean defaults to `false`.
- **Edit-checklist UI.** `CheckStitch/ChecklistDetailView.swift` is the sole
  edit-checklist screen; its Number Reminders toggle (`:70`, id
  `checklistPrefixNumbersToggle` `:73`) binds through `numberingBinding`
  (`:256-261`) to `ChecklistStore.setPrefixesReminderNumbers(_:for:)`
  (`ChecklistStore.swift:277-283`). The view is keyed by `checklistID` (`:3-4`)
  and re-reads the store in the binding getter so a synced value updates the
  toggle (`:253-255`).
- **Store mutation contract** is uniform: guard `.notFound` → no-op when
  unchanged → mutate → bump `revision`/`modifiedAt` → `scheduleSave()` →
  return `.updated`.
- **Watch transport & rendering.** `PhoneSyncAdapter.sendContext` pushes the
  whole envelope via `updateApplicationContext`; the watch ingests it into
  `WatchChecklistStore` (`ChecklistSync.swift:346-359`) as `checklists`/`folders`
  arrays. `WatchChecklistViewModel` derives `looseChecklists` (`:25-29`),
  `checklists(in:)` via `folderID == folder.id` (`:34-36`), `current(_:)`
  (`:49-52`) and `visibleItems(of:)` via `!item.isBlank` (`:61-63`). Views:
  `WatchChecklistListView.swift:13-27`, `WatchFolderDetailView.swift:13-24`,
  `WatchChecklistDetailView.swift:28-65`.
- **Folder membership is derived, never stored**: `Checklist.folderID: UUID?`
  (`Checklist.swift:186,197,212,239-242`); the folder owns no child pointer
  (research Q4).
- **Localization.** Three catalogs (`App`/`Core`/`Watch`), mapped in
  `scripts/l10n-check.sh:15-19` and `LocalizationFixtures.swift:8`; a new
  user-facing key needs all six languages plus a `requiredKeys` entry
  (`LocalizationFixtures.swift:12`).

## Desired End State

A user can disable a per-checklist "Show on watch" toggle on the iOS
edit-checklist screen. The flag persists through the versioned, iCloud-synced
envelope, and the watch honours it:

1. The toggle appears in `ChecklistDetailView`, labelled "Show on watch",
   defaulting to **on**, with store-backed persistence.
2. Decoding a v5-or-earlier envelope (no `showsOnWatch` key) yields `true`;
   `currentVersion` stays **5**.
3. On the watch, a check set to `false` does not appear in the main list's
   loose section nor in its folder's detail list. A folder row does not appear
   when it has at least one member and every member is hidden. A folder with
   zero members still appears.
4. Hidden checklists remain fully visible and editable on iOS (only the watch
   rendering changes).

**Verification**
- `make test-unit` — codec absent-key default-true + round trip; store
  mutation suite; view-model filtering incl. all-hidden folder and empty folder.
- `make watch-build` — watch layer compiles with the new derivations.
- `bash scripts/test.sh` — full gate (`gate: ok`), warnings-as-errors included.
- `scripts/l10n-check.sh` — new key present in all six languages.
- Static evidence is insufficient for the watch behaviour ticket (per
  `AGENTS.md`): verify the installed bundle with `devicectl`/`run-watch.sh`.

## Patterns to Follow

- **Additive boolean on `Checklist`** — model `showsOnWatch` exactly on
  `prefixesReminderNumbers` (`Checklist.swift:222,234,239-242,254-255,269`):
  stored `public var` with `= true` default, `CodingKeys` entry,
  `decodeIfPresent(Bool.self, forKey: .showsOnWatch) ?? true` with a comment
  naming the absent-in-v5-and-earlier case, unconditional encode. No
  `migrated(at:)` work — that fires only for `.migratable` v1/v2 payloads
  (`ChecklistStore.swift:80-91`).
- **Store mutation shape** — `setShowsOnWatch(_ enabled: Bool, for id: UUID) ->
  SetDestinationOutcome` mirroring `ChecklistStore.swift:277-283` one-for-one
  (guard `.notFound`, unchanged no-op, `revision += 1`, `modifiedAt = now()`,
  `scheduleSave()`), and rides the checklist's existing coarse clock.
- **Store-backed binding** — `showOnWatchBinding(checklistID:)` mirroring
  `ChecklistDetailView.swift:256-261`: getter reads `store.checklist(id:)`,
  setter calls the store method; doc-comment why the getter re-reads.
- **Toggle UI** — `Toggle` inside the existing Form/Section in
  `ChecklistDetailView.swift:70-75`, with a `Label` (`systemImage:`), a stable
  `.accessibilityIdentifier`, and a behavior footer.
- **Watch derivation in the view model** — extend `WatchChecklistViewModel`
  (`:16-63`) so `looseChecklists` and `checklists(in:)` exclude hidden
  checklists and a folder-visibility helper computes "≥1 member and all
  members hidden" over the same `folderID`-derived child set. Views keep
  rendering already-filtered collections; no filtering duplicated in
  `WatchChecklistListView` / `WatchFolderDetailView`.
- **Localization** — "Show on watch" in the **App** catalog
  (`CheckStitch/Localizable.xcstrings`) with `extractionState: "manual"` and
  all six languages, plus an alphabetically-placed
  `LocalizationFixtures.requiredKeys` App entry (`LocalizationFixtures.swift:12`).
- **Tests** — Swift Testing, behaviour-named, `@MainActor`; codec cases in
  `ChecklistCodecTests.swift` (`:167,178` precedent), store cases in
  `ChecklistStoreTests.swift` (`:1840-1882` precedent), a `#if os(macOS)`-gated
  toggle assertion in `ChecklistDetailViewTests.swift`, and view-model filtering
  tests.

Patterns the research found that should **NOT** be followed:
- **`@State`/`$` view-local bindings** (`InterfaceSettingsView.swift:53`,
  `BackgroundSettingsView.swift:11,36`) — correct for app settings, wrong here;
  the flag is store-persisted and synced.
- **A `ChecklistItem`-level boolean** — no stored-boolean precedent on
  `ChecklistItem` (`hasDescription`/`isBlank` are computed, `Checklist.swift:66-75`)
  and it cannot express folder-level hiding.
- **Bumping `currentVersion`** — an additive `decodeIfPresent ?? true` does not
  qualify (research Q1); bumping would strand older clients unnecessarily.

## Design Decisions

1. **Flag on `Checklist`, not `ChecklistItem`**: `Checklist.showsOnWatch` — the
   task is per-checklist, `prefixesReminderNumbers` is the exact precedent, and
   the watch already receives whole `Checklist` values, so the flag reaches all
   three watch views with no transport change (`ChecklistSync.swift:352`).
2. **Positive polarity, `Bool = true`**: `showsOnWatch` matches the "Show on
   watch" label and makes `decodeIfPresent ?? true` read as "absent → shown".
   This is the first default-`true` stored field; that is acceptable and
   explicit.
3. **Absent key decodes to `true`, no version bump**: older payloads and older
   clients keep working; follows the additive-field rule from research Q1.
4. **Row-level hiding, not empty-content hiding**: a hidden checklist disappears
   from the watch main list and folder detail; nothing navigable is left behind.
   iOS is unchanged.
5. **Empty folders stay visible**: only folders with ≥1 member and all members
   hidden are hidden. Avoids changing unrelated watch behaviour for empty
   folders.
6. **Filtering lives in `WatchChecklistViewModel`**: one derivation serving both
   watch views, unit-testable without UI.
7. **Toggle only in `ChecklistDetailView`, iOS list unchanged**: minimal UI
   surface; scope is "hide on watch", not "mark hidden on phone".
8. **Rides the existing checklist coarse clock**: `revision`/`modifiedAt`
   newest-editor-wins already covers a whole-checklist field; no merge-code
   change.

## What We're NOT Doing

- No `ChecklistItem`-level flag, no per-item watch hiding.
- No change to iOS list/detail rendering (hidden checklists are not greyed,
  badged, or filtered on the phone).
- No watch-side editing — the watch only renders the flag.
- No `currentVersion` bump and no new `migrated(at:)` case.
- No changes to text/dynamic-type support.
- No new merge resolution logic or per-field merge clock.
- No folder-side child list (membership stays derived from `folderID`).
- No child tickets — all work lands on the main ticket.

## Open Risks

- **First default-`true` stored field.** Every prior boolean defaults to
  `false`; the codec round-trip and absent-key tests must prove the `true`
  default explicitly, and the merge tests should confirm a `true`/`false`
  conflict resolves newest-editor-wins like `prefixesReminderNumbers` does.
- **Folder-visibility edge cases.** Unknown/deleted `folderID` values and
  tombstones must not make a folder vanish for the wrong reason; cover
  loose-checklists-with-unknown-folder and tombstoned folders in view-model
  tests.
- **Watch backwards compatibility.** An older watch build receiving a payload
  with the new key ignores it (unknown key, additive) — confirm decode does not
  throw on an unrecognised key.
- **Localization identity.** The German/Spanish/French/Japanese/Chinese values
  must differ from English or be listed in `excludedIdentities`
  (`LocalizationFixtures.swift:166-183`) to satisfy `l10n-check.sh`.
- **Static evidence is not enough.** Watch hide/show behaviour must be verified
  on the installed watch bundle, not via unit tests alone.