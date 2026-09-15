# Task

Add an edit screen for each checklist item (Linear VAR-1007). Each item row
in the checklist detail screen gets an "edit" icon; tapping it brings up
another screen where the item's **description** and **days until due** can be
edited. The "days until due" field shows helper text under it explaining that
leaving it empty means no due date, and `0` means today.

The data model already supports this — no schema or migration work. An item is
`ChecklistItem` with `title`, `description: String`, and
`relativeDate: Int?` (days from today: `0` = today, `1` = tomorrow, negative
= past, `nil` = no date; no time-of-day support). The codec is at v4 and
round-trips both fields. The store already has per-field mutators that stamp
item `revision`/`modifiedAt` and debounce-save: `updateItem(...title:)`,
`updateItemDescription(...description:)`, and `updateItem(...relativeDate:)`
(no-op when unchanged). All that is missing is the UI: the edit-icon
affordance per row, the new edit screen, and the localization of its strings.

## Why MEDIUM

Breadth trigger 7 (MULTI_MODULE) — the change spans a new view, the
detail-view row affordance, localization, and several test files (≈7–8
files), while M1 (approach known: existing pushed-subscreen pattern + existing
store mutators) and M2 (no schema, no new subsystem/integration, no shared
convention risk) hold. One plan pass, then implement → review.

## Key files

- `CheckStitch/ChecklistDetailView.swift` — the item list; `ItemRow` at
  `:270-358` (title/description/date inline fields, `#if os(iOS`/`macOS)` split
  on the date field, buffered `draftDate` commits via `commitRelativeDate`;
  iOS-only `ToolbarItem { EditButton() }` at `:112-114` is the checklist
  reorder *edit mode*, not a per-item editor). Add the per-row edit icon and
  route to the new screen (pushed-subscreen precedent:
  `CheckStitch/SettingsView.swift:32-51` `NavigationLink` subscreens +
  `.settingsSubscreenLayout()` from `CheckStitch/SettingsSubscreenLayout.swift`;
  `BackgroundSettingsView.swift:17-22` shows the `caption()` helper-text
  pattern). `ContentView.swift:14,28-41` holds the root `NavigationStack`.
- **New** `CheckStitch/ItemEditView.swift` — the edit screen (description
  field + days-until-due field with the caption underneath). New app-target
  files need no `project.pbxproj` edit
  (`PBXFileSystemSynchronizedRootGroup`). Must build on macOS
  (`make build-mac`) and iOS sim.
- `CheckStitch/ChecklistStore.swift` — existing mutators at `:225-236`
  (title), `:238-250` (description), `:252-261` (relativeDate); a combined
  single-stamp mutator is optional, not required.
- `CheckStitch/Localizable.xcstrings` + `CheckStitch/...lproj` (`en/es/fr/ja/zh-Hans`)
  — new user-visible strings follow the existing localization pattern.
- Tests — `CheckStitchTests/ChecklistDetailViewTests.swift` (existing ItemRow
  render/buffer suites), `CheckStitchTests/ViewRenderTests.swift` (render
  canary), `CheckStitchTests/ChecklistStoreTests.swift` (only if a combined
  mutator lands); optional one-line XCTest smoke addition in
  `CheckStitchUITests/CheckStitchUITests.swift`.

Sync/merge of edited fields needs no work: edits flow through
`ChecklistSyncService` → iCloud KVS → `ChecklistSyncCoordinator` → watch
(`CheckStitchWatch/` reads `ChecklistItem` directly, dates not shown there).