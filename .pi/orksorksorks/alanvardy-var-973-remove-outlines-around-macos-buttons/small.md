# Task

On macOS in dark mode, CheckStitch's buttons render with the platform's default button chrome — a lighter grey background/bezel surrounding them — which looks wrong against the app's dark appearance. Remove that chrome so buttons render without the lighter grey background.

This exact issue was previously fixed in the SingleThread app (`/Users/vardy/dev/SingleThread` — the ticket's `../SingleThread` reference); mirror that fix pattern:

- Apply `.buttonStyle(.borderless)` to the buttons (SingleThread does this via a shared `ViewModifier` that wraps `.borderless` — `SingleThreadButtonModifier.swift`, commit `2366a8fc`; `.borderless` is a no-op on iOS/iPadOS and removes the translucent bezel on macOS).
- For the action `Menu` (if any), SingleThread used `.menuStyle(.borderlessButton)`.
- SingleThread also builds a self-drawn `.controlPlate()` (circle fill + shadow) for icon-only buttons; CheckStitch's buttons already hand-draw their own `.stroke(.tint)` rounded-rectangle overlays inside their labels (ContentView.swift lines ~62/102/118), so evaluate whether just suppressing the default bezel with `.borderless` suffices, or whether the plate pattern is needed — the goal is only to remove the grey backgrounds, not to redesign the buttons' look.
- Apply the fix only where the grey chrome appears on macOS; keep the iOS look unchanged.

## Why SMALL

All A–F hold: single module (one app target, 5 Swift files), ≤~5 files with a known pattern to follow (SingleThread's prior fix); 0 unknowns worth research — the fix approach and reference implementation are given in the ticket; no schema/migration; no new subsystem or shared/convention code touched (entitlements/pbxproj/scripts unaffected); no design sign-off needed; and there is no test target in this repo (gate is `./scripts/test.sh` = build + shellcheck), so tests needed are few/local.

## Key files (from recon)

- `CheckStitch/ContentView.swift` — the only user-facing buttons: `settingsButton` (~L58), `createChecklistButton` (~L78, stroke overlay at L102), `editChecklistButton` (~L124, stroke overlay L118), plus `EditChecklistView` Form buttons (~L150–188, default-style, no chrome overrides). No `.buttonStyle`/`.background`/`.fill` anywhere.
- `CheckStitch/SettingsView.swift` — toolbar "Done" button (~L40–42), default chrome.
- Reference fix: `/Users/vardy/dev/SingleThread/SingleThreadButtonModifier.swift` (`.borderless` via shared `ViewModifier`), `/Users/vardy/dev/SingleThread/ControlPlateModifier.swift`, usage in `SingleThread/ContentView+ActionMenu.swift` (`.singleThreadButton()` + `.menuStyle(.borderlessButton)`). SingleThread's guard-rail tests (`MacOSActionButtonChromeTests.swift`, `SingleThreadButtonModifierTests.swift`) assert the modifiers by string-describing the view.
- Not implicated: `AppGroup.entitlements`, `project.pbxproj`, `scripts/`, `Makefile`.