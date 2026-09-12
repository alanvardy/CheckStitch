# Task

Fix VAR-974: on macOS, switching the app to Light mode does nothing — the app
stays in Dark mode (the persisted setting and picker update, but the windows
never change appearance).

The appearance plumbing already exists end to end in main (this is a bug fix,
not a feature):

- `CheckStitch/AppearanceMode.swift` — `enum AppearanceMode: String, CaseIterable`
  (`.system`/`.light`/`.dark`), persisted in `UserDefaults.standard` under key
  `"appearanceMode"` via `@AppStorage`/`AppearanceModePreference`.
- `CheckStitch/AppDelegate.swift` — the iOS twin (`UIWindow.overrideUserInterfaceStyle`)
  works; the macOS `MacAppDelegate` sets `window.appearance = mode.appKitAppearance`
  (`.light` → `NSAppearance(named: .aqua)`, `.dark` → `.darkAqua`, `.system` → `nil`)
  from `applicationDidFinishLaunching` and `applicationDidBecomeActive`.
- `CheckStitch/MyApp.swift` — registers `MacAppDelegate` via `@NSApplicationDelegateAdaptor`.
- `CheckStitch/SettingsView.swift` — appearance picker; `AppearanceMode.light.colorScheme`
  already works in the SwiftUI canvas preview (the `preferredColorScheme` path), so the
  failing piece is the window-level `NSWindow.appearance` bridge.

Diagnose why the `NSWindow.appearance` assignment doesn't take effect on macOS —
e.g. wrong API/property for this AppKit version, wrong window collection (`NSApp.windows`
vs. all realized windows), or wrong timing (appearance set before windows exist /
after they're shown), or the canvas needing `AppearanceMode.colorScheme` threaded
through `ContentView.swift`. Cross-check against the working reference implementation
at `/Users/vardy/dev/SingleThread` and the iOS counterpart before fixing. Apply the
smallest fix that makes Light/Dark switch the whole window live (picker already
triggers re-application via `applicationDidBecomeActive`).

Constraints: `.system` must keep following the OS appearance; the iOS path must keep
working. Gate is `./scripts/test.sh` (build + shellcheck; no test target — do not add
one). Note the worktree currently has a stray deleted `DELETEME` file committed by the
branch's `chore: start` commit — exclude it from the fix (leave as-is or delete, don't
mix it into this change). Do not push to main; the branch already has a draft PR #13.

## Why SMALL

Single module (~3 Swift files), follows the existing iOS/`AppearanceMode` pattern;
no schema, no new integration, no design decision — a localized bug fix with at most
1–2 AppKit API unknowns, and the gate is a build (no test surface).

## Key files

- `CheckStitch/AppDelegate.swift` — `MacAppDelegate` (the fix lives here; iOS twin for reference)
- `CheckStitch/AppearanceMode.swift` — `appKitAppearance` / `colorScheme` mapping
- `CheckStitch/MyApp.swift` — `@NSApplicationDelegateAdaptor(MacAppDelegate.self)` registration
- `CheckStitch/ContentView.swift` — check for hardcoded dark styling that ignores the window appearance