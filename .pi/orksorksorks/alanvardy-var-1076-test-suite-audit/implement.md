# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| —     | `6e0933c` | chore: remove DELETEME placeholder (housekeeping to unblock rebase) |
| 1     | `e13b2e1` | Phase 1: ChecklistSyncDiagnostics is testable and tested |
| 2     | `342f56b` | Phase 2: ContentView settings-action routing is a tested unit |
| 3     | `f603f16` | Phase 3: AppGroup + Color contract constants under test |
| 4     | `071a49d` | Phase 4: Export document content-type contract under test |
| 5     | `ff079bf` | Phase 5: sync + environment contract tests |
| 6     | `c7e2185` | Phase 6: hardening, findings artifact, full gate |

## Automated Checks
- [x] Phase 1: narrow `-only-testing:CheckStitchTests/ChecklistSyncDiagnosticsTests` passes (7 tests); `make test-unit` passes; `rg 'privacy: .public'` shows `log`'s two interpolations collapsed to one
- [x] Phase 2: `make test-unit` passes (ContentViewSettingsActionTests 5 cases); `make build` passes; `rg 'SettingsDataActionRoute'` shows exactly the definition, the one `perform` use, and the suite
- [x] Phase 3: `make test-unit` passes (AppGroupTests 3 + ColorCrossPlatformTests 1); `rg 'test.appGroup.probe'` shows both writes have `defer { removeObject }`; `make build-mac` passes
- [x] Phase 4: `make test-unit` passes (ChecklistExportDocumentTests); `rg 'ChecklistExportDocument' CheckStitchTests/` shows new suite + existing CheckListExportTests (no contradictions)
- [x] Phase 5: `make test-unit` passes (ChecklistSyncingContractTests 3 + AppEnvironmentTests 1); `make watch-build` passes
- [x] Phase 6: `make test-unit` (all suites, no shared-state leak); `bash scripts/tests/run.sh` passes (26 tests); `bash ./scripts/test.sh` prints **`gate: ok`**; `git status` shows findings.md plus only intended files

## Deviations / Notes (resolved during implementation)
- **Phase 3 compile fix (rolled into Phase 6 commit `c7e2185`):** `ColorCrossPlatformTests` imported `AppKit` unconditionally, which broke the `test-ui` leg because the whole `CheckStitchTests` bundle is also compiled against the iOS simulator SDK (`error: Unable to resolve module dependency: 'AppKit'`). The `import AppKit` was moved under `#if os(macOS)` and the single test case guarded likewise — it stays a macOS-only assertion (as the plan's recon already recorded finding #9), now compiles cleanly on the sim leg. `make test-unit` continues to exercise it.
- **Phase 3 API adaptation:** `AppGroup.suiteName`, `AppGroup.defaults`, and `Color.systemBackground` are `@MainActor internal static`; both Phase 3 suites were annotated `@MainActor` (matching the repo convention for suites touching statics; test target has no `SWIFT_DEFAULT_ACTOR_ISOLATION`).
- **Phase 2 API adaptation:** `ContentViewSettingsActionTests` needed `import CheckStitchCore` to reference `Checklist.id` in the `\.id` key paths.
- Phase 5 `defaultEnvironmentProvidesReminderCreator` intentionally **not** written (no default `reminderCreator`, no production construction site) — replaced by `environmentIsUsableWithInjectedSeams` + finding #5.

## Manual Verification Items (from the plan)
- [ ] Phase 1: `make build` succeeds; no compiler warning (gate is warnings-as-errors)
- [ ] Phase 1: On-device records unchanged — after a run, `devicectl`/Console still shows `[<gate>] k=v` lines
- [ ] Phase 2: `make run`, Settings → Export presents the multi-select; Settings → Import presents the file importer (behaviour-preserving refactor)
- [ ] Phase 2: Reordering with move arrows still moves first/last without change
- [ ] Phase 3: `make run`, app launches, list background renders as before; no crash from the App Group UserDefaults
- [ ] Phase 4: `make run`, export a checklist to Files → a `.json` document that re-imports (unchanged behaviour)
- [ ] Phase 6: open `findings.md` — every entry has severity + evidence, and no entry describes a fix that was silently applied
- [ ] Phase 6: `make test-unit` runtime is not materially longer than before (suites are pure; no I/O)