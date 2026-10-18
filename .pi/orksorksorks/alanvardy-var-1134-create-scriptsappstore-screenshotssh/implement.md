# Implementation Summary

VAR-1134: Port SingleThread's `scripts/appstore-screenshots.sh` to CheckStitch —
per-language App Store captures of the main list, empty state, settings/options
screens, the standalone watch app, and per-run manifests, written to
`build/appstore-screenshots/<lang>/<device>/<n>-<name>.png`, plus the launch-argument
UI-testing seams (`LaunchSeams` in `CheckStitchCore`) those captures need on both
the iOS and watch targets.

All seven phases landed; each is its own commit on
`alanvardy-var-1134-create-scriptsappstore-screenshotssh`. The branch is pushed and
the PR (#100) is open as a draft.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| (pre) | `f0e27f1` | chore: remove DELETEME placeholder (housekeeping for a clean status; not a planned phase) |
| 1     | `2dd612a` | Phase 1: Walking skeleton — one hermetic empty-state capture |
| 2     | `83c439a` | Phase 2: Deterministic wallpapers staged into the app container |
| 3     | `303a1da` | Phase 3: Seeded main list (dark + light) |
| 4     | `57224c7` | Phase 4: Settings and detail screens |
| 5     | `cdb352d` | Phase 5: Multi-language loop |
| 6     | `9c39e17` | Phase 6: iPad, standalone watch, and per-run manifest |
| 7     | `502eb02` | Phase 7: Hardening, CLI surface, docs |

Diff vs `origin/main`: 28 files changed, 1095 insertions(+), 34 deletions(-)
(new `scripts/appstore-screenshots.sh`, `LaunchSeams.swift`, wallpaper fixtures,
watch wiring, `Makefile`, `AGENTS.md`, unit/UI tests, and the `run.sh` harness cases).

## Automated Checks

- [x] Phase 1: `make test-unit` passes (new `LaunchSeamsTests` green; existing suites unaffected)
- [x] Phase 1: `bash scripts/tests/run.sh` passes (new `appstore_*` cases green)
- [x] Phase 1: `make build` succeeds with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`
- [x] Phase 1: `bash -n scripts/appstore-screenshots.sh` and `shellcheck` are clean
- [x] Phase 2: `bash scripts/tests/run.sh` passes with the wallpaper-staging case
- [x] Phase 2: `shellcheck` + `bash -n` clean
- [x] Phase 3: `make test-unit` passes (`ChecklistStoreTests.seedPopulatesTheStoreAndPermitsOverwrite`)
- [x] Phase 3: `make test-ui` passes (new seeded case finds a `checklistRow-*`)
- [x] Phase 3: `bash scripts/tests/run.sh` passes with the two-shot order case
- [x] Phase 4: `make test-unit` passes
- [x] Phase 4: `make test-ui` passes (four UI cases: smoke, seeded list, settings, detail)
- [x] Phase 4: `bash scripts/tests/run.sh` passes with the five-shot `SCREENS` sequence case
- [x] Phase 5: `make test-unit` passes (six-id + unknown-language cases)
- [x] Phase 5: `bash scripts/tests/run.sh` passes with the six-language-directories case
- [x] Phase 6: `make test-unit` passes (`WatchChecklistStoreTests` seed case green)
- [x] Phase 6: `make watch-build` succeeds
- [x] Phase 6: `bash scripts/tests/run.sh` passes with the watch + manifest cases
- [x] Phase 7: `bash scripts/tests/run.sh` passes (all `appstore_*` cases, option-parse, `-h`, unknown flag, pre/post-flight)
- [x] Phase 7: `shellcheck scripts/*.sh scripts/tests/*.sh` and `bash -n` are clean
- [x] Phase 7: `bash scripts/test.sh` prints `gate: ok` (run once during the final phase)
- [x] Phase 7: The capture run is absent from `scripts/test.sh` (grep returns nothing)

Full-suite tallies reported per phase: `run.sh` 28 → 29 → 30 → 31 → 32 → 34 → 37 passed,
0 failed; `make test-unit` 687 → 688 tests, 71 suites; `make test-ui` 2 → 4 cases.

## Deviations (approved during implementation)

- **Phase 4 settings UI test** — the plan's literal `appearancePicker` assertion cannot hold:
  `SettingsView` is a `NavigationStack` whose "Interface" row pushes `InterfaceSettingsView`
  (which owns `appearancePicker`), so the picker is never visible on sheet-open. Approved
  deviation: `testUITestingOpenSettingsShowsSettingsSheet` asserts `settingsInterfaceRow`
  exists on open, proving the settings sheet presented.
- **Phase 7 pre-flight vs post-flight size check** — adding `preflight_size` would have made
  the existing Phase 1 post-flight mismatch case (`appstore_size_mismatch_exits_one_and_names_file`)
  unreachable. Approved deviation: the harness `sips` stub is path-aware — it reports the
  expected `1206x2622` for the `appstore-preflight*` temp screenshot while captured
  `build/appstore-screenshots/*.png` output reports the mismatch pair, so both pre-flight and
  post-flight coverage stay green.

## Manual Verification Items (from the plan — not checked; the user confirms these)

### Phase 1 — walking skeleton
- [ ] `make build && bash scripts/appstore-screenshots.sh iphone-6.3 --no-build` writes
      `build/appstore-screenshots/en/iphone-6.3/1-main-dark.png` and prints no size error
- [ ] `sips -g pixelWidth -g pixelHeight build/appstore-screenshots/en/iphone-6.3/1-main-dark.png`
      reports `1206` × `2622`
- [ ] The shot shows the empty state (no list rows), proving `--ui-testing` + ephemeral defaults took effect
- [ ] `xcrun simctl get_app_container <udid> app.alanvardy.CheckStitch data` is unchanged after the run
      (real App Group container untouched)

### Phase 2 — wallpapers
- [ ] `bash scripts/appstore-screenshots.sh iphone-6.3 --no-build` then the staged wallpaper check
- [ ] Reopening the captured PNG shows the staged photo behind the card, not the plain background colour

### Phase 3 — seeded main list
- [ ] `bash scripts/appstore-screenshots.sh iphone-6.3 --no-build` writes `1-main-dark.png` (three seeded rows)
      and `2-empty.png` (empty state)
- [ ] The dark shot is dark and the light shot is light (`simctl ui … appearance` took effect)

### Phase 4 — settings + detail
- [ ] `bash scripts/appstore-screenshots.sh iphone-6.3 --no-build` writes all five `en/iphone-6.3/*.png`
- [ ] `3-settings.png` shows the settings sheet; `5-detail.png` shows the first seeded checklist's items

### Phase 5 — multi-language
- [ ] A full `bash scripts/appstore-screenshots.sh iphone-6.3 --no-build` run creates
      `en de es fr ja zh-Hans` folders, each with the five PNGs
- [ ] Opening the `ja` and `zh-Hans` main shots shows Japanese / Simplified Chinese chrome (buttons, nav title)

### Phase 6 — iPad, watch, manifest
- [ ] `bash scripts/appstore-screenshots.sh` (all classes, `--no-build` after one build) writes
      `iphone-6.3`, `ipad-13` and `watch-46mm` folders for all six languages
- [ ] Both watch PNGs are `416×496`; `1-list.png` shows the seeded rows and `2-detail.png` shows the
      first checklist's items
- [ ] Each `manifest.json` lists the captured screens in order

### Phase 7 — hardening / determinism
- [ ] Two consecutive `bash scripts/appstore-screenshots.sh --no-build` runs produce byte-identical PNGs
      (`shasum build/appstore-screenshots/**/*.png` before/after)
- [ ] A clean clone with networking disabled still produces the full tree (wallpapers are committed, not fetched)
- [ ] `make appstore-screenshots ARGS='iphone-6.3 --no-build'` runs the script
- [ ] A deliberate `--udid iphone-6.3=<wrong-udid>` on a wrong-class simulator fails at pre-flight naming the
      simulator, before any capture

## Notes

- `scripts/fixtures/appstore-wallpapers/` ships 10 committed JPEGs + `manifest.json`, so the capture run
  needs no network.
- `LaunchSeams` in `CheckStitchCore` is the single arg/env reader shared by the app and the watch target.
- The capture run is deliberately **not** part of `scripts/test.sh`; the script's gate is `shellcheck` +
  `bash -n` + the `scripts/tests/run.sh` stub harness.
