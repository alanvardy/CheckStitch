# Implementation Plan

## Overview

Add a read-only About screen to CheckStitch by mirroring SingleThread's shipped
"About" feature (VAR-651): a bundle-derived, injectable `AppInfo` struct plus two
Core version-format strings, a new `AboutView.swift` in the app target reached
from a new About row in `SettingsView`, and unit suites
(`AppInfoTests`, `AboutViewTests`, `StubBundle`). Two commits, one per layer —
Core first (compiles and tests green on its own), then the app surface.

**Classification check:** recon found no schema, no migration, no persisted
format, no new subsystem/interface, and no design decision. `AppInfo` is a
straight mirror of `SingleThreadCore/.../AppInfo.swift`; `AboutView` mirrors
`SingleThread/AboutView.swift`; the Core/app catalog + test-helper layers
already exist and have an established pattern. MEDIUM holds — no escalation.

### Deviation from `medium.md` (recon finding, resolved here)

`medium.md` says "mirror the SingleThread `SettingsView` About row". SingleThread
uses a local `SettingsLinkLabel` component carrying a caption
("App version, credits, and contact."). **CheckStitch has no `SettingsLinkLabel`;
its settings rows use a plain `Label` inside their own `Section`** (see
`CheckStitch/SettingsView.swift:29-42`, Background row). Per `medium.md`'s own
instruction to mirror *the existing Background row*, the About row is a plain
`Label("About", systemImage: "info.circle")` with **no caption**, so no
"App version, credits, and contact." key is added.

### Recon-confirmed facts the plan relies on

- `CheckStitch/AboutView.swift` does not exist; no `AppInfo`-like type or
  version-string code exists anywhere in the repo (zero grep hits for
  `CFBundleShortVersionString`/`CFBundleVersion`). No overlap.
- `CheckStitch/SettingsSubscreenLayout.swift` already provides
  `settingsSubscreenLayout()` (macOS frame fix, iOS no-op).
- `CheckStitch/SettingsView.swift` already owns its `NavigationStack`
  (`:11`), so `AboutView` is pushed, never presented as a sheet.
- Both catalogs exist: `CheckStitch/Localizable.xcstrings` (34 keys, root of the
  app target) and
  `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`
  (3 keys), both `sourceLanguage: en` with `extractionState: "manual"` entries
  and `stringUnit { state: "translated", value }` per language.
- `CheckStitchTests/LocalizationTestHelpers.swift` supplies `String.en(_:bundle:)`,
  `Bundle.core` (embedded `CheckStitchCore_CheckStitchCore.bundle`) and `Catalogs`;
  `CheckStitchTests/LocalizationFixtures.swift` holds `requiredKeys` and
  `excludedIdentities`.
- `CheckStitchTests/ViewRenderTests.swift` already does `@testable import CheckStitch`
  and constructs `SettingsView(appearanceMode:bindings:backgroundImage:)`.
- No `StubBundle` exists in CheckStitchTests — it is new.

### Commands (from `Makefile` / `scripts/test.sh`)

- Fast loop: `make test-unit` (macOS-hosted, unsigned, no simulator).
- Phase-2 compile check: `make build` (simulator).
- Full gate (run **once** by the parent after both phases commit):
  `bash scripts/test.sh` → prints `gate: ok`.

---

## Phase 1: Core `AppInfo` + Core version strings

Lands the Core layer and its unit suite. Compiles standalone (the new type is
unused by the app yet) and keeps every existing test green.

### Changes

#### 1. New Core type

**File**: `CheckStitchCore/Sources/CheckStitchCore/AppInfo.swift`
**Action**: create

Mirror `SingleThreadCore/Sources/SingleThreadCore/AppInfo.swift` exactly, with
the fallback literal changed to `"CheckStitch"`. The two localized formats
resolve through the package's own catalog via `Bundle.module`.

```swift
import Foundation

/// Bundle-derived app identity — display name, marketing version, and build
/// number — formatted for the About screen. The first runtime `Bundle` read in
/// the codebase, kept injectable so it is unit-testable.
public struct AppInfo: Sendable {
    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Single source of truth for the feedback email address.
    public static let feedbackEmail = "alan@vardy.cc"

    /// `CFBundleShortVersionString` (e.g. "1.0"), nil if absent.
    public var marketingVersion: String? {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// `CFBundleVersion` (e.g. "1"), nil if absent.
    public var buildNumber: String? {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// `CFBundleDisplayName` ?? `CFBundleName` ?? "CheckStitch".
    public var displayName: String {
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "CheckStitch"
    }

    /// "Version 1.0 (1)"; "Version 1.0" when build is nil; "" when marketing is nil.
    public var versionDescription: String {
        guard let marketing = marketingVersion else { return "" }
        if let build = buildNumber {
            return String(
                localized: "Version \(marketing) (\(build))",
                table: "Localizable",
                bundle: .module)
        }
        return String(
            localized: "Version \(marketing)",
            table: "Localizable",
            bundle: .module)
    }

    private let bundle: Bundle
}
```

#### 2. Core string catalog — two version-format keys

**File**: `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`
**Action**: modify

Add both keys to `strings`, each with all six languages (the catalog's
`LocalizationTests.catalogsHaveAllSixLanguages` requires all six). Values copied
verbatim from `SingleThreadCore/.../Localizable.xcstrings` (they are already
shipped, reviewed translations):

```json
"Version %@ (%@)": {
  "extractionState": "manual",
  "localizations": {
    "en":      { "stringUnit": { "state": "translated", "value": "Version %@ (%@)" } },
    "de":      { "stringUnit": { "state": "translated", "value": "Version %1$@ (%2$@)" } },
    "es":      { "stringUnit": { "state": "translated", "value": "Versión %1$@ (%2$@)" } },
    "fr":      { "stringUnit": { "state": "translated", "value": "Version %1$@ (%2$@)" } },
    "ja":      { "stringUnit": { "state": "translated", "value": "バージョン %1$@ (%2$@)" } },
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "版本 %1$@ (%2$@)" } }
  }
},
"Version %@": {
  "extractionState": "manual",
  "localizations": {
    "en":      { "stringUnit": { "state": "translated", "value": "Version %@" } },
    "de":      { "stringUnit": { "state": "translated", "value": "Version %@" } },
    "es":      { "stringUnit": { "state": "translated", "value": "Versión %@" } },
    "fr":      { "stringUnit": { "state": "translated", "value": "Version %@" } },
    "ja":      { "stringUnit": { "state": "translated", "value": "バージョン %@" } },
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "版本 %@" } }
  }
}
```

Keep the file valid JSON with its existing `sourceLanguage` / `version` root keys.

#### 3. Test fixture: stub bundle

**File**: `CheckStitchTests/StubBundle.swift`
**Action**: create

Verbatim from `SingleThreadTests/StubBundle.swift` (the `@unchecked Sendable`
restatement is required — `Bundle` is `@unchecked Sendable`, and Swift 6 with
warnings-as-errors rejects a subclass that does not restate it):

```swift
import Foundation

/// Test fixture: a `Bundle` subclass returning a fixed info dictionary so
/// `AppInfo` can be exercised without the real bundle's Info.plist.
///
/// Must restate `@unchecked Sendable`: `Bundle` is `@unchecked Sendable`, and
/// Swift 6 + warnings-as-errors rejects subclasses that don't restate it.
final class StubBundle: Bundle, @unchecked Sendable {
    init(info: [String: Any]) {
        stubbedInfo = info
        super.init()
    }

    override var infoDictionary: [String: Any]? { stubbedInfo }

    override func object(forInfoDictionaryKey key: String) -> Any? { stubbedInfo[key] }

    private let stubbedInfo: [String: Any]
}
```

#### 4. Test suite: `AppInfoTests`

**File**: `CheckStitchTests/AppInfoTests.swift`
**Action**: create

Mirror `SingleThreadTests/AppInfoTests.swift`, importing `CheckStitchCore` and
using the shared `String.en(_:bundle:)` helper (resolving against `Bundle.core`,
because the hosted test runner cannot use the package-only `.module`). Five
`@Test` functions, behaviour-named, no `test` prefix:

- `readsMarketingVersionBuildNumberAndDisplayName` — happy path; stub with
  `CFBundleShortVersionString`/`CFBundleVersion`/`CFBundleDisplayName`, expects
  `versionDescription == String.en("Version 1.0 (1)", bundle: .core)`.
- `fallsBackWhenIdentityKeysAreAbsent` — sad path; `StubBundle(info: [:])` →
  `marketingVersion == nil`, `buildNumber == nil`,
  `displayName == "CheckStitch"`, `versionDescription.isEmpty`.
- `omitsBuildParentheticalWhenBuildIsAbsent` — marketing only → expects
  `String.en("Version 1.0", bundle: .core)`.
- `emptyVersionWhenMarketingAbsentButBuildPresent` — sad path; build only →
  `versionDescription.isEmpty`.
- `fallsBackToBundleNameWhenDisplayNameAbsent` — only `CFBundleName` →
  `displayName == "CheckStitch"`.

#### 5. Localization fixtures — Core requirements + exclusion

**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

- Extend the `("Core", [...])` entry of `requiredKeys` to
  `["System", "Light", "Dark", "Version %@ (%@)", "Version %@"]` so a dropped
  key fails loudly.
- Add to `excludedIdentities`, with a comment matching the file's style:

```swift
// de/fr "Version" — same spelling as English
ExclusionEntry(catalog: "Core", key: "Version %@"),
```

Without this entry, `LocalizationTests.nonEnglishValuesDifferFromEnglish` fails:
`Version %@` is byte-identical in `de`/`fr`.

### Verification

#### Automated
- [x] `make test-unit` passes (covers the new `AppInfoTests` and all
      `LocalizationTests`, including the six-language and canary checks on the
      two new Core keys).
- [x] `grep -c 'Version %@' CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`
      returns > 0 and the file still parses
      (`python3 -c "import json;json.load(open('CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings'))"`).

#### Manual
- [ ] None — no UI is reachable in this phase; `AppInfo` is exercised entirely by
      the unit suite.

#### Commit
- [x] One commit: `git commit -m "Add Core AppInfo and version strings (VAR-903)"`

---

## Phase 2: About view, Settings row, app strings, UI tests

Lands the app surface. Depends on Phase 1's `AppInfo` and reuses the existing
`settingsSubscreenLayout()` modifier and `NavigationStack`.

### Changes

#### 1. New About view

**File**: `CheckStitch/AboutView.swift`
**Action**: create

Mirror `SingleThread/SingleThread/AboutView.swift`, with `CheckStitchCore`
imported and the preview written in CheckStitch's local style (bare `#Preview`
wrapped in a `NavigationStack`, as in
`CheckStitch/BackgroundSettingsView.swift:89-96` — CheckStitch does not guard
previews with `#if os(iOS)`):

```swift
import CheckStitchCore
import SwiftUI

/// Read-only About screen presenting app identity, author attribution, and a
/// feedback mail link. Pushed from Settings' `NavigationStack`, so it owns its
/// own `.navigationTitle` and never re-presents a sheet.
struct AboutView: View {
    init(
        appInfo: AppInfo = AppInfo(),
        feedbackEmail: String = AppInfo.feedbackEmail) {
        self.appInfo = appInfo
        self.feedbackEmail = feedbackEmail
    }

    var body: some View {
        Form {
            Section {
                Label(appInfo.displayName, systemImage: "checklist")
            }
            Section {
                Text("Copyright 2026 Alan Vardy")
                Text("Made with love by a lone developer")
                Text(appInfo.versionDescription)
            }
            Section {} footer: {
                if let feedbackURL = URL(string: "mailto:\(feedbackEmail)") {
                    Link(feedbackEmail, destination: feedbackURL)
                } else {
                    Text(feedbackEmail)
                }
            }
        }
        .navigationTitle("About")
        .settingsSubscreenLayout()
    }

    private let appInfo: AppInfo
    private let feedbackEmail: String
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
```

#### 2. About row in Settings

**File**: `CheckStitch/SettingsView.swift`
**Action**: modify

Add a sibling `Section` immediately after the Background `Section`
(`:29-42`), inside the same `Form`, mirroring the existing plain-`Label` row
style (no caption — see the deviation note above):

```swift
Section {
    NavigationLink {
        AboutView()
    } label: {
        Label("About", systemImage: "info.circle")
    }
    .accessibilityIdentifier("settingsAboutRow")
}
```

No new member variables, no change to the toolbar, `navigationTitle`, or the
staged `SettingsBindings`.

#### 3. App string catalog — three About keys

**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Add three `extractionState: "manual"` entries, each with all six languages.
Values for the first two are copied verbatim from
`SingleThread/Resources/Localizable.xcstrings` (shipped translations); the third
is newly authored for CheckStitch:

| key | en | de | es | fr | ja | zh-Hans |
| --- | --- | --- | --- | --- | --- | --- |
| `About` | `About` | `Über` | `Acerca de` | `À propos` | `このアプリについて` | `关于` |
| `Copyright 2026 Alan Vardy` | `Copyright 2026 Alan Vardy` | `Urheberrecht 2026 Alan Vardy` | `Derechos de autor 2026 Alan Vardy` | `Droits d'auteur 2026 Alan Vardy` | `著作権 2026 Alan Vardy` | `版权所有 2026 Alan Vardy` |
| `Made with love by a lone developer` | `Made with love by a lone developer` | `Mit Liebe gemacht von einem unabhängigen Entwickler` | `Hecho con amor por un desarrollador independiente` | `Fait avec amour par un développeur indépendant` | `ひとりの開発者が愛情を込めて作っています` | `由一位独立开发者倾心打造` |

JSON entry shape (repeat per key, matching every existing entry):

```json
"About": {
  "extractionState": "manual",
  "localizations": {
    "en": { "stringUnit": { "state": "translated", "value": "About" } },
    "de": { "stringUnit": { "state": "translated", "value": "Über" } },
    "es": { "stringUnit": { "state": "translated", "value": "Acerca de" } },
    "fr": { "stringUnit": { "state": "translated", "value": "À propos" } },
    "ja": { "stringUnit": { "state": "translated", "value": "このアプリについて" } },
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "关于" } }
  }
}
```

All three keys differ from English in every non-English language, so **no new
`excludedIdentities` entry is needed**.

#### 4. Test suite: `AboutViewTests`

**File**: `CheckStitchTests/AboutViewTests.swift`
**Action**: create

Mirror `SingleThreadTests/AboutViewTests.swift`, adapted to CheckStitch's
imports (`@testable import CheckStitch` + `import CheckStitchCore`, plus
`SwiftUI`/`Testing`), `@MainActor`, and the CheckStitch stub values:

```swift
@testable import CheckStitch
import CheckStitchCore
import SwiftUI
import Testing

@MainActor
struct AboutViewTests {
    @Test
    func aboutViewRendersAttributionAndIdentity() {
        let view = AboutView(appInfo: stubAppInfo())
        let bodyDescription = String(describing: view.body)
        for expected in [
            "Copyright 2026 Alan Vardy",
            "Made with love by a lone developer",
            "Version 1.0 (1)",
            "CheckStitch",
            "alan@vardy.cc",
        ] {
            #expect(bodyDescription.contains(expected))
        }
        #if os(macOS)
            #expect(bodyDescription.contains("SettingsSubscreenLayout"))
        #endif
    }

    @Test
    func aboutViewRendersWithoutCrashingWhenVersionIsNil() {
        let view = AboutView(appInfo: AppInfo(bundle: StubBundle(info: [:])))
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("Copyright 2026 Alan Vardy"))
        #expect(bodyDescription.contains("Made with love by a lone developer"))
        // Display name falls back to the "CheckStitch" literal.
        #expect(bodyDescription.contains("CheckStitch"))
    }

    private func stubAppInfo() -> AppInfo {
        AppInfo(bundle: StubBundle(info: [
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleDisplayName": "CheckStitch",
        ]))
    }
}
```

The macOS-only `SettingsSubscreenLayout` assertion is the canary that
`settingsSubscreenLayout()` was actually applied (on iOS it is a no-op, so
`String(describing:)` cannot observe it there).

#### 5. Settings row coverage in the render suite

**File**: `CheckStitchTests/ViewRenderTests.swift`
**Action**: modify

Add one `@Test` to the existing `@MainActor struct ViewRenderTests`, reusing the
same `SettingsView` construction already used in `settingsViewListsAllAppearanceModes`:

```swift
@Test
func settingsViewExposesAboutRow() {
    let view = SettingsView(
        appearanceMode: .constant(.system),
        bindings: SettingsBindings(),
        backgroundImage: BackgroundImageStore())
    let bodyDescription = String(describing: view.body)
    #expect(bodyDescription.contains("About"))
    #expect(bodyDescription.contains("Background"))
}
```

#### 6. Localization fixtures — App required keys

**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Insert the three new keys into the `("App", [...])` list of `requiredKeys`,
keeping the list's existing ordering (`About` alongside the other `A` keys,
`Copyright 2026 Alan Vardy` after the `Checklist…`/`Choose…`/`Create…` entries,
`Made with love by a lone developer` after `Light`).

### Verification

#### Automated
- [ ] `make test-unit` passes (new `AboutViewTests`, extended `ViewRenderTests`,
      and `LocalizationTests` over the three new App keys).
- [ ] `make build` succeeds (simulator compile of the app target with the new
      view and row).

#### Manual
- [ ] `make run`, then: open Settings (gear) → confirm an **About** row with an
      `info.circle` glyph sits under the Background row; tapping it pushes a Form
      showing the display name, "Copyright 2026 Alan Vardy", the developer credit,
      the "Version x (y)" string, and an `alan@vardy.cc` mailto link.
- [ ] Change the simulator/app language to German and confirm the About row and
      screen render German strings (no raw keys).
- [ ] Confirm the About screen fills and top-aligns on macOS
      (`make build-mac-signed`) rather than vertically centring.

#### Commit
- [ ] One commit: `git commit -m "Add About screen and Settings row (VAR-903)"`

---

## Final gate (parent, after both phases)

- [ ] `bash scripts/test.sh` prints `gate: ok` (simulator build → `make test`
      incl. the UI smoke → `make build-mac` → `make watch-build` → shell tests →
      shellcheck). Run once, after both phase commits.
- [ ] Open the PR into `main` (never push directly to `main`); merge only with
      `gh pr merge <n> --rebase --delete-branch`.

## Out of scope

No changes to `CheckStitchWatch`, `CheckStitchUITests`, `ContentView`,
`AppGroup.entitlements`, the `Makefile`, `scripts/`, or any existing
Core/app string beyond the five keys added above. No refactoring of
`SettingsView`, no `SettingsLinkLabel` introduction. No new dependencies.
