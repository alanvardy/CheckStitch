# Task

On the native macOS build of CheckStitch, the red close button at the top-left of the window does nothing: clicking it neither closes the window nor quits the app. (The macOS target already exists — `SUPPORTED_PLATFORMS` includes `macosx`, `MACOSX_DEPLOYMENT_TARGET = 27.0`; the macOS app is built with `xcodebuild -destination 'platform=macOS'` and launched via `open`, the same path `scripts/run-devices.sh`'s host step uses.)

The app currently has no window close/quit handling at all: `CheckStitch/MyApp.swift` uses a bare `WindowGroup { ContentView(environment:) }`, and `MacAppDelegate` (in `CheckStitch/AppDelegate.swift`, registered via `@NSApplicationDelegateAdaptor` on macOS) only applies the persisted appearance to `NSApp.windows` in `applicationDidFinishLaunching`/`applicationDidBecomeActive`. No `NSWindowDelegate`, `applicationShouldHandleReopen`, `onClose`, or `windowResizability` exists anywhere in the repo.

Make the red close button work per standard macOS convention (close the window with the app remaining active in the Dock, with Cmd-W closing and Cmd-Q quitting as usual), or the closest equivalent that matches how the button is observed to misbehave. Fix the root cause found on reproduction. The fix must stay behind `#if os(macOS)` and be confined to the thin `CheckStitch/` app target — do not touch `CheckStitchCore`, the shared scheme, or build settings unless the reproduction proves a build-side cause. Nothing in the views overlays the title bar / traffic-light area (`ContentView`'s only overlay is top-trailing), so suspect the scene/window configuration or the `NSApplication`/`NSWindow` lifecycle before anything in a view.

Verify by building and launching the macOS app (`xcodebuild ... -destination 'platform=macOS' ... CODE_SIGNING_ALLOWED=NO build`, then launch the built `.app`) and clicking the close button. New logic ships with a test covering the behavior where feasible (render/delegate-level, in the existing `CheckStitchTests` style — there is no macOS window-level UI harness; do not build new test infrastructure). Run the gate `./scripts/test.sh` before committing.

## Why SMALL

Single module (thin app target) and ~2 files following the existing `#if os(macOS)` delegate seam; 1 unknown (root cause, resolved by reproduction on the existing macOS build path); no schema, no new subsystem, no shared/build-convention code, no design sign-off (standard macOS window conventions); tests few and local.

## Key files

- `CheckStitch/MyApp.swift` — scene/window config: bare `WindowGroup` at :26-30; `#if os(macOS)` delegate adaptor at :21-24.
- `CheckStitch/AppDelegate.swift` — `MacAppDelegate` (:44-62) is the natural home for any `NSWindowDelegate`/close codepath; mirrors the iOS-side adaptation style.
- `CheckStitch/ContentView.swift` — read-only for confirmation that no view covers the traffic lights (verified: only a top-trailing settings overlay).
- Build/run: `scripts/run-devices.sh` (macOS build with `CODE_SIGNING_ALLOWED=NO`, launched via `open`); gate `scripts/test.sh`.