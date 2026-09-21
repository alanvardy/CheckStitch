# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | b5ae667 | walking skeleton — durable counter + threshold refusal, all entry points |
| 2     | f16a0d7 | real purchase — Buy unlocks without relaunch |
| 3     | ff69081 | restore + entitlement lifecycle |
| 4     | af3e1a8 | hardening and polish |

## Automated Checks
- [x] Phase 1: `make build` (iOS simulator, warnings-as-errors)
- [x] Phase 1: `make build-mac` (macOS slice)
- [x] Phase 1: `make watch-build` (watchOS)
- [x] Phase 1: `make test-unit` (RunCounterTests, gate/VM/intent/coordinator/watch suites, localization canaries)
- [x] Phase 1: grep — no un-updated exhaustive `switch` over `ReminderRunOutcome`
- [x] Phase 2: `make test-unit` (PurchaseServiceTests green; existing suites unchanged)
- [x] Phase 2: `make build` (StoreKit links on iOS)
- [x] Phase 2: `make build-mac` (StoreKit 2 API on macOS slice)
- [x] Phase 2: `make watch-build` (Core unchanged for watchOS)
- [x] Phase 3: `make test-unit` (restore/fail-open/unknown semantics green)
- [x] Phase 3: `make build` and `make build-mac`
- [x] Phase 3: `make watch-build`
- [x] Phase 4: `make test-unit` (Phase 4 sad-path tests green — 410 tests / 52 suites)
- [x] Phase 4: grep — every entry point (Intent, Reminders, RunResultKind, VM) handles `purchaseRequired`
- [x] Phase 4: `./scripts/test.sh` prints `gate: ok` (build → test → build-mac → watch-build → shell tests → shellcheck)

## Manual Verification Items (from the plan)
- [ ] Phase 1 — `make run` on this worktree's simulator; run a checklist 20×. The 21st tap shows the paywall and the Reminders app receives no new reminders. (Shortcut while iterating: temporarily set `RunGate.freeRunLimit = 1` in `RunCounter.swift`, verify, then revert — do not commit the change.)
- [ ] Phase 1 — Browse/edit/duplicate/export/import a checklist while at the limit — all still work.
- [ ] Phase 2 — Set the scheme's StoreKit configuration, `make run`, drive the counter to the limit (20 runs or a temporary `freeRunLimit = 1`), tap **Buy**, confirm the local StoreKit purchase sheet, and verify the paywall dismisses **without relaunching** and the next run creates reminders.
- [ ] Phase 2 — Confirm the price shown matches the `.storekit` configuration.
- [ ] Phase 2 — Cancel the purchase sheet; verify the paywall stays and `lastError` copy is shown only for a thrown error (cancellation shows nothing).
- [ ] Phase 3 — On the simulator: buy, then delete the app, reinstall (`make run`), and confirm a run at the limit shows the paywall; tap **Restore Purchases** and confirm it unlocks.
- [ ] Phase 3 — Airplane-mode cold launch after a prior purchase: the app stays unlocked (no paywall) and runs still succeed.
- [ ] Phase 3 — First-ever launch with no purchase and StoreKit unreachable: at the limit, the paywall shows with the retry affordance (no silent unlock).
- [ ] Phase 4 — Voice/shortcut (`RunChecklistIntent`) at the limit speaks the limit dialogue; no reminders are created.
- [ ] Phase 4 — A remote run from the paired watch at the limit shows the refusal on the watch (the `.runResult(purchaseRequired)` ack), and the phone does not create reminders.
- [ ] Phase 4 — While locked at the limit: browse, edit, duplicate, delete, export, import and sync checklists all still work.
- [ ] Phase 4 — Paywall: with the store unreachable, the retry row shows; **Try Again** reloads; the buy button shows the price once loaded.
- [ ] Phase 4 — Accessibility: VoiceOver reads the paywall title, price, buy, restore and dismiss controls.

## Notes
- Phase 4's worker subagent timed out during `make test-unit` before committing; the parent (this run) reviewed the uncommitted diff, confirmed it was complete and Phase-4-scoped, ran the verification (`make test-unit`, the grep), and committed it (`af3e1a8`).
- The Run-action StoreKit scheme selection in `CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitch.xcscheme` is a GUI-generated wiring that could not be authored confidently by hand (the project uses `PBXFileSystemSynchronizedRootGroup`); it is a manual follow-up. `CheckStitch/CheckStitch.storekit` was authored by hand and committed. Open the scheme in Xcode → Run → Options → StoreKit Configuration and select `CheckStitch.storekit` before the Phase 2 manual test.
- Small test adaptations were made by the implementers and reconciled in later phases (details live in the per-phase reports): `PurchaseService` starts `.unknown` so "locked" assertions use `!isUnlocked`; `RunChecklistIntent` extracts a `resolveGate()` helper because `await` cannot appear to the right of `??`; Phase 2/3 purchase tests use isolated default caches so they don't depend on the machine's real `.standard` user defaults.