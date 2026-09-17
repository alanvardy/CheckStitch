# Done

- **Branch / head SHA**: `alanvardy-var-1027-create-checklist-not-working-on-watch` @ `4469810`
- **Mechanical checks**: `./scripts/test.sh` prints `gate: ok` — simulator build, headless pre-boot, `make test` (256 unit tests in 33 suites + 1 UI smoke), `make build-mac`, `make watch-build`, 17/17 shell tests, `shellcheck`. Pre-existing, non-blocking warnings flagged: `appintentsmetadataprocessor` "no AppIntents.framework" (11×), and four redundant `try #require(store.run(...))` warnings in `WatchChecklistStoreTests.swift` (lines 59/142/158/183) caused by the branch's `run() -> UUID` signature change. No errors. No rebase conflicts; branch was rebased before the session and pushed with `--force-with-lease`.
- **Review outcome**:
  - **P0 blocker fixed** — `WatchSyncAdapter` had no `WCSessionDelegate.session(_:didReceiveUserInfo:)`, so the phone's `transferUserInfo` `runResult` was dropped on the real device and the watch could never leave `Sending…`. Added the handler (and a `watchReceive` gate), routing both receive paths through one helper. This was the exact silent-drop class the ticket targets, and it was invisible to the green gate because store tests inject messages directly through `FakeChecklistSyncTransport`.
  - **P1 fixed** — `WatchChecklistStore.run` now reuses the in-flight run for a checklist instead of queueing a second create, so re-tapping an offline checklist no longer guarantees duplicate reminder sets when the phone returns.
  - **P2 fixed** — `phases` is now insertion-ordered and capped at 32 (was unbounded); the diagnostics disk sink guards the Documents-directory lookup and logs append failures instead of silently returning.
  - **Optional improvements applied** — split `phoneSend`/`watchReceive` gate labels; `RunPhase.detail` surfaces the created reminder count (previously dead) alongside the failure reason; the detail screen prefers the store's fresh checklist copy so a `notFound` refresh self-corrects; the watch/phone skew window is documented in `plan.md`.
  - **Declined/deferred** — none of the reviewer's items were rejected; the residual risks from the plan (cross-launch dedup is in-memory, legacy no-runID queued messages, English-only Core reason strings) remain documented and out of scope.
- **Remaining manual items**: on-device verification, which per `AGENTS.md` cannot be replaced by static evidence (sync tickets cannot close on static evidence). With the P0 fix in place these are now meaningful and still unexecuted:
  1. `bash scripts/run-watch.sh` (watch) and `bash scripts/run-devices.sh` (iPhone) — install the final build (`4469810`).
  2. Phone running: tap **Create reminders** → watch reads `Sending…` then `Created`; reminders appear in the iPhone's Reminders app.
  3. Phone force-quit: tap → watch stays `Sending…`; launch the phone → exactly one set of reminders; watch reaches `Created`.
  4. Deny Reminders permission → watch shows a permission reason and the button re-enables.
  5. Stale checklist (deleted on the phone) → watch shows `Not found — refreshing.` and the list self-corrects.
  6. Capture the full log chain on both devices — now including the watch-side `[watchReceive]`: `[watchSend] [watchReceive] [phoneReceive] [phoneSend] [phoneHandle] [snapshotLookup] [createOutcome]` — from Console.app or the pullable `Documents/checklist-sync.log`.
