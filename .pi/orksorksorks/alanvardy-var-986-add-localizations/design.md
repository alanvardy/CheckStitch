# Design Discussion

Ticket: VAR-986 — Add localizations (de, en, es, fr, ja, zh-Hans) to
CheckStitch, mirroring SingleThread (VAR-749 / VAR-791).

## Current State

CheckStitch ships every user-facing string as a hardcoded English literal and
has zero localization infrastructure: no `.lproj`, no `.xcstrings`, no
`LocalizedString` types. The build system is already localization-ready — it
just has no resources and no migrated strings.

- **App target** (`CheckStitch/`, iOS + macOS via
  `SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`): ~39 user-facing
  literals across `ContentView.swift` (8), `ChecklistDetailView.swift` (12),
  `BackgroundSettingsView.swift` (10), `SettingsView.swift` (6),
  `ChecklistStore.swift` defaults (3), `AppearanceMode.swift` picker labels
  (3).
- **CheckStitchCore SPM package**: ~4 user-facing strings — `AppearanceMode`
  labels (`CheckStitchCore/.../AppearanceMode.swift:67-71`) and the persisted
  defaults `"New checklist"` (`Checklist.swift:23`) / `"New item"` /
  `defaultChecklistName` + seeded `"one"/"two"/"three"`
  (`ChecklistViewModel.swift:15-18`). `Package.swift` has **no** `resources:`
  key.
- **Watch target**: 5 literals — `WatchChecklistListView.swift:17,23`,
  `WatchChecklistDetailView.swift:26`.
- **Membership is directory-synchronized.** All four targets use
  `PBXFileSystemSynchronizedRootGroup` and every `PBXResourcesBuildPhase` /
  `PBXSourcesBuildPhase` is empty (`project.pbxproj:282-326`). Any
  `.xcstrings` or `.lproj` dropped under a target folder is auto-adopted with
  **no pbxproj edit**.
- **Localization settings already set**: project-level
  `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` (`project.pbxproj:405/:470`),
  `developmentRegion = en` (`:258`); app target
  `STRING_CATALOG_GENERATE_SYMBOLS = YES` + `SWIFT_EMIT_LOC_STRINGS = YES`
  (`:513/:517`); watch `SWIFT_EMIT_LOC_STRINGS = YES`. `knownRegions` is still
  `(en, Base)` (`:260`).
- **Generated Info.plist**: `GENERATE_INFOPLIST_FILE = YES` everywhere; app has
  no `CFBundleDisplayName` override, and usage descriptions live as English
  `INFOPLIST_KEY_NSReminders(FulllAccess)UsageDescription` build settings
  (`:494-495`). The watch target hardcodes
  `INFOPLIST_KEY_CFBundleDisplayName = CheckStitch` (`:672/:700`).

The reference project `SingleThread` proves the exact shape this work takes:
per-target `Localizable.xcstrings` with the same six languages, `.lproj/
InfoPlist.strings` per app-side target, a `SharedStrings` enum in core using
`String(localized:table:bundle: .module)`, and a 5-assertion localization test
suite.

## Desired End State

All six languages (en, de, es, fr, ja, zh-Hans) present in per-target string
catalogs; every UI-visible string resolved through a catalog at runtime;
localized app metadata via `.lproj/InfoPlist.strings`; a localization test
suite proving catalogs are complete and translated. The full gate
(`bash scripts/test.sh` → `gate: ok`) stays green.

Correctness is verified by:
1. `make test-unit` passing a new `LocalizationTests` suite that parses the
   `.xcstrings` files from the source tree and asserts every key has a
   non-empty value in all six languages and that non-English values differ from
   English.
2. A test that each `<lang>.lproj/InfoPlist.strings` parses via
   `PropertyListSerialization` and carries every required key.
3. `make build` (simulator), `make build-mac`, `make watch-build` all
   compilating after the string migration.
4. Manual smoke: launch on a device/simulator set to `de` (or another
   non-English locale) and confirm UI copy renders translated and the app
   display name still reads "CheckStitch".

## Patterns to Follow

Follow `SingleThread` — it is the working reference for every mechanism here.

- **One catalog per target, same six languages.** App:
  `CheckStitch/Localizable.xcstrings`; watch:
  `CheckStitchWatch/Localizable.xcstrings`; core:
  `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`.
  `sourceLanguage: "en"`. Reference:
  `SingleThread/SingleThread/Resources/Localizable.xcstrings`.
- **String access**: `String(localized: <key>, table: "Localizable", bundle: .main)`
  for app/target strings; `bundle: .module` for core strings. SwiftUI `Text`/
  `Label`/`Button` literals are auto-extracted
  (`SingleThreadApp+Commands.swift:17,23`).
- **Core strings get a typed home**: an `enum SharedStrings` exposing each core
  key, e.g. `static var system: String { String(localized: "System", table: "Localizable", bundle: .module) }`. Reference:
  `SingleThreadCore/.../LocalizedString+Shared.swift:16-98`.
- **Core package declares resources**: add
  `resources: [.process("Resources")]` to the `CheckStitchCore` target in
  `Package.swift` (reference: `SingleThreadCore/Package.swift:17`) — without
  this the catalog is not compiled into `Bundle.module`.
- **`InfoPlist.strings` measures**: app `.lproj/{en,de,es,fr,ja,zh-Hans}/InfoPlist.strings`
  carrying the two `NSReminders*UsageDescription` keys plus `CFBundleDisplayName`;
  watch `.lproj/*/InfoPlist.strings` carrying only `CFBundleDisplayName` (the
  watch never touches EventKit, so its generated Info.plist has no Reminders
  usage-description key). Reference:
  `SingleThread/de.lproj/InfoPlist.strings`.
- **Locale-pinned tests**: `String.en(key, bundle:, table:)` helper pinning
  `Locale(identifier: "en")`; catalogs read from the source tree via
  `#filePath`-derived URLs, not bundles. Reference:
  `SingleThreadTests/LocalizationTestHelpers.swift:4-24`,
  `LocalizationTests.swift:15,227-238`.
- **Register languages**: extend project `knownRegions` to
  `(en, Base, de, es, fr, ja, zh-Hans)` (`project.pbxproj:260`), matching
  `SingleThread` (`:447-455`).

**Patterns NOT to follow / do differently:**
- Do **not** localize persisted data defaults (`"New checklist"`,
  `"New item"`, `"one"/"two"/"three"`, `"checklist"`) — those are user data that
  syncs to the watch and into Reminders, not UI chrome (see Design Decision 2).
- Do **not** add pbxproj file references or edit the Resources phases — the
  synchronized root groups adopt resources automatically. A pbxproj edit there
  would be a smell.
- Do **not** turn off `STRING_CATALOG_GENERATE_SYMBOLS` (CheckStitch sets it
  YES; SingleThread sets NO). Keep CheckStitch's existing setting.
- Do **not** remove the watch's `INFOPLIST_KEY_CFBundleDisplayName` build
  setting — it intentionally takes precedence over `.lproj`.
- Do **not** "fix" `ContentView.swift:344`'s shadowed `ChecklistWidth` while
  touching strings in that file.

## Design Decisions

1. **String access pattern**: typed constants (`SharedStrings`) for core +
   `String(localized:table:bundle:)` at app call sites and SwiftUI literal
   extraction elsewhere — mirroring SingleThread. Chosen over pure
   `SWIFT_EMIT_LOC_STRINGS` extraction because the test helpers assert against
   resolvable keys from a known bundle, and core strings need `Bundle.module`
   routing.

2. **Localization scope**: UI-visible copy only — view/nav/button/alert text,
   accessibility labels, `AppearanceMode` labels, `ContentUnavailableView`.
   Persisted defaults stay English literals because they become user data that
   is synced and frozen at creation time.

3. **`AppearanceMode` duplication**: localize the labels independently in both
   the app catalog and the core catalog. The app keeps using its own
   `AppearanceMode`; deduping the two types is out of scope.

4. **`InfoPlist.strings` scope**: all six `.lproj` dirs in both app and watch.
   The app `.lproj` files localize the two Reminders usage descriptions and
   carry an unchanged `CFBundleDisplayName = CheckStitch`; the watch `.lproj`
   files carry only `CFBundleDisplayName` — the watch never touches EventKit
   (it forwards run requests to the phone), so its generated Info.plist has no
   Reminders usage-description key.
   Usage-description build settings remain English, matching the reference.

5. **Test fidelity**: port all 5 SingleThread localization assertions, minus
   the plural-variations test (CheckStitch has no plural keys) — with the
   non-English-differs check retained as the translation canary. Add
   `LocalizationTestHelpers.swift` with `String.en` and a `Bundle.core`
   resolver for `CheckStitchCore_CheckStitchCore.bundle`.

6. **Language set**: exactly de, en, es, fr, ja, zh-Hans — the ticket's "common
   languages" and the reference project's set.

## What We're NOT Doing

- No new languages beyond the six specified.
- No localization of persisted defaults, storage keys (`"checklists.v1"`),
  `UserDefaults` rawValues, SF Symbol names, accessibility identifiers, or
  logger messages.
- No dedup/refactor of `AppearanceMode` or `ChecklistWidth`.
- No removal of the watch `INFOPLIST_KEY_CFBundleDisplayName` build setting.
- No plural-variation architecture beyond what naturally appears in catalogs
  (`"\(percent)%"` needs no plural category; there is no `%lld` noun key).
- No widget target (none exists), no App Store metadata localization, no
  release-notes/`WhatsNew`.
- No changes to gate ordering, simulator discipline, or shell test stubs —
  unless a new script is genuinely required (it is not expected to be).
- No child tickets; all work lands on the main VAR-986 ticket.

## Open Risks

- **Catalog capture completeness.** Xcode behavior for `"\(percent)%"`
  (interpolation) and accessibility-label string literals may produce
  `%lld`-style keys; if tests read `.xcstrings` from the tree, any string Xcode
  extracted but we did not intend to localize will show as a missing
  translation. Mitigation: keep keys explicit/simple where possible; verify on
  the first simulator build what Xcode actually extracted.
- **`AppearanceMode` in core is referenced by both app and package.** Adding
  resources to `Package.swift` changes the package product; confirm all four
  targets still link and `make test-unit` (which does `@testable import
  CheckStitchCore`) resolves `Bundle.core` from `.main`.
- **Generated Info.plist merge order** (`INFOPLIST_KEY_*` vs `.lproj`) is
  inferred from SingleThread's working pattern, not experimentally verified on
  this Xcode toolchain. The watch display name is the one known
  precedence-sensitive case; verify manually.
- **Non-English-differs exceptions** will need a small exclusion list (e.g.
  `CFBundleDisplayName`, `%lld%%`-style keys, app-name strings) — building it
  requires seeing the first catalog output.
- **`knownRegions` edit** is a pbxproj change; it is cosmetic for runtime but
  needed for Xcode to surface the languages. Keep it minimal and verify
  `make build` still parses the project.