# Task

Add an **Interface** settings subscreen to CheckStitch containing two controls:
a **Text Size** picker (System / Small / Medium / Large / Extra Large) that
scales text app-wide via SwiftUI Dynamic Type, and an **Allow landscape**
toggle that lets the iPhone app rotate (lock otherwise portrait).

The reference implementation lives in `/Users/vardy/dev/SingleThread` — the
ticket says "See ../SingleThread for details on implementation and do it the
same way." Copy its shape:

- `SingleThread/TextSize.swift` — `TextSize: String, CaseIterable` enum mapping
  each case to `DynamicTypeSize?` (.system → nil), plus `systemImage` and
  `title` (localized).
- `SingleThread/TextSizeModifier.swift` — conditional `.dynamicTypeSize(size)`
  view modifier, applied at the `ContentView` root.
- `SingleThread/InterfaceSettingsView.swift` — the subscreen: appearance (already
  exists in CheckStitch), Text Size picker (`textSizePicker`), Allow landscape
  toggle (`allowLandscapeToggle`) gated `#if os(iOS)` with caption
  "Let the app rotate on iPhone.", using `.settingsSubscreenLayout()` (already
  exists in CheckStitch).
- `SingleThread/AppDelegate.swift` — scene-delegate extension implementing
  `supportedInterfaceOrientationsFor`, reading the persisted `allowsLandscape`
  key (missing key → `true`), plus a static `applyLock(allowsLandscape:)` that
  calls `setNeedsUpdateOfSupportedInterfaceOrientations()` and
  `requestGeometryUpdate`. CheckStitch's `CheckStitch/AppDelegate.swift` already
  bridges persisted settings into UIKit the same way — extend that pattern, and
  call `applyLock` from the toggle's `.onChange` (SingleThread does this via a
  `SettingsViewModel.allowsLandscapeChanged`).

CheckStitch specifics, following its existing settings patterns
(`CheckStitch/AppearanceMode.swift`, `CheckStitch/SettingsView.swift`,
`CheckStitch/SettingsBindings.swift`, `CheckStitch/SettingsSubscreenLayout.swift`,
`CheckStitch/BackgroundSettingsView.swift`):

- Add `TextSize` + `TextSizeModifier` under `CheckStitch/` (app target; the
  watch target shares only Core and needs no interface settings).
- Add `allowsLandscape` and `textSize` as `@AppStorage` properties on
  `ContentView` (as `appearanceMode` etc. already are) and apply the text-size
  modifier at the root; stage the new prefs through the settings sheet
  writeback path (`settingsSheetWritebacks`) like the background keys.
- Add an "Interface" `NavigationLink` row in `SettingsView` that pushes the new
  subscreen (same shape as the Background row), taking bindings rather than the
  whole bag.
- Add new strings to `CheckStitch/Localizable.xcstrings` (Text Size,
  System/Small/Medium/Large/Extra Large, Allow landscape, captions) — the repo
  keeps 6 committed `*.lproj` folders.
- macOS must not regress: no landscape row on macOS; Text Size should apply
  there too.

Tests (add to existing `CheckStitchTests`, Swift Testing, following
`AppearanceModePreferenceTests.swift` / `AppearanceModeTests.swift` /
`SettingsBindingsTests.swift` precedent): TextSize enum mapping + persistence
round-trip, missing-key defaults to landscape-allowed, orientation-mask
selection for both values, and the settings view renders the new rows.

Gate: `make test-unit` first, then `bash scripts/test.sh`; new logic ships with
happy and sad path tests.

## Why MEDIUM

MULTI_MODULE + CROSS_CUTTING (known ordering): the change spans ~8–10 files
across the settings UI, `ContentView` root, the iOS `AppDelegate` platform
bridge, localizations, and several test suites — but the SingleThread reference
carries it end to end, so the approach is already known (M1) and there is no
design decision, schema, new subsystem, or shared/convention risk (M2).

## Key files

- `/Users/vardy/dev/SingleThread/TextSize.swift` — reference enum
- `/Users/vardy/dev/SingleThread/TextSizeModifier.swift` — reference modifier
- `/Users/vardy/dev/SingleThread/InterfaceSettingsView.swift` — reference subscreen
- `/Users/vardy/dev/SingleThread/AppDelegate.swift` — reference orientation lock
- `CheckStitch/SettingsView.swift` — add Interface row + subscreen push
- `CheckStitch/SettingsBindings.swift` — stage new prefs (or thread bindings)
- `CheckStitch/ContentView.swift` — `@AppStorage` keys, root text-size modifier,
  settings sheet writebacks (`settingsSheetWritebacks`, ~line 540)
- `CheckStitch/AppDelegate.swift` — orientation mask + `applyLock`
- `CheckStitch/Localizable.xcstrings` — new strings
- `CheckStitchTests/` — new TextSize / orientation / settings-view suites