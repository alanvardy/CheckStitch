# Done

- **Branch / head SHA**: `alanvardy-var-923-refactor-codebase-using-mvvm-principles` @ `25faed9` (pushed to origin; rebased on `origin/main` `60f3518`, no conflicts)
- **Mechanical checks**: `bash scripts/test.sh` → `gate: ok` (`make build` iOS sim → `make test` unit + UI smoke → `make build-mac` → `make watch-build` → 24/24 shell tests → shellcheck). `make test-unit`: 361 tests / 48 suites pass. All compiling legs run `WARNINGS_AS_ERRORS`. No Swift linter configured (shellcheck only, per repo convention). Warnings flagged: none.
- **Review outcome** (2 fresh-context reviewers + own scan; no blockers):
  - **Fixes applied** (commit `25faed9`):
    - `#Preview` in `CheckStitch/ContentView.swift` was missing the now-required `SettingsViewModel` environment → added.
    - Extracted `ContentView.settingsSnapshot()` and restored the `@AppStorage` → `SettingsSnapshot` read-path test (`SettingsBindingsTests.snapshotReadsCurrentUserDefaults`), recovering the coverage dropped when `makeSettingsBag()` was removed.
    - Refreshed stale comments in `CheckStitchCore/.../ChecklistCreator.swift` and `ReminderCreating.swift` that referenced the deleted `ChecklistViewModel` / unused `AppEnvironment` injection.
    - Normalised missing trailing newlines across 17 changed Swift files.
  - **Reviewer finding rejected**: "remove dead `.environment(store)` from `MyApp`/preview" — incorrect; `ChecklistDetailView`, `ItemEditView` and `ExportChecklistsView` still declare `@Environment(ChecklistStore.self)` and inherit it from those injections, so removal would break them. Retained.
  - **Deferred / ignored** (with reason): deleting the orphaned Core `AppEnvironment` (plan Phase 8 deliberately retains it as public seam API, out of scope); the duplicate-tap guard now sitting inside the spawned `Task` (benign — MainActor serialises the tasks and `.disabled(runVM.creating.contains(id))` gates the first tap); `creating.remove` skipped on a thrown `ChecklistReminders.create` (the API is non-throwing); merging the structurally identical `SettingsSnapshot`/`SettingsWriteback` (intentional read/write direction split); no dedicated `WatchChecklistViewModel` suite (pure passthrough).
  - **Optional improvements applied**: yes (per operator's `[2]`), i.e. the trailing-newline normalisation, the read-path test and the stale-comment refresh above.
- **Remaining manual items**: the `make run` / `make build-mac-signed` / `run-watch.sh` / real-device verification items recorded in `implement.md` (per-phase behaviour spot-checks) and `plan.md` are unchanged and still unverified — this is a pure refactor and static evidence cannot close sync/icon/render tickets.
