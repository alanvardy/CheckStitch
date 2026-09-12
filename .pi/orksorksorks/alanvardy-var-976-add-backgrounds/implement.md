# Implementation Summary

Ticket: `alanvardy-var-976-add-backgrounds` — add backgrounds to CheckStitch.
Branch: `alanvardy-var-976-add-backgrounds`. Rebased onto `origin/main` (`9e143dd`)
before phase work; all seven phase commits are pushed.

## Commits

| Phase | Commit    | Description |
|-------|-----------|-------------|
| 0     | `3539105` | Test target & gate |
| 1     | `f7c8389` | BackgroundFade |
| 2     | `ba60da0` | BackgroundImageStore |
| 3     | `ee221e4` | BackgroundPhotoLayer |
| 4     | `81581c6` | SettingsBindings |
| 5     | `5ac858e` | Settings surface (pushed Background subscreen) |
| 6     | `a591075` | ContentView mount — ZStack, fetch trigger, pin wiring |

## Automated Checks

- [x] `bash scripts/test.sh` green after **every** phase and at final HEAD `a591075` (`TEST SUCCEEDED`, `gate: ok`)
- [x] `make build` green (iOS simulator destination), including `#Preview` compilation
- [x] `make test FILTER=CheckStitchTests/HarnessTests` green (Stage 0)
- [x] `make test FILTER=CheckStitchTests/BackgroundFadeTests` green — 4 cases
- [x] `make test FILTER=CheckStitchTests/BackgroundImageStoreTests` green — 19 cases, no network (injected fakes only)
- [x] `make test FILTER=CheckStitchTests/BackgroundPhotoLayerTests` green — 3 cases
- [x] `make test FILTER=CheckStitchTests/SettingsBindingsTests` green — 4 cases
- [x] Final gate run at HEAD: 31/31 tests across 5 suites, 0 failures; shellcheck clean
- [x] Negative check (Stage 0): a deliberately failing `#expect(false)` made `bash scripts/test.sh` exit 2 (`TEST FAILED`); then reverted

## Manual Verification Items (from the plan)

- [ ] Stage 0: `make run` still builds, installs, and launches unchanged.
- [ ] Stage 3 / Stage 6: in the `make run` check, confirm the centered buttons do **not** stretch or shift when the background photo is enabled (the layout-non-expansion property the `Color.clear.overlay` wrapper exists for; visual, not asserted).
- [ ] Stage 5: `make run`: gear opens Settings; a **Background** row is present and pushes a subscreen titled "Background" with toggle, fade picker, pin toggle, refresh button, and (once an image has loaded) a credit footer.
- [ ] Stage 5: toggle / picker / pin / refresh all respond; refresh shows a spinner and is disabled while refreshing.
- [ ] Stage 5: `SettingsBindingsTests` still measures the snapshot/writeback contract added in Stage 4.
- [ ] Stage 5: macOS check (out of gate): open the project in Xcode, build and run the macOS destination, and confirm the pushed Background subscreen is top-aligned, not vertically centered.
- [ ] Stage 6: `make run` (cold launch): the wallpaper renders full-bleed behind the checklist card; windows/resize keep the buttons centered and unstretched.
- [ ] Stage 6: toggle Background off → photo hidden, base colour remains; on → photo returns without a refetch.
- [ ] Stage 6: fade picker at 0% shows the photo strongest, 90% barely; the change is immediate.
- [ ] Stage 6: pin on: relaunch after >24h (or delete/mutate the sidecar timestamp) does **not** refetch. Unpin with a stale image: image refreshes.
- [ ] Stage 6: refresh button: spinner appears, is disabled mid-flight, and on success a new photo/credit appears; a tap while pinned still refreshes.
- [ ] Stage 6: credit footer link opens the Unsplash photographer page.
- [ ] Stage 6: kill and relaunch: the last photo + credit persist (Application Support/CheckStitch) and are shown before/without a fresh fetch.

Stages 1, 2 and 4 had no manual items (pure math, fakes-only store, prefs bag).

**Residual, not gated** (from plan.md): the live `vardy.cc/unsplash` endpoint (ATS, reachability), the macOS settings-subscreen alignment, and the photo layer's layout-non-expansion property are manual-only this ticket; the gate runs the iOS simulator destination.

## Deviations from plan.md

1. **Stage 4/5 boundary (approved, "Option A")** — the plan put `makeSettingsBag()` / `writeBack(_:)` on `ContentView` in Stage 5, but Stage 4's `SettingsBindingsTests` calls them, so Stage 4 could not compile or pass its gate as written. The three background `@AppStorage` properties plus `makeSettingsBag()` and `writeBack(_:)` were pulled forward into Stage 4; Stage 5 added only `settingsSheetWritebacks(_:)` and the settings/subscreen wiring. The end state is identical to the plan.
2. **Stage 6 missing dependency (approved)** — the plan's Stage 6 snippet uses `Color.systemBackground`, which is a SingleThread extension (`Color+CrossPlatform.swift`) that the plan never listed for CheckStitch. Added `CheckStitch/Color+CrossPlatform.swift` as a verbatim port of the reference (18 lines; no `project.pbxproj` edit needed).
3. **Cosmetic** — newly created files end without a trailing newline (as in the plan's snippets). Left as-is to stay within phase scope.

## Operational note

Phase 0's subagent hit `ENOSPC` (volume at 100%) and died mid-verification. Its commit was independently re-verified by the parent (build, full gate, filter run, and the negative check) before the next phase started. ~17 GiB of regenerable caches (Mozilla sccache, central Xcode `DerivedData`, `XCTestDevices`, Homebrew downloads) were reclaimed to unblock builds; no project files or user device-support data were touched.
