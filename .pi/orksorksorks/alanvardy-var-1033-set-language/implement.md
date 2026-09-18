# Implementation Summary

All four phases of the VAR-1033 language-picker plan implemented and committed. The branch was rebased onto `origin/main` (`d8941a7`) before phase work; because that rebase brought in VAR-1042 (privacy-policy settings subscreen, watch-channel partial-reminder-creation), subagents adapted line numbers and two plan premises to the current code (see deviations below and the per-phase reports).

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | 0423a99 | Walking skeleton — pick a language in Settings and watch the UI flip, live |
| 2     | 4cb4a9a | The whole app follows the choice — no mixed-language UI |
| 3     | 8c87eea | The watch renders in the phone's language |
| 4     | c693ff2 | Hardening — close the leaks and make the flip observable |

## Automated Checks
- [x] Phase 1: `make test-unit` passes — 307 tests / 39 suites, incl. new `AppLanguageTests` and `AppLanguagePreferenceTests`; `LocalizationTests` green with `Interface`/`Language` required
- [x] Phase 2: `make test-unit` passes — 310 tests / 40 suites; `LocalizationTests` unchanged and green; new `LocalizedStringResolutionTests` green (incl. the key `de` App-catalog resolution through the `resolved(in:)` seam); `rg "String\(localized"` empty over the phase's six files
- [x] Phase 3: `make test-unit` passes — 318 tests / 41 suites, incl. new `AppLanguageSyncTests` (7 tests) and updated `ChecklistSyncCoordinatorTests`; `make watch-build` succeeds
- [x] Phase 4: `bash scripts/test.sh` prints `gate: ok` (build → sim → test → build-mac → watch-build → 17/17 shell tests → shellcheck); `rg -n "String\(localized"` over `CheckStitch CheckStitchWatch CheckStitchCore/Sources` finds only the seam implementation in `LocalizedString+Shared.swift` and two doc comments — no bare eager `String(localized:)` remains; `LocalizationTests` green with the four new Core keys + the new App key in `requiredKeys`; `ChecklistItemTests`, `ChecklistDetailViewTests`, `AppLanguageSyncTests` green

### Deviations from the plan (intent-preserving)
- **Phase 1 test pin deferred to Phase 2**: the plan's key-based title pin (`\.title.key`) requires the app `AppearanceMode.title` to return a resource (Phase 2 change); applied in commit 4cb4a9a.
- **Phase 3 premise stale**: main (VAR-1042) had already added `session(_:didReceiveUserInfo:)` + `ChecklistSyncMessage` decode to `WatchSyncAdapter` — no adapter change needed; the coordinator push + store receive complete the design.
- **Phase 4 watch button**: post-drift `WatchChecklistDetailView` has a three-state `buttonTitle` (`Sending…`/`Created`/`Create reminders`); all three converted to `LocalizedStringResource` rendered via `Text(...)` in a `label:` block (compiled by `make watch-build`). The plan's manual wording "`Gesendet` / `Erinnerungen erstellen`" is stale post-drift — the post-run state reads "Created".
- **Phase 4 coordinator test snippet** used the existing `createReminders: { await runner.run($0) }` pattern (the plan's `{ _ in }` cannot type-check); count `== 3` holds.

## Manual Verification Items (from the plan)
- [ ] `make run` on this worktree's simulator (`.simulator_id` = `D6D3CD6F-F7EF-4265-8E93-389ED04891EB`)
- [ ] Settings shows **Interface → Language** as the first section; options read System / English / Deutsch / Español / Français / 日本語 / 简体中文
- [ ] Select **Deutsch** and, *without relaunching*, "Settings", "Interface", "Language", "Appearance" and "Done" re-render in German
- [ ] Force-quit and relaunch: the app opens in German and the picker still shows Deutsch
- [ ] Select **System** and confirm the app returns to the device language
- [ ] This is the **only** evidence for the live flip (the hosted runner pins the process locale) — **the plan requires this to be seen; it is the design's whole risk and Phase 1's checkpoint**
- [ ] `make run`; switch to Deutsch and confirm **live, without relaunch**: appearance picker rows read System/Hell/Dunkel, the Background footer credit is German, due-date labels on a checklist detail row are German, and the About footer version line is unchanged in shape
- [ ] No English residue on the Settings sheet or a checklist screen after the switch
- [ ] Switch to 日本語 and confirm the same screens follow with no relaunch
- [ ] `bash scripts/run-watch.sh` with the watch paired; set **日本語** on the phone
- [ ] Raise/foreground the watch: its UI (list title "Checklists"/"チェックリスト", "Create reminders" button, empty-state text) is Japanese
- [ ] Force-quit the watch app (or the phone) and relaunch the watch: it still opens in Japanese
- [ ] Set the phone back to **System**; the watch returns to the device language on the next activation
- [ ] Known lag, accepted by design: a change made while the watch session is already active lands on the watch's next activation/`requestChecklists`, not instantly
- [ ] Simulator: select Deutsch and walk Settings → Appearance / Background / About, the checklist list, a detail row and the item editor (including the Priority menu); no English text remains on screen
- [ ] `xcrun simctl io` digests differ (see `verify-language.md`) and are recorded in that file
- [ ] Watch (rerun `bash scripts/run-watch.sh`): the detail screen's button reads German after the phone is set to Deutsch (post-drift wording: "Created" state translates; see Phase 4 report)
- [ ] Delete the `appLanguage` key (or reinstall) and confirm the app opens in the device language (`.system` default)

Evidence file for the screenshot diff: `.pi/orksorksorks/alanvardy-var-1033-set-language/verify-language.md` (recorded procedure; digests to be pasted by the user).

## Observations (pre-existing, untouched)
- `CheckStitch/ContentView.swift` imports `CheckStitchCore` twice (lines 1 and 3).
- `SettingsView` renders `Text("Import and Export")` against catalog key `"Import and export"` (case mismatch) — the plan flags this for a follow-up.
- `phase.detail` line under the watch button uses `RunResultKind.message` (plain English by design; core reason strings are deliberately not localized).