# Implementation Summary

Companion `CheckStitchWatch` target (embedded in `CheckStitch.app`) added: the
phone owns EventKit and the checklist store and pushes via
`updateApplicationContext`; the watch lists checklists, shows items read-only,
and offers one "Create reminders" action that runs the existing phone-side
reminder write. All sync logic landed in `CheckStitchCore` as host-tested
types; the watch/phone `WCSession` adapters and pbxproj stay thin and are
verified by compile + gate.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `5e6658d` | Shared model in CheckStitchCore |
| 2     | `3d66ae8` | Sync contract + watch state machine |
| 3     | `68ef82b` | Watch target + build scaffolding |
| 4     | `e289e8b` | Watch UI — list → detail → run |
| 5     | `4366da0` | Phone-side coordinator + WCSession adapter |
| 6     | `a811adb` | Tooling, gate and real-watch run |

(Plus chore `9013e8b` committing the design.md/structure.md step artifacts, so
the whole `.pi/orksorksorks/<branch>/` dir is tracked per repo convention.)

## Automated Checks

- [x] Phase 1: `make test-unit` (25 tests/9 suites), `make build`, `make build-mac`, watchOS `swiftc -typecheck` of the whole package (D2 guard proof)
- [x] Phase 2: `make test-unit` (35 tests/11 suites incl. the new sync suites), `make build-mac`
- [x] Phase 3: `make watch-build`, `make build` (watch embedded), `make build-mac` (watch excluded via `platformFilter = ios`), `make test-unit`, `plutil -lint` → OK
- [x] Phase 4: `make watch-build`, `make build`
- [x] Phase 5: `make test-unit` (40 tests/12 suites), `make build`, `make build-mac`, exactly **one** `EKEventStore()` outside tests (`CheckStitch/ChecklistReminders.swift:12`)
- [x] Phase 6: `bash scripts/test.sh` → `gate: ok` (build → test → build-mac → watch-build → shellcheck), `shellcheck scripts/run-watch.sh` clean, `bash -n scripts/run-watch.sh` clean

## Manual Verification Items (from the plan)

- [ ] Run the app on the simulator, create a checklist with items, kill and relaunch: items and names persist (wire format unchanged)
- [ ] `xcrun simctl list devices available | grep "Apple Watch Series 11"`, boot one, `xcrun simctl install <UDID> DerivedData/Build/Products/Debug-watchsimulator/CheckStitchWatch.app`, `xcrun simctl launch <UDID> app.alanvardy.CheckStitch.watchkitapp`, confirm it launches showing "CheckStitch"
- [ ] On the watch simulator: launch shows the empty state ("Open CheckStitch on your iPhone."); with the phone not running there is no data, which is the expected cold state
- [ ] In Xcode Previews (or with a temporary fixture), a checklist shows its non-blank items and the "Create reminders" button; tapping it flips the label to "Sent"
- [ ] Phone app on the simulator starts without a crash with no watch paired (`WCSession.isSupported()`/activation no-ops)
- [ ] `bash scripts/run-watch.sh` installs and launches `CheckStitchWatch` on `Alan's Apple Watch` (`00008301-209B793C010BC02E`)
- [ ] Design check 3: create/edit a checklist on the iPhone (`make run`), leave both apps active; the checklist appears in the watch list
- [ ] Design check 4: tap the checklist on the watch, confirm its non-blank items render, tap **Create reminders**; one new reminder per non-blank item appears in Inbox on the phone
- [ ] Design check 5: the watch performs no other write, edits nothing, and shows no Reminders permission prompt

## Observations / adaptations made during implementation

- **Phase 4**: `WCSessionDelegate.activationDidCompleteWith` witness required the protocol's exact signature (`error: (any Error)?`, `_ session:` label) — the `_` label prefixes the private `session` field and resolves the main-actor-isolated error; message decoding happens before the `Task { @MainActor }` hop. Applied the same pattern in Phase 5's `PhoneSyncAdapter`.
- **Phase 6**: the plan's verbatim `WATCH_NAME="${WATCH_NAME:-Alan's Apple Watch}"` is a genuine bash parse error (literal `'` inside the default word). Fixed with `DEFAULT_WATCH_NAME="Alan's Apple Watch"` → `WATCH_NAME="${WATCH_NAME:-$DEFAULT_WATCH_NAME}"` — same behavior, clean `bash -n` + shellcheck.
- **Carried warning (not fixed — plan forbade touching the deployment target)**: `WATCHOS_DEPLOYMENT_TARGET = 27.0` warns that the watchOS **Simulator** SDK only supports 4.0…26.5.99. Gate still green; watch the real-watch manual run (`run-watch.sh`, `generic/platform=watchOS` device SDK) — if the device refuses 27.0, that's a design-level decision.
- **Watch UI verified by compile only**; runtime is guarded by the manual watch-simulator smokes above.