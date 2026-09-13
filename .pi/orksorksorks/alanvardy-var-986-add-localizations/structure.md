# Structure Outline

## Approach

Build the localization surface bottom-up: first the resource/test plumbing (so
catalogs can be compiled and asserted on), then author the three catalogs
(app, core, watch) with all six languages, then route each target's UI copy
through its catalog — core (`Bundle.module`) before app before watch — and
finally localize `Info.plist` metadata via `.lproj/InfoPlist.strings`. Every
layer ships its tests; `make test-unit` is the fast checkpoint and the full gate
(`bash scripts/test.sh`) is the top-of-stack checkpoint. No pbxproj file refs
are ever added — directory-synchronized groups adopt every resource.

---

## Layer 1: Foundation — resource plumbing, test harness, language registration

Delivers everything that later layers need to compile and assert against:
the core package compiles its catalog into `Bundle.module`, the test target has
locale-pinned lookup helpers and a catalog parser, and Xcode knows the six
languages. Green here proves helpers resolve and can parse a (possibly empty)
catalog.

**Files**: `CheckStitchCore/Package.swift`, `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings` (new, skeleton), `CheckStitch/Localizable.xcstrings` (new, skeleton), `CheckStitchWatch/Localizable.xcstrings` (new, skeleton), `CheckStitchTests/LocalizationTestHelpers.swift` (new), `CheckStitchTests/LocalizationTests.swift` (new), `CheckStitch.xcodeproj/project.pbxproj` (`knownRegions` :260)

**Key changes**:
- `CheckStitchCore` target gains `resources: [.process("Resources")]` — without it the core catalog never reaches `Bundle.module`
- `func String.en(_ key: String, bundle: Bundle, table: String = "Localizable") -> String` — pins `Locale(identifier: "en")` for host-locale-independent assertions
- `extension Bundle { static var core: Bundle }` — resolves `CheckStitchCore_CheckStitchCore.bundle` from `.main`, `preconditionFailure` if absent
- `struct CatalogKey { key: String; localizations: [String: String] }` + `func loadCatalogs(fromSourceTree:) throws -> [CatalogKey]` — `#filePath`-derived source-tree reader, shared by all later assertions
- `knownRegions = (en, Base, de, es, fr, ja, zh-Hans)`

**Tests**: `SmokeTests` unchanged (canary); new `LocalizationTests.catalogsParseAndHaveNonEmptyEnglish` (parses each skeleton — sad path: malformed JSON throws the right error). `LocalizationTestHelpers` covered by a trivial lookup test.
**Verify**: `make test-unit` green; `make build`, `make build-mac`, `make watch-build` all still compile with the package resource change.

---

## Layer 2: Catalog content — all keys × six languages

Populates the three catalogs with the full key inventory and all six
translations. This is the data layer every consumer reads from; green proves
every key is present in every language and that non-English values are real
translations.

**Files**: `CheckStitch/Localizable.xcstrings`, `CheckStitchWatch/Localizable.xcstrings`, `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`; `CheckStitchTests/LocalizationTests.swift`

**Key changes**:
- App catalog: ~39 keys (the 8 + 12 + 10 + 6 view literals from `research.md` Q1 plus `System`/`Light`/`Dark`)
- Core catalog: `System`, `Light`, `Dark`
- Watch catalog: `No checklists`, `Open CheckStitch on your iPhone.`, `Checklists`, `Sent`, `Create reminders`
- `sourceLanguage: "en"`; every key carries `en, de, es, fr, ja, zh-Hans` string units
- `excludedIdentities` list for the non-English-differs canary (e.g. `CFBundleDisplayName`, `%lld%%`-style keys, proper-noun/identical terms like `System` in de) — built from the first real catalog output

**Tests**: `catalogsHaveAllSixLanguages` (happy: every key resolves; sad: a deliberately omitted language fails), `nonEnglishValuesDifferFromEnglish` (translation canary with exclusions). No plural-variation test — CheckStitch has no `%lld` noun keys.
**Verify**: `make test-unit` green for all three catalogs.

---

## Layer 3: Core string access — `SharedStrings` + localized `AppearanceMode`

Routes every core-owned user-facing string through the core catalog via
`Bundle.module`. Green proves core strings resolve from the compiled package
bundle, not just from the source-tree JSON.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/SharedStrings.swift` (new), `CheckStitchCore/Sources/CheckStitchCore/AppearanceMode.swift`, `CheckStitchTests/LocalizationTests.swift`, `CheckStitchTests/AppearanceModeTests.swift`

**Key changes**:
- `enum SharedStrings { static var system: String; static var light: String; static var dark: String }` — each `String(localized: <key>, table: "Localizable", bundle: .module)` (extended by later core keys)
- `AppearanceMode.label: String` returns `SharedStrings.*` instead of the duplicated literals (`AppearanceMode.swift:67-71`)

**Tests**: new core-lookup assertions using `String.en(..., bundle: .core)`; extend `AppearanceModeTests` to assert labels resolve through `Bundle.core` (happy: `dark` → `Dark`; sad: resolver precondition when the bundle name is wrong, exercised via a fixture). Persisted defaults (`"New checklist"`, `"New item"`, `one/two/three`, `"checklist"`) are **not** localized (Design Decision 2) and keep their existing tests untouched.
**Verify**: `make test-unit` green; `make watch-build` still compiles core (it links the package).

---

## Layer 4: App string migration — every view literal through the app catalog

Migrates the app target's UI copy to catalog-backed lookups, keeping behaviour
identical. Green proves the app compiles on both slices and its keys resolve
from the test host via `.main`.

**Files**: `CheckStitch/ContentView.swift`, `CheckStitch/ChecklistDetailView.swift`, `CheckStitch/BackgroundSettingsView.swift`, `CheckStitch/SettingsView.swift`, `CheckStitch/AppearanceMode.swift`, `CheckStitchTests/LocalizationTests.swift`, `CheckStitchTests/ViewRenderTests.swift`

**Key changes**:
- SwiftUI `Text`/`Label`/`Button`/`Section`/`ContentUnavailableView` literals stay as literals (auto-extracted by `SWIFT_EMIT_LOC_STRINGS = YES`); non-view strings (`accessibilityLabel`, alert bodies) become `String(localized: <key>, table: "Localizable", bundle: .main)`
- App `AppearanceMode.label` returns `String(localized: ..., bundle: .main)` (independent of core per Design Decision 3)
- `app.alanvardy.CheckStitch` catalog keys are the English literals — no key renaming

**Tests**: `ViewRenderTests` (all appearance modes render) stays green; new app-key assertions via `String.en(..., bundle: .main)` for the migrated accessibility/alert strings (happy: resolves; sad: an unknown key returns the key unchanged). Do **not** touch `ContentView.swift:344`'s shadowed `ChecklistWidth`.
**Verify**: `make test-unit` green; `make build` and `make build-mac` compile; spot-check the built app bundle contains the compiled app catalog.

---

## Layer 5: Watch string migration

Migrates the watch target's five literals through its own catalog. Green
proves the watch scheme still compiles and its keys resolve.

**Files**: `CheckStitchWatch/WatchChecklistListView.swift`, `CheckStitchWatch/WatchChecklistDetailView.swift`, `CheckStitchTests/LocalizationTests.swift`

**Key changes**:
- `ContentUnavailableView` description and `Button(sent ? "Sent" : "Create reminders")` etc. converted to catalog-backed lookups; `Text`/`navigationTitle` literals stay auto-extracted
- All lookups use `bundle: .main` (watch target bundle)

**Tests**: watch-key presence assertions against the source-tree catalog (watch is not macOS-hosted, so bundle lookup is source-tree based); existing watch store tests unaffected.
**Verify**: `make watch-build` compiles; `make test-unit` green.

---

## Layer 6: Localized Info.plist metadata

Adds the per-language `InfoPlist.strings` files so usage descriptions and the
app display name localize. Green proves every `.lproj` file parses and carries
its required keys.

**Files**: `CheckStitch/{en,de,es,fr,ja,zh-Hans}.lproj/InfoPlist.strings` (new, 6), `CheckStitchWatch/{en,de,es,fr,ja,zh-Hans}.lproj/InfoPlist.strings` (new, 6), `CheckStitchTests/LocalizationTests.swift`

**Key changes**:
- App files: `NSRemindersFullAccessUsageDescription`, `NSRemindersUsageDescription`, `CFBundleDisplayName = CheckStitch` (en value localized per language; name stays "CheckStitch")
- Watch files: `NSRemindersFullAccessUsageDescription`, `CFBundleDisplayName = CheckStitch`
- `INFOPLIST_KEY_*` build settings remain English (reference pattern); watch's `INFOPLIST_KEY_CFBundleDisplayName` intentionally stays and takes precedence

**Tests**: `infoPlistStringsHaveRequiredKeysPerLanguage` — `PropertyListSerialization` parses each of the 12 files and asserts required keys non-empty (happy: all present; sad: a missing key in one language fails).
**Verify**: `make test-unit` green; `make build`, `make build-mac`, `make watch-build` compile.

---

## Testing Checkpoints

- After Layer 1: `make test-unit` + all three builds pass with the package resource change.
- After Layer 2: catalog completeness / all-six / non-English-differs green.
- After Layer 3: core strings resolve from `Bundle.core`, `AppearanceModeTests` green, `make watch-build` compiles.
- After Layer 4: `make test-unit`, `make build`, `make build-mac` green.
- After Layer 5: `make test-unit`, `make watch-build` green.
- After Layer 6: full gate `bash scripts/test.sh` prints `gate: ok`; manual smoke on a simulator/device set to `de` confirms translated UI copy and display name "CheckStitch".

**Non-horizontal caveat**: generated-Info.plist precedence (`INFOPLIST_KEY_*` vs `.lproj`) cannot be asserted from unit tests — Layer 6's actual effect is only provable by the manual locale smoke at the top of the stack. The testable part (files parse and carry keys) lands in Layer 6 so a failure there is caught before the manual check.