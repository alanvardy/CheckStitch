# Task

Add a settings menu to CheckStitch:

1. **Gear button** — show a gear (SF Symbol `gearshape`) in the top-left corner
   of the screen (`Content` in `CheckStitch/ContentView.swift`).
2. **Settings modal** — tapping the gear opens a modal settings screen, the
   same shape as SingleThread's `SettingsView.swift` (a modal presented from
   the gear button; see `/Users/vardy/dev/SingleThread/SingleThread/SettingsView.swift`
   and `ContentView+Settings.swift`).
3. **Single entry: theme** — port SingleThread's appearance/theme code as-is;
   it has gotchas, so follow the reference implementation exactly:
   - `AppearanceMode` enum (`.system` / `.light` / `.dark`) from
     `/Users/vardy/dev/SingleThread/SingleThread/AppearanceMode.swift`,
     persisted through `UserDefaults` via `@AppStorage` (the `AppearanceModePreference`
     backing store), with `load(from defaults:)` defaulting to `.system`.
   - Applied at the **window level**, not per-view: `UIWindow.overrideUserInterfaceStyle`
     on iOS. `.system` means "clear the override → follow the device"
     (`windowOverrideStyle` returns `.unspecified`).
   - `colorScheme` (`ColorScheme?`, `nil` for `.system`) exists only for
     SwiftUI previews — a preview has no window to override.
   - The modal itself must reference the setting through the same bindings and
     `preferredColorScheme(...)` picker pattern as SingleThread's `SettingsView.swift`.
   - No new tests: CheckStitch has no test target; the gate is the build +
     shellcheck, so keep the build green.

CheckStitch is VerseVision SwiftUI (like SingleThread) with a `ContentView.swift`
and `MyApp.swift`. Wire the theme override where CheckStitch's iOS root window
is created (mirroring where SingleThread applies `windowOverrideStyle`).
New files go under `CheckStitch/` — no `.pbxproj` edit needed.

## Why SMALL

Single module (~2 existing Swift files + a small ported settings/theme pair,
≤5 files), approach entirely dictated by the SingleThread reference (0–2
unknowns — the "gotchas" are documented in that code, not open questions), no
schema/migration, no new subsystem or shared/convention code, no design
decision to sign off (ticket and reference specify it), and tests required are
none — a few local ones at most.

## Key files

- `CheckStitch/ContentView.swift` — sole screen; add the gear button and host/modal.
- `CheckStitch/MyApp.swift` — app root; apply the theme window override.
- New: `CheckStitch/AppearanceMode.swift` (+ its `AppearanceModePreference`
  storage) and a `CheckStitch/SettingsView.swift`, ported from
  `/Users/vardy/dev/SingleThread/SingleThread/AppearanceMode.swift`,
  `SettingsView.swift`, and `ContentView+Settings.swift`.