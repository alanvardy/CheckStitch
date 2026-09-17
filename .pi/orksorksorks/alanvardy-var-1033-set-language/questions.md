# Research Questions

## Context

Focus on the CheckStitch repo (/Users/vardy/dev/alanvardy-var-1033-set-language):
how the app resolves localized UI strings at runtime, the settings/interface
UI surface, existing persisted-user-preference patterns, per-platform startup
paths (iOS app, macOS leg, watch target), and the localization test suites
that gate the string catalogs. All findings should carry file:line
references; describe what exists, not what should change.

## Questions

1. [codebase-analyzer] How does localized-string resolution work in this
   codebase at runtime? Trace from the Localizable.xcstrings catalogs and
   SharedStrings through bundle loading to the rendered string: what
   determines which language String(localized:) resolves to on each platform
   target (iOS app, macOS leg, watch), and what locale-related Foundation or
   Swift APIs, hooks, or environment mechanisms does the code reference (or
   deliberately avoid)? Include any test-only locale pinning.

2. [codebase-pattern-finder] What patterns exist in the codebase for a
   user-persisted preference — a settings choice that is read from UserDefaults
   / @AppStorage, written back, and applied app-wide? Cover the
   AppearanceModePreference and AppearanceMode load/save lifecycle, the
   @AppStorage props on ContentView, per-platform storage (AppGroup.defaults,
   UserDefaults.standard, NSUbiquitousKeyValueStore), default-value handling,
   and the test suites that exercise these paths.

3. [codebase-analyzer] How is the Settings screen structured in SwiftUI —
   the modal sheet presented from ContentView? Trace SettingsView end to end:
   the Form/Section/NavigationLink/Picker/toolbar primitives, how the
   appearance Picker's selection flows from staged bindings to persisted
   storage to applied appearance, how the background settings subscreen and
   About view are reached, and what an "interface" grouping would sit beside.

4. [codebase-analyzer] How does each platform target start up and apply
   app-wide configuration? Trace the entry points (CheckStitch/MyApp.swift,
   iOs and macOS delegates, CheckStitchWatch app) to where settings are
   loaded and applied (e.g. applyAppearance), where per-target view
   hierarchies are built, and which bundle/table each target's localized
   strings use (bundle .main vs core .module).

5. [codebase-pattern-finder] What do the localization test suites assert
   about the string catalogs and SharedStrings in each target? Cover
   LocalizationTests.swift, its helpers and fixtures (catalog loading,
   required keys, canary values, guarded catalogs, per-language
   InfoPlist.strings keys), how locale is pinned in tests, and which
   target/platform each suite runs on.