# Structure Outline

## Approach

Add one additive stored boolean, `Checklist.showsOnWatch` (default `true`,
`decodeIfPresent ?? true`, **no** `currentVersion` bump), mutate it through a
store method shaped exactly like `setPrefixesReminderNumbers`, bind it to a
store-backed "Show on watch" toggle in `ChecklistDetailView`, and honour it by
filtering already-derived collections in `WatchChecklistViewModel` so the
watch's existing views render less. No transport, merge-clock, or migration
work: the whole `Checklist` already travels in the envelope.

No horizontal phase is needed — the codec change is additive (no schema
migration, no version bump, no `migrated(at:)` case).

---

## Phase 1: Walking skeleton — toggle on iOS hides a loose checklist on the watch

Turning off "Show on watch" on the iOS edit-checklist screen persists the flag
through the synced envelope, and that checklist disappears from the watch main
list. Proves the full path: toggle → store → codec → envelope → watch store →
watch view model → watch list.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`CheckStitch/ChecklistStore.swift`, `CheckStitch/ChecklistDetailView.swift`,
`CheckStitch/Localizable.xcstrings`, `CheckStitchTests/LocalizationFixtures.swift`,
`CheckStitchWatch/WatchChecklistViewModel.swift`,
`CheckStitchWatch/WatchChecklistListView.swift`,
(+ tests `CheckStitchTests/ChecklistCodecTests.swift`,
`CheckStitchTests/ChecklistStoreTests.swift`,
`CheckStitchTests/ChecklistDetailViewTests.swift`,
new `CheckStitchTests/WatchChecklistViewModelTests.swift`)

**Key changes**:
- `Checklist.showsOnWatch: Bool = true` — new stored property + `CodingKeys`
  case; `decodeIfPresent(Bool.self, forKey: .showsOnWatch) ?? true` with the
  "absent in v5-and-earlier payloads decodes to shown" comment; unconditional
  encode. `currentVersion` stays `5`.
- `ChecklistStore.setShowsOnWatch(_ enabled: Bool, for id: UUID) -> SetDestinationOutcome`
  — guard `.notFound` → no-op when unchanged → mutate → `revision += 1` /
  `modifiedAt = now()` → `scheduleSave()` → `.updated`.
- `ChecklistDetailView.showOnWatchBinding(checklistID: UUID) -> Binding<Bool>`
  — getter re-reads `store.checklist(id:)?.showsOnWatch ?? true`, setter calls
  the store method; `Toggle` with `Label(..., systemImage:)` +
  `.accessibilityIdentifier("checklistShowsOnWatchToggle")` + behavior footer.
- `WatchChecklistViewModel.looseChecklists: [Checklist]` — now
  `ChecklistGrouping.isLoose` **and** `showsOnWatch`.
- App-catalog `"Show on watch"` key (six languages, `extractionState: "manual"`)
  + alphabetically-placed `LocalizationFixtures.requiredKeys` App entry.

**Contract**: `Checklist.showsOnWatch` (Bool, default-true, additive, v5 wire
shape) is the flag every later slice reads; `setShowsOnWatch(_:for:)` is the
only writer; `WatchChecklistViewModel` is the only watch-side filter owner —
views never filter.

**Tests**:
- `ChecklistCodecTests`: `payloadWithoutShowsOnWatchDecodesAsShown` (absent key →
  `true`), `showsOnWatchSurvivesEnvelopeRoundTrip` (both values) — happy + sad.
- `ChecklistStoreTests`: `setShowsOnWatchUpdatesRevisionAndPersists`,
  `setShowsOnWatchUnchangedIsNoOp`, `setShowsOnWatchUnknownIDIsNotFound`.
- `WatchChecklistViewModelTests` (new): `looseChecklistsExcludeHiddenChecklists`.
- `ChecklistDetailViewTests` (`#if os(macOS)` region): `showsOnWatchToggleDefaultsOn`,
  `togglingShowsOnWatchPersists`.
- Localization: `everyRequiredKeyIsPresent`, `catalogsHaveAllSixLanguages`,
  `nonEnglishValuesDifferFromEnglish`.

**Verify**: `make test-unit` (all of the above green) → `make watch-build`
(watch layer compiles) → `scripts/l10n-check.sh` prints ok.

---

## Phase 2: Folder semantics — folder detail and folder rows honour hiding

A folder's detail list shows only shown checklists, and a folder row disappears
from the watch main list when it has ≥1 member and every member is hidden. A
folder with zero members still appears. Independently valuable on top of
Phase 1's wire contract.

**Files**: `CheckStitchWatch/WatchChecklistViewModel.swift`,
`CheckStitchWatch/WatchChecklistListView.swift`,
`CheckStitchWatch/WatchFolderDetailView.swift`,
`CheckStitchTests/WatchChecklistViewModelTests.swift`

**Key changes**:
- `WatchChecklistViewModel.checklists(in folder: Folder) -> [Checklist]` — now
  also requires `showsOnWatch` (folder detail shrinks for free).
- `WatchChecklistViewModel.visibleFolders: [Folder]` — new derivation over the
  same `folderID == folder.id` child set: keep when members is empty **or** any
  member `showsOnWatch`; drop when members non-empty and all hidden.
- `WatchChecklistListView` renders `viewModel.visibleFolders` (no filter inline);
  `WatchFolderDetailView` keeps rendering `checklists(in:)` unchanged.

**Contract**: `visibleFolders` / filtered `checklists(in:)` are the folder
semantics; membership stays derived from `folderID` — no folder-side child list
is added.

**Tests** (`WatchChecklistViewModelTests`): `folderDetailExcludesHiddenChecklists`,
`folderWithSomeVisibleMembersStaysVisible`,
`folderWithEveryMemberHiddenIsHidden`, `emptyFolderStaysVisible`.

**Verify**: `make test-unit` (view-model suite + no regressions in
`ChecklistGroupingTests`) → `make watch-build`.

---

## Phase 3: Hardening — sync conflicts, edge cases, and on-watch verification

The default-`true` field survives a `true`/`false` concurrent edit, hidden
checklists whose folder is unknown/deleted stay hidden rather than reappearing
in the loose list, an older watch client ignores the new key without failing to
decode, and hide/show is verified on the installed watch bundle.

**Files**: `CheckStitchTests/ChecklistMergeTests.swift`,
`CheckStitchTests/ChecklistCodecTests.swift`,
`CheckStitchTests/WatchChecklistViewModelTests.swift`

**Key changes** (tests only — no new production surface expected; any fix this
slice forces stays inside the Phase 1/2 contracts):
- Merge: assert newest-editor-wins for a `showsOnWatch` conflict, mirroring the
  `prefixesReminderNumbers` merge cases.
- Codec: assert a payload carrying an unrecognised key still decodes (older
  client tolerance).
- View model: `hiddenChecklistWithUnknownFolderIsNotShownAsLoose`,
  `hiddenChecklistWithTombstonedFolderIsNotShown`.

**Contract**: none new — this slice only pins behaviours later changes must not
break.

**Tests**: the four cases above.
**Verify**: `make test-unit`; then full `bash scripts/test.sh` (`gate: ok`,
warnings-as-errors included); then **live**: `bash scripts/run-watch.sh`, toggle
"Show on watch" off on the phone and confirm the row is absent on the installed
watch bundle (and returns when re-enabled) — per `AGENTS.md`, static evidence
cannot close this ticket.

---

## Testing Checkpoints

- After Phase 1: `make test-unit` + `make watch-build` + `scripts/l10n-check.sh` green; absent-key default-`true` and round-trip pinned.
- After Phase 2: `make test-unit` + `make watch-build` green; all four folder-derivation cases pinned.
- After Phase 3: `bash scripts/test.sh` prints `gate: ok`, plus the on-device watch check.