# Task

VAR-1027 — "Create checklist not working on watch": when the user taps
"Create reminders" on the Apple Watch app, no reminders appear in the Reminders
app on their iPhone. Root cause is unknown and must be located before any fix
can be designed; this is a debugging + fix task on a real watch/phone pair.

Context from recon (see below): the watch never touches EventKit. The path is
`WatchChecklistDetailView` button → `WatchChecklistStore.run` →
`WCSession.transferUserInfo(.runChecklist(id))` (guard: returns false unless
the session is `.activated`) → phone `PhoneSyncAdapter.didReceiveUserInfo` →
`ChecklistSyncCoordinator.handle(.runChecklist(id))` → silent guard-drop if the
`id` is not in the phone's snapshot → `ChecklistReminders.create(from:)`
(EventKit, permission + destination resolution + save). The watch button flips
to "Sent" as soon as the transfer is accepted — even if the phone later fails.

## Why LARGE

- **UNKNOWNS** — the root cause is unlocated: ≥3 open questions need research
  and a device spike. (a) Does the `runChecklist` userInfo transfer actually
  reach the phone (WCSession activation on cold launch, phone app not running,
  background delivery)? (b) Does the phone's reminder creation silently fail
  (permission, destination missing, the `EKCADErrorDomain 1021` concurrency
  failure the coordinator's serialized run queue already works around)? (c) Is
  the "Sent" feedback false-positive — transfer accepted but never created?
  Reproducing requires a real paired watch+phone (`bash scripts/run-watch.sh`),
  not the simulator.
- **CROSS_CUTTING, unknown ordering** — the failure surface spans three layers:
  the watch target (transport + UI feedback), the shared `CheckStitchCore`
  seam (`ChecklistSyncMessage` protocol, `WatchChecklistStore`,
  `ChecklistSyncCoordinator`, codec), and the phone target (EventKit create
  path). No existing pattern dictates where the fix lands because the failure
  point is not yet identified; a prior attempt (draft PR #45) contains no
  code — this is unfixed, fresh work.
- A product/UX decision may be needed (what the watch should do when the phone
  is unreachable: queue/retry vs honest failure state vs background delivery),
  which is a human sign-off.

Relevant code (as of classification):
- `CheckStitchWatch/WatchSyncAdapter.swift`, `WatchChecklistDetailView.swift`,
  `WatchChecklistListView.swift`, `CheckStitchWatchApp.swift`
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`,
  `ChecklistSyncCoordinator.swift`, `ReminderCreating.swift`,
  `ChecklistCreator.swift`, `ReminderDestinationTargeting.swift`
- `CheckStitch/PhoneSyncAdapter.swift`, `CheckStitch/MyApp.swift` (coordinator
  wiring), `CheckStitch/ContentView.swift`
- Tests: `CheckStitchTests/WatchChecklistStoreTests.swift`,
  `ChecklistSyncCoordinatorTests.swift`, `ChecklistMessageTests.swift`,
  `ChecklistCreatorTests.swift`, `EventKitReminderCreatorTests.swift`