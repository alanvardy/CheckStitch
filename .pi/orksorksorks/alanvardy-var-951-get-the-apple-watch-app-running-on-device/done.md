# Done

- **Branch / head SHA**: `alanvardy-var-951-get-the-apple-watch-app-running-on-device` — review fixes at `6602731` (plus this artifact's chore commit).
- **Mechanical checks**: `./scripts/test.sh` → `gate: ok` on the final tree:
  - `make build` (iOS sim, watch embedded), `make test` (15 XCTest + 83 Swift Testing tests / 19 suites, one UI smoke), `make build-mac`, `make watch-build` (watchOS), `scripts/tests/run.sh` → **15 passed / 0 failed**, `shellcheck scripts/*.sh scripts/tests/*.sh` clean.
  - Warnings flagged (not failures): `WATCHOS_DEPLOYMENT_TARGET = 27.0` vs the installed watchOS SDK's max `26.5.99` (`project.pbxproj` watch configs, `CheckStitchCore/Package.swift`); repeated benign `linkd.autoShortcut` connection noise in the simulator test log.
- **Review outcome**:
  - **Fixed (applied under `[1]`, commit `6602731`)**:
    1. *Cold-start sync stall (blocker)* — `activate()` is asynchronous, so the coordinator's initial `pushContext()` and the watch's cold-launch `requestRefresh()` were dropped by the `activationState` guards; a cold-started pair stayed empty until a phone edit re-pushed. Added `onActivated` to `ChecklistSyncTransport`, re-push from the phone adapter and re-request from the watch adapter on activation.
    2. *"Sent" shown when nothing was sent* — `sendContext`/`sendUserInfo` now report acceptance; `WatchChecklistStore.run` returns whether the request was accepted and only then records `pendingRunID`; the detail view's label flips only on a real send. Watch re-activation after deactivation is covered by the same path.
    3. *`run-watch.sh` had no shell-test coverage* — added three cases to `scripts/tests/run.sh` (resolve→install→launch, unreachable device, unknown device); 15/15 pass.
    4. *Swallowed `updateApplicationContext` error* — now logged via `os.Logger`.
    5. *EventKit 1021 overlap* — coordinator serialises run requests through a task chain.
    - New unit tests: `activationSeedsTheWatchAfterTheColdStartDrop`, `activationRequestsRefreshAfterTheColdStartDrop`, `rejectedRunIsNotRecordedAsPending`.
  - **Deferred to the user (needs a decision before merge)**:
    - **Scope divergence from `task.md`.** The ticket asks the watch to "run a checklist (read items from a CheckStitch Reminders list and let the user check them off)"; the shipped design (`design.md` decision 6) is a read-only list plus one "Create reminders" action with no check-off/completion and no Reminders reads on the watch. `design.md` itself flagged this as the one open ambiguity. Confirm the read-only design (then no code change) or specify the check-off flow.
    - ~~**`WATCHOS_DEPLOYMENT_TARGET = 27.0`**~~ — **resolved**: the real-watch attempt proved it un-installable and the target is now `26.0` (see Addendum).
  - **Optional (declined, not applied)**: missing newline at EOF on several new files; `WatchChecklistStore.pendingRunID` is now only read by tests; `EventKitReminderCreator` (and its `requestFullAccessToReminders`) still compiles into the watch binary via the shared package (no reachable write path on the watch) — platform-filter the source or amend the design claim if desired.
- **Remaining manual items** (from `implement.md`, still open): the real-device deliverable itself is unverified —
  - `bash scripts/run-watch.sh` must install and launch `CheckStitchWatch` on `Alan's Apple Watch` (`00008301-209B793C010BC02E`). The resolver and deployment-target blockers are fixed (Addendum); the remaining blocker is that the watch was unreachable (`tunnelState: disconnected`, Bluetooth tunnel timed out) at hand-off.
  - Design check 3: a checklist created/edited on the iPhone appears in the watch list.
  - Design check 4: tapping a checklist shows its non-blank items and "Create reminders" produces one reminder per item on the phone.
  - Design check 5: the watch performs no other write and shows no Reminders permission prompt.
  - Persistence, phone-app-without-watch launch, and the watch-simulator empty state.

## Addendum — real-watch install attempt

This artifact previously admitted the on-device run was unverified. A real
attempt was then made; it found two concrete blockers, both now fixed:

1. **The built app could not install on the device.** The watch runs **watchOS
   26.6**, the installed SDK is **26.5**, but the bundle declared
   `MinimumOSVersion = 27.0`. `WATCHOS_DEPLOYMENT_TARGET` was lowered to `26.0`
   (4× in `project.pbxproj`) and `CheckStitchCore/Package.swift` `.watchOS` to
   `26.0`; the rebuilt bundle now declares `MinimumOSVersion = 26.0`.
2. **`run-watch.sh` could never resolve the watch.** The device name is
   `Alan’s Apple\u00a0Watch` (U+2019 apostrophe, U+00A0 space) while the script
   hardcoded the ASCII form, so the exact-name check always fell through. The
   resolver now NFKC-normalises, folds curly apostrophes and collapses
   whitespace on both sides; regression test
   `run_watch_matches_typographic_device_name` covers it. 16/16 shell tests and
   `./scripts/test.sh` → `gate: ok`.

**Still blocked (physical):** `devicectl device install app` cannot create a
tunnel (Bluetooth invalidated, `RemotePairingError` 1007/1034); the watch's
`connectionProperties.tunnelState` is `disconnected` and its last connection
was 2026-09-11. Installing needs the watch awake and unlocked on the same Wi-Fi
as this Mac, ideally on the charger, with Developer Mode and Remote Device
Services on. Once reachable, `bash scripts/run-watch.sh` resolves, builds and
installs.
