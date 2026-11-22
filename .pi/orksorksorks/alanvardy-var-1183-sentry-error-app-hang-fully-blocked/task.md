# Task

Investigate and contain a production Sentry "App Hang Fully Blocked" reported
against CheckStitch (issue 7849871699, culprit `MyApp.$main`). The hung main
thread contains no CheckStitch app-code frames — it is trapped inside system
frameworks (`AccessibilitySettingsLoader` / `GuidedAccessManager` →
`_NSFrameworkPathFromLibraryPath` → `-[NSBundle loadAndReturnError:]`) — so the
root cause is a system stall, not an app-logic bug.

The containment belongs in the shared Sentry `beforeSend`/`beforeBreadcrumb`
privacy path (`SentryScrubber`), which should drop this class of system-stall
hang using a stack-frame signature derived for this specific stall. The
directly analogous SingleThread ticket VAR-1165 added a system-stall drop, but
its signature targeted a different stall (BackBoardServices/libxpc), so it must
be re-derived here. Repo policy requires the fix be backed by a unit test.
