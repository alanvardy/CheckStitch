# Task

Investigate and contain a production Sentry "App Hang Fully Blocked" in
CheckStitch (issue 7849871699, culprit `MyApp.$main`) captured on iOS 27.2.1.
The hung main thread contains **no CheckStitch app-code frames** — it is stuck
entirely inside system frameworks (`AccessibilitySettingsLoader` /
`GuidedAccessManager` → `_NSFrameworkPathFromLibraryPath` →
`-[NSBundle loadAndReturnError:]`), while the only in-app-adjacent thread is the
Sentry ANR tracker (`monitorThreadCache` sleeping). The ticket notes the same
class of hang may already have been fixed in `../SingleThread` (VAR-1165, which
added a system-stall signature drop to `beforeSend`); that precedent should be
consulted, but the signature there targeted a *different* stall
(BackBoardServices/libxpc), so the correct fail-open signature for this hang
must be diagnosed, and any fix must be backed by a unit test per repo policy.

## Why LARGE

Matched triggers: **UNKNOWNS** (the crash report has no app-code culprit frame,
so the hang's root cause and the system-stall signature that would safely
identify it must be diagnosed via spike/repro before an approach exists — the
SingleThread precedent's BackBoardServices signature does not cover this stack)
and **CONVENTION_RISK** (the containment lives in `SentryScrubber`, the shared
privacy/`beforeSend` path applied to every Sentry event and breadcrumb, and
drops an entire exception class). Decisive signal: with no known culprit and a
signature that must be derived rather than copied, neither M1 ("approach known,
0–2 unknowns") nor the SMALL A–B criteria hold. The directly analogous
SingleThread ticket VAR-1165 was itself routed LARGE on the same reasoning.
