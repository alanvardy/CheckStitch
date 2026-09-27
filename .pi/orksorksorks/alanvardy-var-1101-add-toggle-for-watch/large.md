# Task

Add a per-checklist "Show on watch" toggle to the **edit checklist screen(s)** of
the CheckStitch iOS app. The toggle:

- is labelled "Show on watch"
- defaults to **enabled**
- when disabled, hides that checklist's item on the Apple Watch
- hides a **folder** on the watch when every checklist in it is hidden

The watch layer (`CheckStitchWatch/`) must honour the flag when rendering the
main list and the folder detail view, and hide any folder whose members are all
hidden.

## Why LARGE

SCHEMA + CROSS_CUTTING + CONVENTION_RISK: the per-item flag lives in the
versioned, iCloud-synced `ChecklistItem`/`ChecklistEnvelope` wire codec
(`ChecklistCodec.currentVersion = 5`) where absent-key decode-defaults and
version-bump policy are design decisions (see `Checklist.swift` decode/`migrated`
precedents), so persisting the default-on field to existing data is a data-model
change to shared sync/owned convention code; and the feature spans data model +
app UI (edit screens) + watch platform target (list + folder-hiding) with no one
existing pattern carrying it end to end.

## Surface (from classification recon)

- `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` — `ChecklistItem` /
  `Checklist` / `Folder` structs; versioned `ChecklistEnvelope` codec
  (`currentVersion = 5`), `decode` defaults, `migrated(at:)`.
- `CheckStitch/ChecklistDetailView.swift`, `CheckStitch/ItemEditView.swift` —
  the edit-checklist UI where the toggle lands (check existing edit form
  controls for precedent).
- `CheckStitchWatch/WatchChecklistListView.swift`,
  `CheckStitchWatch/WatchFolderDetailView.swift`,
  `CheckStitchWatch/WatchSyncAdapter.swift` — watch-side rendering that must
  filter hidden items and hide all-hidden folders.
- `Localizable.xcstrings` + `LocalizationFixtures.requiredKeys` — new
  user-facing string ("Show on watch") needs all 6 languages; run
  `scripts/l10n-check.sh`.