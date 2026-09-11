# Task

The settings menu (gear button) appears on iPhone and iPad but not on macOS —
users on macOS cannot see the gear icon at all. `ContentView.swift` renders the
settings button as a `.overlay(alignment: .topTrailing)` containing an
`Image(systemName: "gearshape")` inside a bordered rounded-rectangle, toggling
the `isShowingSettings` sheet that hosts `SettingsView`. On macOS the button is
not visible — find out why (candidate causes: the `gearshape` system image
being unavailable/empty on macOS, or the overlay placement/z-order/geometry
clipping on macOS) and fix it so the gear button renders and opens the settings
sheet on macOS exactly as it does on iOS, keeping the iOS behavior unchanged.

## Why SMALL
Single module (ContentView.swift's overlay button); no schema, no new subsystem,
no shared/convention risk, no cross-platform surface beyond already-present
`#if os(...)` gating; ≤2 unknowns (system-image availability vs. overlay
placement on macOS) and an existing platform-gating pattern to follow; no
design decision or sign-off; no test target in this repo (gate is the build).

## Key files
- `CheckStitch/ContentView.swift` — `settingsButton` (`gearshape` image + overlay).
- `CheckStitch/SettingsView.swift` — the sheet the button opens (may need a
  tweak if macOS sheet presentation differs).
- `CheckStitch/AppDelegate.swift` / `MyApp.swift` — existing `#if os(macOS)`
  gating pattern to mirror if a platform split is needed.
- Reference: `/Users/vardy/dev/SingleThread` for how macOS surfaces settings
  affordances (kept on macOS `NSWindow` conventions).