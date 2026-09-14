# Task

Add an About screen to CheckStitch, mirroring the already-shipped SingleThread
feature (VAR-651). An "About" row in Settings pushes a read-only About view —
using the existing `NavigationStack` NavigationLink pattern already used for
`BackgroundSettingsView` — showing the app display name, "Copyright 2026 Alan
Vardy", a developer-credit line, the version string, and a feedback contact
(mailto link to `alan@vardy.cc`). Follow the SingleThread mirror exactly:
`AboutView.swift` in the app target, a bundle-derived injectable `AppInfo`
struct in Core, and the `settingsSubscreenLayout()` modifier (already present
in CheckStitch).

## Why MEDIUM

MULTI_MODULE — the change spans the CheckStitchCore package (new `AppInfo`
struct reading the `Bundle`, new localizable version string), the CheckStitch
app target (new `AboutView.swift`, an About row in `SettingsView.swift`,
localization keys), and CheckStitchTests (~3 new files) — roughly 8 files
across two packages. M1–M2 hold: the approach is a straight mirror of
SingleThread's VAR-651 with zero unknowns, and there is no schema change, no
new subsystem, and no design decision to sign off.

## Key files

Reference mirror (read first):
- `/Users/vardy/dev/SingleThread/SingleThread/AboutView.swift`
- `/Users/vardy/dev/SingleThread/SingleThreadCore/Sources/SingleThreadCore/AppInfo.swift`
- `/Users/vardy/dev/SingleThread/SingleThread/SettingsView.swift` (About row ≈ lines 145–157)
- `/Users/vardy/dev/SingleThread/SingleThreadTests/AboutViewTests.swift`, `AppInfoTests.swift`, `StubBundle.swift`

CheckStitch app target:
- `CheckStitch/SettingsView.swift` — add an About `NavigationLink` row mirroring the existing Background row (`.accessibilityIdentifier("settingsAboutRow")`), pushing `AboutView()`.
- new `CheckStitch/AboutView.swift` — a Form with display-name label, copyright, developer credit, `appInfo.versionDescription`, and the feedback `Link`; apply `.settingsSubscreenLayout()` (modifier already exists in `CheckStitch/SettingsSubscreenLayout.swift`).

CheckStitchCore:
- new `CheckStitchCore/Sources/CheckStitchCore/AppInfo.swift` — injectable `Bundle`-reading struct (`CFBundleShortVersionString`, `CFBundleVersion`, display name) + `feedbackEmail` constant + localized "Version \(marketing) (\(build))" string.
- localization keys: `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings` and/or `CheckStitch/Localizable.xcstrings` (existing `Localizable.xcstrings`/`.lproj` pattern; `GENERATE_INFOPLIST_FILE = YES` already set).

Tests (CheckStitchTests, Swift Testing): new `AppInfoTests.swift`, `AboutViewTests.swift`, `StubBundle.swift` mirroring the SingleThread suites; follow existing `ViewRenderTests.swift` / localization-test patterns. Verify with `make test-unit` before the full `bash scripts/test.sh` gate.