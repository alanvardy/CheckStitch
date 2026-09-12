# Done

- **Branch / head SHA**: `alanvardy-var-976-add-backgrounds` @ `32808a9`
  (rebased onto `origin/main` `224c875`, 0 behind). Pushed with
  `--force-with-lease` after the rebase; review-artifact commits follow.

## Rebase performed during review (user-authorised)

The review precondition found the branch 37 behind / 10 ahead of `origin/main`,
with merge conflicts in `CheckStitch.xcodeproj/project.pbxproj`,
`CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitch.xcscheme`,
`CheckStitch/ContentView.swift`, `Makefile`, `scripts/test.sh`. On the user's
explicit "Rebase", the 8 phase commits were replayed onto current `main`:

- Infra files (`pbxproj`, `xcscheme`, `Makefile`, `scripts/test.sh`): took
  main's versions — main already owns the `CheckStitchTests` +
  `CheckStitchUITests` targets and gate, so the branch's Phase 0 test-target
  setup was redundant. New background sources land in the existing
  `PBXFileSystemSynchronizedRootGroup` folders with no project edit.
- `SettingsView.swift`: main's appearance picker + macOS
  `preferredColorScheme` retained, plus the pushed Background row.
- `ContentView.swift`: main's navigation/list/detail/reminders content
  re-integrated with the background ZStack, `BackgroundPhotoLayer`, cold-launch
  `.task` (pin before refresh), pin `onChange`, and staged-bag settings sheet.
- Added one follow-up commit `9a04fba` adapting main's `ViewRenderTests` to the
  new `SettingsView` signature (the rebase surfaced this breakage).
- Backup of the pre-rebase branch: local branch `backup-976-pre-rebase`
  (`8f20540`).

## Mechanical checks — `bash scripts/test.sh` green

- `make build` (iOS Simulator) — **BUILD SUCCEEDED**
- `make test` unit suites on macOS — **53 swift-testing tests in 14 suites +
  14 XCTest cases, 0 failures**; includes BackgroundFade, BackgroundImageStore
  (19), BackgroundPhotoLayer, SettingsBindings, Harness, ViewRender.
- `make test-ui` — 1 UI smoke test passed.
- `make build-mac` — macOS slice built.
- `shellcheck scripts/*.sh` — clean.
- Pre-existing, non-blocking warnings only: `MACOSX_DEPLOYMENT_TARGET = 27.0`
  above the SDK's supported range (main's setting, unrelated to this diff).

## Review outcome

Single bounded fresh-context `reviewer` over the full 1557-line code diff
(`/tmp/review976.diff`), plus parent cross-check.

- **Blockers: none.** Concurrency (MainActor store, `isFetching` single-flight
  across awaits, post-await re-pin commit rejection), atomic disk-before-state
  pairing, and the two manually re-integrated views all held up.
- **Fixes worth doing now: none.** Both reviewer P2s were inspected and
  declined:
  1. *"`writeBack` rewrites all three keys on any change"* — intentional
     centralised writeback (the plan's Stage 5 design); it is the function
     `SettingsBindingsTests` exercises, so per-field wiring would orphan
     `writeBack` in production for a theoretical concurrent-writer benefit.
     Redundant writes are harmless in a single-window app.
  2. *"Cold launch fetches even when the background is disabled"* — the plan's
     Stage 6 manual contract explicitly requires "toggle Background off → on →
     photo returns without a refetch", and nothing triggers a fetch on
     re-enable. Gating `.task` on `backgroundEnabled` would break that.
- **Optional improvements applied (user-approved, commit `32808a9`):** added
  trailing newlines to `BackgroundPhotoLayer.swift`,
  `BackgroundSettingsView.swift`, `SettingsBindings.swift`,
  `SettingsSubscreenLayout.swift`; `FakeBackgroundFetcher` now throws a
  descriptive `unstubbedURL` error instead of force-unwrapping; documented the
  deliberate synchronous main-actor file I/O in
  `BackgroundImageStore.loadStoredImage`/`persist`. `bash scripts/test.sh`
  re-run green after these edits (53 swift-testing + 14 XCTest + 1 UI, 0
  failures). The settings sheet's live-writeback (no cancel/discard) was left
  as the ticket's designed behaviour.

## Remaining manual items (from `plan.md` / `implement.md`)

- `make run` (cold launch): wallpaper renders full-bleed; resize keeps the
  checklist card centered and unstretched (`Color.clear.overlay`
  non-expansion is visual-only, not asserted).
- Settings — Background subscreen: toggle, fade picker, pin toggle, refresh
  spinner/disabled-mid-flight, and credit footer link all respond.
- Pin on → relaunch after >24h does not refetch; unpin with a stale image does.
- Kill/relaunch: last photo + credit persist in Application
  Support/CheckStitch and show without a fresh fetch.
- macOS (out of gate): pushed Background subscreen is top-aligned, not
  vertically centered.
- Live `vardy.cc/unsplash` endpoint (ATS, reachability) remains ungated.
