# Task

VAR-1027 — "Create checklist not working on watch": when the user taps
"Create reminders" on the Apple Watch app, no reminders appear in the Reminders
app on their iPhone. The root cause is unknown and must be located before any
fix can be designed; this is a debugging + fix task on a real watch/phone pair.

The suspected path is: watch button → WatchChecklistStore.run →
WCSession.transferUserInfo(.runChecklist(id)) → phone PhoneSyncAdapter
didReceiveUserInfo → ChecklistSyncCoordinator.handle(.runChecklist(id)) →
silent guard-drop if the id is not in the phone's snapshot →
ChecklistReminders.create(from:) (EventKit). The watch button flips to "Sent"
as soon as the transfer is accepted, even if the phone later fails. A prior
attempt (draft PR #45) contains no code — this is unfixed, fresh work.