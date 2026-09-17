# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | 6905c2a | Instrument the sync gates on both targets |
| —     | 7180def | Phase 1 amendment: persist sync gate log to app container for device pull (user-approved Option B: `Documents/checklist-sync.log` file sink so gates are pullable via `devicectl device copy from --domain-type appDataContainer`) |
| —     | 969b104 | docs: record the one-tap hardware chain in spike.md |
| —     | d218a24 | docs: record Phase 1 decision-gate outcome in plan.md |
| 2     | c280b0a | Honest watch feedback — Sending… → Created / reason |
| 3     | efa48fe | Unknown/stale id recovers instead of silently dropping |
| 4     | dab56cb | Retain-and-resend across the activation race / non-running phone |
| 5     | d02db66 | Hardening — sad paths, log hygiene, on-device verdict |

## Automated Checks

- [x] Phase 1: `make test-unit` green (239 tests); `make build` green; `make watch-build` green
- [x] Phase 1 decision gate: one-tap hardware chain captured in `spike.md` — watch `[watchSend] accepted=true` ×[adapter+store], `[watchActivation] state=activated`; phone `[phoneReceive] → [phoneHandle] → [snapshotLookup] result=hit → [createOutcome] outcome=created(count: 11)`; 11 reminders confirmed in the iPhone Reminders app by the user. Chain clean end-to-end with the phone app running; reproduced defect = the phone-not-running / no-honest-feedback family (selects Phases 2+4 primary, Phase 3 safety net, per design decision 7)
- [x] Phase 2: `make test-unit` (RunResult round-trip + malformed-kind rejection; sending→created/failed store phases; everyOutcomeIsAnsweredOnTheWatchChannel); `make watch-build` (detail view compiles against RunPhase); `make build`
- [x] Phase 3: `make test-unit` (runRequestForUnknownIDAnswersNotFoundAndRePushes — no create, exactly one `.runResult(.notFound)`, `sentContexts.count == 2`; runRequestForKnownIDPushesNoExtraContext — `sentContexts.count == 1`; notFoundResultAsksForAFreshContext); `make watch-build`
- [x] Phase 4: `make test-unit` (runBeforeActivationIsRetainedThenResentExactlyOnceOnActivation, aResultClearsThePendingRun, aRejectedResendLeavesTheRunPending — watch store; duplicateRunIDCreatesOnceAndIsAckedAgain — one create, two acks); `make watch-build`
- [x] Phase 5: `make test-unit` (everyResultKindMapsToAUserVisiblePhase ×5 kinds; runResultWithANonDictionaryPayloadIsRejected); **`./scripts/test.sh` prints `gate: ok`** (simulator build, headless pre-boot, `make test` incl. UI smoke, `build-mac`, `watch-build`, 17/17 shell tests, shellcheck)
- [x] No silent paths remain on the run path: every decoded `.runChecklist` is answered by exactly one `.runResult` (coordinator `[phoneHandle]` duplicate-ack/duplicate-in-flight/acked/ack-dropped logs + phone adapter `handler=unset` failure ack)

## Manual Verification Items (from the plan)

Phase 1 gate items are DONE and user-confirmed (see `spike.md`). The following were NOT executed by me and are NOT checked off — they need the FINAL build installed on both devices first:
1. `bash scripts/run-watch.sh` (watch) and `bash scripts/run-devices.sh` (iPhone) — install the final Phases 2–5 build (commit d02db66), since all checks below require it

Phase 2:
- [ ] Tap **Create reminders** with the phone app running: the watch button reads `Sending…` then `Created`
- [ ] With the phone app force-quit, tap again: the button stays `Sending…` (never a false success — Phase 4 symptom)
- [ ] Phone log shows `[createOutcome] outcome=created(n)` and the watch receives one `.runResult` (pullable via the `Documents/checklist-sync.log` file sink on both devices)

Phase 3:
- [ ] On the phone, delete a checklist the watch is showing
- [ ] On the watch, open the now-stale checklist and tap **Create reminders**
- [ ] The watch shows `Not found — refreshing.` and the list self-corrects on the refreshed context

Phase 4:
- [ ] Force-quit CheckStitch on the iPhone, then tap **Create reminders** on the watch: the button shows `Sending…`
- [ ] Launch CheckStitch on the iPhone (foreground once, so the session activates)
- [ ] The phone creates exactly **one** set of reminders; the watch transitions to `Created`
- [ ] Re-tap the same checklist afterwards: the second run creates a second, distinct set

Phase 5 (closing verdict — sync tickets cannot close on static evidence):
- [ ] Tap **Create reminders** on a real checklist while the phone app is running → reminders appear in the iPhone's Reminders app; the watch button reads `Created`
- [ ] Force-quit the phone app, tap again, then launch the phone → exactly one set of reminders appears; the watch reaches `Created`
- [ ] Deny Reminders permission (Settings → CheckStitch → Reminders → off), tap → the watch shows a permission reason and the button is enabled again
- [ ] Capture the full log chain for the closing comment (`[watchSend] [phoneReceive] [phoneHandle] [snapshotLookup] [createOutcome]` on both devices — available from Console.app or the pullable file sink)
- [ ] State the user-visible end state in the completion artifact

## Notes / Deviations (all resolved within scope)

- **Phase 1**: the plan listed `WatchChecklistDetailView` changes only in Phase 2, but Phase 1's `run() -> UUID?` broke the existing `sent = store.run(checklist)` line; minimal compile patch `!= nil` applied, later replaced by the Phase 2 rewrite. The `idevicessyslog` command named in the plan does not exist on this host and `devicectl device sysdiagnose/diagnose` fail on both device types — this motivated the user-approved `checklist-sync.log` file sink amendment (`7180def`).
- **Phase 2**: the plan's inline `.runResult` `userInfo` encoder arm did not compile; extracted to a private helper (wire-identical). The plan said "English only" for the two new catalog keys but the repo's localization gate requires all six languages with non-English differing — added de/es/fr/ja/zh-Hans. Phase 2 store tests needed `store.start()` before `transport.deliver` (fake wiring); same pattern applied in Phases 3–4.
- **Phase 4**: `Set<UUID>` (Foundation) compiles on macOS + watchOS; `pendingRunID` fully removed (one doc-comment mention remains). Phase 4 `aResultClearsThePendingRun` needed `store.start()`.
- **Phase 5**: no deviations.
- Pre-existing (not fixed, out of scope): `ChecklistSyncCoordinator.swift` lacks a trailing newline. Plan residual risks (cross-launch duplicates from in-memory dedup; legacy queued messages without runID; English-only reason strings) stand as documented.