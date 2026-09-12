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
    - **`WATCHOS_DEPLOYMENT_TARGET = 27.0`** — pre-existing project setting, plan forbade changing it; verify in the real-watch run rather than bumping blindly.
  - **Optional (declined, not applied)**: missing newline at EOF on several new files; `WatchChecklistStore.pendingRunID` is now only read by tests; `EventKitReminderCreator` (and its `requestFullAccessToReminders`) still compiles into the watch binary via the shared package (no reachable write path on the watch) — platform-filter the source or amend the design claim if desired.
- **Remaining manual items** (from `implement.md`, still open): the real-device deliverable itself is unverified —
  - `bash scripts/run-watch.sh` must install and launch `CheckStitchWatch` on `Alan's Apple Watch` (`00008301-209B793C010BC02E`), watching for `devicectl` 4016/offline and the 27.0 deployment-target question.
  - Design check 3: a checklist created/edited on the iPhone appears in the watch list.
  - Design check 4: tapping a checklist shows its non-blank items and "Create reminders" produces one reminder per item on the phone.
  - Design check 5: the watch performs no other write and shows no Reminders permission prompt.
  - Persistence, phone-app-without-watch launch, and the watch-simulator empty state.
