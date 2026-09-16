# Research Questions

## Context

Focus on the Watch-to-phone checklist sync flow in the CheckStitch codebase:
the CheckStitchWatch target (app entry, list/detail views, WatchSyncAdapter,
WatchChecklistStore), the sync seam in CheckStitchCore (ChecklistSync.swift,
ChecklistSyncCoordinator, ChecklistSyncing.swift), the phone-side adapters in
CheckStitch (PhoneSyncAdapter, MyApp wiring, ChecklistSyncService), the
reminder-creation seam (ReminderCreating, ChecklistCreator,
ReminderDestinationTargeting, EventKitReminderDestination, ChecklistReminders),
and the corresponding test suites and hardware-run scripts
(scripts/run-watch.sh, scripts/run-devices.sh). Describe what exists with
file:line references; do not suggest improvements or propose solutions.

## Questions

1. **Watch-side send path**: How does the "Create reminders" button on the
   watch detail view reach the WCSession — trace WatchChecklistStore.run,
   WatchSyncAdapter.sendUserInfo, the WCSession activation guard, and the
   transferUserInfo call, plus the "Sent" button-state feedback. When can
   sendUserInfo return false, and does anything on the watch retry or observe
   delivery after transferUserInfo is accepted?

2. **Phone-side reception**: How does the phone app receive incoming WCSession
   userInfo — trace PhoneSyncAdapter's WCSessionDelegate (didReceiveUserInfo),
   its activation requirements, and how the session and coordinator are wired
   in MyApp. What are the lifecycle and delivery constraints for a
   transferUserInfo to reach a phone app that is not running, is backgrounded,
   or is cold-launching, and what guards could drop the message before it
   reaches the coordinator?

3. **Coordinator handling and error visibility**: How does
   ChecklistSyncCoordinator handle a .runChecklist message — the snapshot()
   lookup, the serialized pendingRun queue, and every path where the run is
   dropped or an error is swallowed without observable feedback. Is the
   createReminders closure's error observed anywhere, and does the phone
   provide any success/failure feedback back to the watch?

4. **Checklist data provenance**: Where does the watch's checklists list and
   each checklist's IDs come from, and how do those IDs relate to the phone's
   store.checklists snapshot — trace the applicationContext push
   (sendContext/pushContext), the requestChecklists refresh, and the iCloud
   KVS ChecklistSyncing seam. Can the watch hold a checklist ID that the
   phone's snapshot lacks (stale context, partial delivery, ordering), and
   what determines when the phone's snapshot is populated?

5. **Reminder creation on the phone**: How does the phone create reminders
   from a checklist — trace ChecklistReminders.create(from:),
   ReminderDestinationTargeting resolution, EventKitReminderDestination and
   EventKitReminderCreator, including the requestAccess/permission path,
   defaultCalendarForNewReminders, save(commit:) under #if !os(watchOS), and
   the documented EKCADErrorDomain 1021 concurrency workaround. Under what
   conditions does creation fail or abort without creating any reminders, and
   are failures surfaced anywhere?

6. **Test coverage and hardware-run scripts**: What do the existing suites
   cover on this send-to-create chain — WatchChecklistStoreTests,
   ChecklistSyncCoordinatorTests, ChecklistMessageTests, ChecklistCreatorTests,
   EventKitReminderCreatorTests and the fakes in TestFixtures — and which
   links in the chain (real WCSession, PhoneSyncAdapter, background delivery,
   error paths) have no test coverage? What role do scripts/run-watch.sh and
   scripts/run-devices.sh play in exercising this on real hardware, and what
   do they check?