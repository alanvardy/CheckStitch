# Implementation Summary

VAR-977 — add a test suite to CheckStitch.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `b835e13` | Test Harness Scaffolding |
| 2     | `bb9198d` | Pure Models |
| 3     | `5db15ee` | EventKit Seam (protocol + real adapter + spy) |
| 4     | `d4bc091` | ChecklistCreator (business logic) |
| 5     | `c93bae3` | AppEnvironment + ChecklistViewModel |
| 6     | `af6b31e` | App Rewiring (presentational layer) |
| 7     | `673bb80` | UI Smoke Target + Gate |
| 8     | `5720fa4` | Documentation Contract |

## Automated Checks

- [x] `xcodebuild -list -project CheckStitch.xcodeproj` lists three targets and scheme `CheckStitch`
- [x] `bash -c 'cd CheckStitchCore && swift build'` succeeds (Phase 1)
- [x] macOS `-only-testing:CheckStitchTests` run green after every phase through Phases 2–6; final suite count 7 (`SmokeTests` + 6 unit suites)
- [x] `make build` green after Phase 1 and every subsequent phase
- [x] `rg` source checks: no inline `ChecklistItem`/`ChecklistWidth`; no `createChecklistReminders`; only `sharedTestEventStore` constructs `EKEventStore()` in tests; `spinnerDuration` only as `.zero` injection; `@AppStorage` only via `AppearanceModePreference.defaultsKey`
- [x] `grep -n SWIFT_DEFAULT_ACTOR_ISOLATION project.pbxproj` — exactly two hits (app target only), test targets opt in per-suite
- [x] `make test-unit` green (macOS host, `CODE_SIGNING_ALLOWED=NO`)
- [x] `make test-ui` green — the XCTest smoke ran on `sim-alanvardy-var-977-add-tests` (Clone 1 of 845FFF19-2594-4198-8058-5068ADA48FA9), accessibility audit passed
- [x] `bash scripts/test.sh` prints `gate: ok`
- [x] `shellcheck scripts/*.sh` clean
- [x] `git diff scripts/run-devices.sh` is empty (untouched)

## Deviations from plan text (all behavior-neutral; approved by supervisor where noted)

1. **Phase 2** — `ChecklistWidthTests.swift` additionally imports `CoreGraphics` (required for `CGFloat` literal conversions). Mirrors SingleThread's `CardWidthTests.swift`.
2. **Phase 2 (pull-forward)** — `import CheckStitchCore` added to `AppDelegate.swift` and `SettingsView.swift` immediately, because deleting `CheckStitch/AppearanceMode.swift` in Phase 2 (not Phase 6) breaks `make build` without it.
3. **Phase 4** — `ChecklistCreatorTests.swift` additionally imports `Foundation` for `TestError.boom.localizedDescription`.
4. **Phase 5 (approved)** — DI container renamed `Environment` → `AppEnvironment`: SwiftUI exports its own `Environment<Value>` type, making the bare name ambiguous in every app file importing both SwiftUI and the package. Applied in `Environment.swift`, `ChecklistViewModel.swift`, `ChecklistViewModelTests.swift`; Phase 6 plan snippets updated to match.
5. **Phase 6** — plan check `rg "EKEventStore\(\)" CheckStitch/` is formally unsatisfiable against the plan's own edits: the `#Preview` and MyApp's long-lived singleton store must construct `EKEventStore()`. Check reworded to `rg "createChecklistReminders" CheckStitch/`; `import EventKit` retained in `ContentView.swift` (preview) and added to `MyApp.swift` (singleton store).
6. **Phase 7 (approved-adjacent)** — the plan's "scoped `#if os(iOS)` is unnecessary" note is wrong: the macOS unit phase still compiles the `CheckStitchUITests` bundle, and macOS's `XCUIAccessibilityAuditType` has no `.trait` member. The audit call is guarded `#if os(iOS) … #else…`, mirroring `SingleThreadUITests.swift` exactly.
7. **Phase 8** — AGENTS.md's heading is "Conventions", not "Testing"; the new unit-suite contract bullets live at the top of that section.

## Notes for the reviewer

- `DELETEME` (tracked placeholder) still exists at the branch root: "git rm before merging". Intentional per ticket setup; left for the merge owner.
- `plan.md` automated boxes are all checked (26); the 10 unchecked boxes are Manual items, gathered below.
- pbxproj got no further hand-edits after Phase 1; FS sync groups picked up all new package/test files.
- `test-ui` boots the worktree simulator itself via `$(SIM)` from `.simulator_id` (`845FFF19-…`); no bare `name=` destination anywhere.

## Manual Verification Items (from the plan)

- [ ] Phase 1: package visible in `xcodebuild -showBuildSettings` (`grep -c CheckStitchCore`)
- [ ] Phase 1: open `CheckStitch.xcodeproj` in Xcode only if `xcodebuild -list` failed (it did not)
- [ ] Phase 2: `make run` launches the app; the checklist screen renders as before (no behaviour change)
- [ ] Phase 3: `grep -n SWIFT_DEFAULT_ACTOR_ISOLATION project.pbxproj` still exactly two hits
- [ ] Phase 6: `make run` on the worktree simulator — tap create: spinner ≥1 s, green checkmark flashes ~1 s; Reminders permission prompt on first tap; deny leaves button unchanged
- [ ] Phase 6: Settings — switch to Dark then back to System; window follows (macOS) / override clears (iOS)
- [ ] Phase 6: Edit checklist — add, rename, reorder, delete rows; blank row is skipped at creation
- [ ] Phase 7: `xcrun simctl list devices | grep -i 845FFF19` shows Recent/Booted activity (UI smoke ran on worktree sim)
- [ ] Phase 8: read edited AGENTS.md sections for accuracy vs `Makefile` / `scripts/test.sh`