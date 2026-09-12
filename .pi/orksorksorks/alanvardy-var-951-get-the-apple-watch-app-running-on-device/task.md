# Task

Get CheckStitch (currently an iOS-only Reminders-checklist app: one target,
`ContentView.swift` + `MyApp.swift`) building and running on a real Apple
Watch device, mirroring SingleThread's completed VAR-602 (`SingleThreadWatch`
targets with `SUPPORTED_PLATFORMS = "watchos watchsimulator"` /
`TARGETED_DEVICE_FAMILY = 4`). On-device the app must be able to **run a
checklist** (read items from a CheckStitch Reminders list and let the user
check them off); create/edit/delete are explicitly out of scope for the watch.