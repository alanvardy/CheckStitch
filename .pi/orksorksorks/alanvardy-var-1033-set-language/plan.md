# Implementation Plan

## Overview

Add a **Language** picker to Settings → Interface that flips the whole app's UI
language live (no relaunch) on iOS and macOS, persists the choice in
`UserDefaults.standard["appLanguage"]`, and delivers it to the paired watch over
the existing `ChecklistSyncMessage` seam. The mechanism is SwiftUI
`\.locale` + an `@Observable AppLocaleState` (the SingleThread pattern); eager
`String(localized:)` sites become `LocalizedStringResource`, resolved with
`resolved(in:)`.

This plan follows `structure.md`'s four phases in order. **One deliberate
addition** (flagged in Phase 4): the planning grep inventory found two more
eager, user-visible strings that are not `String(localized:)` sites —
`ChecklistItemPriority.label` (rendered in the item editor *and* used as an
accessibility label) and `ReminderDestinationError.errorDescription` — plus
`ItemRow.displayTitle`'s `"Item"` fallback. Leaving them would leave English
residue, which Phase 4's stated goal forbids, so they are converted and their
keys added to the catalogs.

Two readings were resolved during planning (both consistent with `structure.md`):

1. **Unknown wire language** → rejected at decode (`ChecklistSyncMessage(userInfo:)`
   returns `nil` when `AppLanguage(rawValue:)` fails) *and* the store guards with
   `guard let … else { break }` so a hand-built garbage message leaves the current
   choice alone. This satisfies both "a malformed/unknown language string decodes
   to a rejected message" and "garbage value yields no change". The persisted
   path (`AppLanguagePreference`) still degrades unknown → `.system`.
2. **Phone→watch delivery** must use `transferUserInfo`, not
   `updateApplicationContext` (which `sendContext` already owns and would
   overwrite). `WatchSyncAdapter` currently has **no**
   `session(_:didReceiveUserInfo:)`, so Phase 3 adds it (the structure's
   "`CheckStitch/WatchSyncAdapter.swift` if the branch needs it").

There is no schema migration.

---

## Phase 1: Walking skeleton — pick a language in Settings and watch the UI flip, live

### Changes

#### 1. Core: `AppLanguage`

**File**: `CheckStitchCore/Sources/CheckStitchCore/AppLanguage.swift`
**Action**: create

```swift
import Foundation

/// User-selectable app language. `.system` preserves the device locale (today's
/// behaviour); the other cases pin the app to one of the six shipped catalogs.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"

    /// Locale for SwiftUI's `\.locale` and explicit lookups. `.system` follows
    /// the device; the six pinned cases map to their catalog language.
    public var locale: Locale {
        self == .system ? .current : Locale(identifier: rawValue)
    }

    /// Reads the persisted language, defaulting to `.system` for a missing or
    /// unknown value. Mirrors `AppearanceMode.load(from:)`.
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        AppLanguagePreference(defaults: defaults).load()
    }
}
```

`CaseIterable` declaration order **is** the picker order and must stay
`system, english, german, spanish, french, japanese, simplifiedChinese`.

#### 2. Core: `AppLanguagePreference`

**File**: `CheckStitchCore/Sources/CheckStitchCore/AppLanguagePreference.swift`
**Action**: create

```swift
import Foundation

/// Persists the app-language raw string in `UserDefaults.standard`. An absent or
/// unrecognized value resolves to `.system`, preserving today's behaviour.
public struct AppLanguagePreference {
    public init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public static let defaultsKey = "appLanguage"

    /// Validated raw value; missing/unrecognized → `AppLanguage.system.rawValue`.
    public var rawValue: String {
        guard let raw = defaults.object(forKey: key) as? String,
              AppLanguage.allCases.contains(where: { $0.rawValue == raw })
        else { return AppLanguage.system.rawValue }
        return raw
    }

    public func load() -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? .system
    }

    public func setRawValue(_ raw: String) {
        defaults.set(raw, forKey: key)
    }

    private let defaults: UserDefaults
    private let key: String
}
```

Deliberately `.standard`, not `AppGroup.defaults` (design decision 4) — the
watch is a separate container reached by sync, not shared defaults.

#### 3. Core: `AppLocaleState`

**File**: `CheckStitchCore/Sources/CheckStitchCore/AppLocaleState.swift`
**Action**: create

```swift
import Foundation
import Observation

/// Process-wide holder of the chosen language. One instance per process,
/// injected at the app and watch roots into `\.locale`; tests construct their
/// own with an isolated `UserDefaults` suite.
@MainActor
@Observable
public final class AppLocaleState {
    public init(language: AppLanguage? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.language = language ?? AppLanguagePreference(defaults: defaults).load()
    }

    /// Shared instance used by the app and watch roots and by the Settings picker.
    public static let current = AppLocaleState()

    /// Locale for non-View consumers (intents, `LocalizedError`s, `AppInfo`).
    /// A plain store read, no actor hop, so it never registers observation.
    public nonisolated static var storedEffectiveLocale: Locale {
        AppLanguagePreference().load().locale
    }

    public private(set) var language: AppLanguage

    /// Locale handed to SwiftUI's `\.locale` and to `resolved(in:)`.
    public var effectiveLocale: Locale { language.locale }

    /// Persists and publishes the choice. Later slices must never read
    /// `AppLanguagePreference` directly — only this holder.
    public func set(_ language: AppLanguage) {
        AppLanguagePreference(defaults: defaults).setRawValue(language.rawValue)
        self.language = language
    }

    private let defaults: UserDefaults
}
```

#### 4. App: picker titles

**File**: `CheckStitch/AppLanguage+Presentation.swift`
**Action**: create

```swift
import CheckStitchCore
import SwiftUI

/// Picker rows for the Language setting. The six endonyms render verbatim in
/// every language (an absent catalog key resolves to its own text, pinned by
/// `LocalizationTests.unknownKeyFallsBackToItsOwnText`); only `System` is a
/// catalog key.
extension AppLanguage {
    var title: LocalizedStringResource {
        switch self {
        case .system: LocalizedStringResource("System", table: "Localizable", bundle: .main)
        case .english: LocalizedStringResource("English", table: "Localizable", bundle: .main)
        case .german: LocalizedStringResource("Deutsch", table: "Localizable", bundle: .main)
        case .spanish: LocalizedStringResource("Español", table: "Localizable", bundle: .main)
        case .french: LocalizedStringResource("Français", table: "Localizable", bundle: .main)
        case .japanese: LocalizedStringResource("日本語", table: "Localizable", bundle: .main)
        case .simplifiedChinese: LocalizedStringResource("简体中文", table: "Localizable", bundle: .main)
        }
    }
}
```

#### 5. App: `SettingsView` gains the Interface section

**File**: `CheckStitch/SettingsView.swift`
**Action**: modify

Add `import CheckStitchCore` at the top, a new binding, and the new first
section. Exact edits:

```swift
struct SettingsView: View {
    @Binding var appearanceMode: AppearanceMode
    @Binding var appLanguage: AppLanguage
    @Bindable var bindings: SettingsBindings
    // … rest unchanged
```

```swift
            Form {
                Section("Interface") {
                    Picker(selection: $appLanguage) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(language.title).tag(language)
                        }
                    } label: {
                        Text("Language")
                    }
                    .accessibilityIdentifier("languagePicker")
                }

                Section {
                    Picker(selection: $appearanceMode) {
                    // … existing Appearance section unchanged
```

Both `#Preview` blocks (lines 92-105) gain `appLanguage: .constant(.system)`.

#### 6. App: `ContentView` write-through binding

**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Add the binding next to `settingsSheetWritebacks(_:)` (≈line 540):

```swift
    /// Write-through language binding: reads the live holder (so a value that
    /// arrives over sync or lands from another scene updates the picker) and
    /// persists immediately on change — no staging bag (design decision 9).
    var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLocaleState.current.language },
            set: { AppLocaleState.current.set($0) })
    }
```

and pass it in (the sheet body already runs in this view's observation scope,
so a `set` re-renders it):

```swift
        SettingsView(
            appearanceMode: $appearanceMode,
            appLanguage: appLanguageBinding,
            bindings: bag,
            backgroundImage: backgroundImage,
            onExport: { requestDataAction(.export) },
            onImport: { requestDataAction(.importChecklists) })
```

#### 7. App: inject `\.locale` at both roots

**File**: `CheckStitch/MyApp.swift`
**Action**: modify

Add `.environment(\.locale, AppLocaleState.current.effectiveLocale)` **inside**
each `WindowGroup` content closure so it is read during view construction, not
stored (a stored read would freeze the language). macOS branch:

```swift
            WindowGroup {
                ContentView()
                    .environment(store)
                    .environment(syncService)
                    .environment(\.locale, AppLocaleState.current.effectiveLocale)
                    .task { await syncService.syncOnLaunch() }
            }
```

iOS branch: same line after `.environment(syncService)` (before the iOS-only
`.task` block).

#### 8. Catalog: two new App keys

**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Add two entries (shape copied from the existing `"About"` entry: `"extractionState": "manual"` + `localizations` for all six languages):

| key | en | de | es | fr | ja | zh-Hans |
|---|---|---|---|---|---|---|
| `Interface` | Interface | Oberfläche | Interfaz | Interface | インターフェース | 界面 |
| `Language` | Language | Sprache | Idioma | Langue | 言語 | 语言 |

French `Interface` is byte-identical to English, so the canary needs an
exclusion (see next change).

#### 9. Fixtures

**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

- `requiredKeys` App list gains `"Interface"` and `"Language"`.
- `excludedIdentities` gains:

```swift
        // fr "Interface" — same spelling as English
        ExclusionEntry(catalog: "App", key: "Interface"),
```

#### 10. Tests

**File**: `CheckStitchTests/AppLanguageTests.swift` **Action**: create

```swift
@testable import CheckStitchCore
import Foundation
import Testing

struct AppLanguageTests {
    @Test(arguments: [
        (AppLanguage.english, "en"),
        (.german, "de"),
        (.spanish, "es"),
        (.french, "fr"),
        (.japanese, "ja"),
        (.simplifiedChinese, "zh-Hans"),
    ] as [(AppLanguage, String)])
    func everyCaseMapsToItsCatalogLocale(_ language: AppLanguage, _ identifier: String) {
        #expect(language.locale == Locale(identifier: identifier))
    }

    @Test
    func systemFollowsTheProcessLocale() {
        #expect(AppLanguage.system.locale == Locale.current)
    }

    @Test
    func everyCaseIteratedLanguageIsOneOfTheSixCatalogs() {
        let pinned = Set(AppLanguage.allCases.map(\.rawValue)).subtracting(["system"])
        #expect(pinned == ["en", "de", "es", "fr", "ja", "zh-Hans"])
    }
}
```

**File**: `CheckStitchTests/AppLanguagePreferenceTests.swift` **Action**: create

```swift
@testable import CheckStitchCore
import Foundation
import Testing

struct AppLanguagePreferenceTests {
    @Test
    func roundTripPersists() {
        let defaults = makeIsolatedDefaults()
        AppLanguagePreference(defaults: defaults).setRawValue(AppLanguage.japanese.rawValue)
        #expect(AppLanguagePreference(defaults: defaults).rawValue == "ja")
        #expect(AppLanguage.load(from: defaults) == .japanese)
    }

    @Test
    func unknownStoredValueFallsBackToSystem() {
        let defaults = makeIsolatedDefaults()
        AppLanguagePreference(defaults: defaults).setRawValue("klingon")
        #expect(AppLanguagePreference(defaults: defaults).rawValue == "system")
        #expect(AppLanguage.load(from: defaults) == .system)
    }

    @Test
    func absentStoredValueFallsBackToSystem() {
        #expect(AppLanguagePreference(defaults: makeIsolatedDefaults()).rawValue == "system")
    }
}
```

**File**: `CheckStitchTests/ViewRenderTests.swift` **Action**: modify

- All three `SettingsView(...)` constructions (lines ≈36-40, ≈47-51, ≈57-61)
  gain `appLanguage: .constant(.system)`.
- `settingsViewListsAllAppearanceModes`: the title pin becomes key-based:
  `#expect(CheckStitch.AppearanceMode.allCases.map(\.title.key) == ["System", "Light", "Dark"])`.

### Verification

#### Automated
- [x] `make test-unit` passes (also compiles the app target — the compiler is the oracle for the `Label`/`Text`/`Binding` shapes)
- [x] `#expect` suite names above exist and run: `make test-unit` output lists `AppLanguageTests`, `AppLanguagePreferenceTests`
- [x] `LocalizationTests` still green with `Interface`/`Language` required

#### Manual
- [ ] `make run` on this worktree's simulator (`.simulator_id` = `D6D3CD6F-F7EF-4265-8E93-389ED04891EB`)
- [ ] Settings shows **Interface → Language** as the first section; options read System / English / Deutsch / Español / Français / 日本語 / 简体中文
- [ ] Select **Deutsch** and, *without relaunching*, "Settings", "Interface", "Language", "Appearance" and "Done" re-render in German
- [ ] Force-quit and relaunch: the app opens in German and the picker still shows Deutsch
- [ ] Select **System** and confirm the app returns to the device language
- [ ] This is the **only** evidence for the live flip (the hosted runner pins the process locale); do not proceed to Phase 2 until it is seen

---

## Phase 2: The whole app follows the choice — no mixed-language UI

### Changes

#### 1. Core: explicit-locale resolution seam

**File**: `CheckStitchCore/Sources/CheckStitchCore/LocalizedString+Shared.swift`
**Action**: create

```swift
import Foundation

// MARK: - Explicit-locale resolution

public extension LocalizedStringResource {
    /// Resolves this resource against an explicit locale. Views get this for
    /// free from `\.locale`; non-View callers use this or
    /// `resolvedInAppLanguage()`.
    ///
    /// Setting `locale` *before* evaluating is the seam: the explicit
    /// `String(localized:…, locale:)` parameter form does not pin the language
    /// on this toolchain (spike NO-GO), while this form does.
    func resolved(in locale: Locale) -> String {
        var resource = self
        resource.locale = locale
        return String(localized: resource)
    }

    /// Resolves against the persisted app-language preference.
    func resolvedInAppLanguage() -> String {
        resolved(in: AppLocaleState.storedEffectiveLocale)
    }
}
```

#### 2. Core: `SharedStrings` returns resources

**File**: `CheckStitchCore/Sources/CheckStitchCore/SharedStrings.swift`
**Action**: modify

```swift
public enum SharedStrings {
    public static var system: LocalizedStringResource {
        LocalizedStringResource("System", table: "Localizable", bundle: .module)
    }

    public static var light: LocalizedStringResource {
        LocalizedStringResource("Light", table: "Localizable", bundle: .module)
    }

    public static var dark: LocalizedStringResource {
        LocalizedStringResource("Dark", table: "Localizable", bundle: .module)
    }
}
```

#### 3. Core: `AppearanceMode.title`

**File**: `CheckStitchCore/Sources/CheckStitchCore/AppearanceMode.swift`
**Action**: modify

```swift
    /// Human-readable label shown in the appearance picker. A resource, so
    /// SwiftUI re-resolves it against `\.locale` on a live language switch.
    public var title: LocalizedStringResource {
        switch self {
        case .system: SharedStrings.system
        case .light: SharedStrings.light
        case .dark: SharedStrings.dark
        }
    }
```

#### 4. Core: `AppInfo` resolves eagerly against the app language

**File**: `CheckStitchCore/Sources/CheckStitchCore/AppInfo.swift`
**Action**: modify

`versionDescription` is a non-View `String`, so it resolves through the seam:

```swift
    /// "Version 1.0 (1)"; "Version 1.0" when build is nil; "" when marketing is nil.
    public var versionDescription: String {
        guard let marketing = marketingVersion else { return "" }
        if let build = buildNumber {
            return LocalizedStringResource(
                "Version \(marketing) (\(build))", table: "Localizable", bundle: .module)
                .resolvedInAppLanguage()
        }
        return LocalizedStringResource(
            "Version \(marketing)", table: "Localizable", bundle: .module)
            .resolvedInAppLanguage()
    }
```

#### 5. App: `AppearanceMode.title` returns a resource

**File**: `CheckStitch/AppearanceMode.swift`
**Action**: modify

```swift
    /// Human-readable label shown in the appearance picker.
    var title: LocalizedStringResource {
        switch self {
        case .system: LocalizedStringResource("System", table: "Localizable", bundle: .main)
        case .light: LocalizedStringResource("Light", table: "Localizable", bundle: .main)
        case .dark: LocalizedStringResource("Dark", table: "Localizable", bundle: .main)
        }
    }
```

`SettingsView`'s `Label(mode.title, systemImage:)` is unchanged — `Label` takes a
`LocalizedStringResource` and resolves it against `\.locale`.

#### 6. App: `BackgroundSettingsView` credit

**File**: `CheckStitch/BackgroundSettingsView.swift`
**Action**: modify

Replace the eager `let credit = String(localized:…)` (≈line 68) with:

```swift
                if let photographer = backgroundImage.photographer {
                    let credit = LocalizedStringResource(
                        "Photo by \(photographer) on Unsplash", table: "Localizable", bundle: .main)
                    if let url = backgroundImage.photographerURL {
                        Link(destination: url) { Text(credit) }
                    } else {
                        Text(credit)
                    }
                }
```

#### 7. App: `DueDateLabel` returns a resource

**File**: `CheckStitch/DueDateLabel.swift`
**Action**: modify

```swift
enum DueDateLabel {
    /// `nil` renders as the empty string; every offset renders a non-empty
    /// phrase, never a bare day count. Returned as a resource so SwiftUI
    /// re-resolves it against the environment locale on a language switch.
    static func resource(for relativeDate: Int?) -> LocalizedStringResource {
        guard let relativeDate else {
            return LocalizedStringResource("", table: "Localizable", bundle: .main)
        }
        switch relativeDate {
        case 0:
            return LocalizedStringResource("Today", table: "Localizable", bundle: .main)
        case 1:
            return LocalizedStringResource("Tomorrow", table: "Localizable", bundle: .main)
        case -1:
            return LocalizedStringResource("Yesterday", table: "Localizable", bundle: .main)
        case 2...:
            return LocalizedStringResource("In \(relativeDate) days", table: "Localizable", bundle: .main)
        default:
            return LocalizedStringResource("\(-relativeDate) days ago", table: "Localizable", bundle: .main)
        }
    }
}
```

`LocalizedStringResource` interpolation of an `Int` produces the existing
catalog keys `In %lld days` / `%lld days ago` — the catalogs are untouched.

#### 8. App: `ChecklistDetailView` due-date call site

**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

```swift
                    Text(DueDateLabel.resource(for: relativeDate))
```

#### 9. Tests

**File**: `CheckStitchTests/LocalizedStringResolutionTests.swift` **Action**: create

```swift
@testable import CheckStitchCore
import Foundation
import Testing

/// Pins the eager-resolution seam (`resolved(in:)`) that every non-View string
/// site depends on: `resource.locale` is set *before* `String(localized:)`.
struct LocalizedStringResolutionTests {
    @Test
    func coreResourcesResolveInAnExplicitLocale() {
        #expect(SharedStrings.dark.resolved(in: Locale(identifier: "de")) == "Dunkel")
        #expect(SharedStrings.dark.resolved(in: Locale(identifier: "en")) == "Dark")
    }

    @Test
    func appCatalogResourcesResolveInAnExplicitLocale() throws {
        // Expected value comes from the *compiled* de table (the technique the
        // localization suites already use), so no translation is hard-coded.
        let settings = LocalizedStringResource("Settings", table: "Localizable", bundle: .main)
        let german = try #require(compiledGermanTable()["Settings"])
        #expect(settings.resolved(in: Locale(identifier: "de")) == german)
        #expect(settings.resolved(in: Locale(identifier: "de")) != settings.resolved(in: Locale(identifier: "en")))
    }

    @Test
    func unknownKeyFallsBackToItsOwnText() {
        #expect(LocalizedStringResource("NoSuchKey", table: "Localizable", bundle: .main)
            .resolved(in: Locale(identifier: "de")) == "NoSuchKey")
    }

    private func compiledGermanTable() throws -> [String: String] {
        let url = try #require(Bundle.main.url(
            forResource: "Localizable", withExtension: "strings", localization: "de"))
        return try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), format: nil) as? [String: String])
    }
}
```

If `appCatalogResourcesResolveInAnExplicitLocale` fails on the hosted runner
while `coreResourcesResolveInAnExplicitLocale` passes, that is a real finding
about the seam (not a test-environment artefact) — stop and report it rather
than weakening the test.

**File**: `CheckStitchTests/AppearanceModeTests.swift` **Action**: modify

```swift
    func titlesResolveThroughTheCoreCatalog(_ mode: AppearanceMode, _ key: String) {
        #expect(mode.title.key == key)
        #expect(mode.title.resolved(in: Locale(identifier: "en"))
            == String(localized: String.LocalizationValue(key), table: "Localizable", bundle: .core))
    }
```

**File**: `CheckStitchTests/ChecklistDetailViewTests.swift` **Action**: modify

Rename the four `DueDateLabel.text(for:)` call sites (lines 83, 90, 92, 99, 100)
to `DueDateLabel.resource(for:)` and resolve them for the assertion:

```swift
    @Test
    func missingDateRendersAsBlank() {
        #expect(DueDateLabel.resource(for: nil).resolved(in: Locale(identifier: "en")).isEmpty)
    }

    @Test(arguments: [0, 1, -1, 3, -3, 12] as [Int])
    func everyOffsetRendersItsOwnPhrase(_ offset: Int) {
        let label = DueDateLabel.resource(for: offset).resolved(in: Locale(identifier: "en"))
        #expect(!label.isEmpty)
        #expect(label != DueDateLabel.resource(for: offset + 2).resolved(in: Locale(identifier: "en")))
    }

    @Test
    func futureAndPastPhrasesCarryTheirDayCount() {
        #expect(DueDateLabel.resource(for: 3).resolved(in: Locale(identifier: "en")).contains("3"))
        #expect(DueDateLabel.resource(for: -3).resolved(in: Locale(identifier: "en")).contains("3"))
    }
```

### Verification

#### Automated
- [x] `make test-unit` passes
- [x] `LocalizationTests` unchanged and green (no catalog keys touched this phase)
- [x] `LocalizedStringResolutionTests` green (the `de` resolution is the phase's key assertion)
- [x] No `String(localized:` remains in the phase's files: `rg -n "String\(localized" CheckStitchCore/Sources/CheckStitchCore/SharedStrings.swift CheckStitchCore/Sources/CheckStitchCore/AppearanceMode.swift CheckStitchCore/Sources/CheckStitchCore/AppInfo.swift CheckStitch/AppearanceMode.swift CheckStitch/BackgroundSettingsView.swift CheckStitch/DueDateLabel.swift` prints nothing

#### Manual
- [ ] `make run`; switch to Deutsch and confirm **live, without relaunch**: appearance picker rows read System/Hell/Dunkel, the Background footer credit is German, due-date labels on a checklist detail row are German, and the About footer version line is unchanged in shape
- [ ] No English residue on the Settings sheet or a checklist screen after the switch
- [ ] Switch to 日本語 and confirm the same screens follow with no relaunch

---

## Phase 3: The watch renders in the phone's language

### Changes

#### 1. Core: new sync message case

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify

```swift
public enum ChecklistSyncKey {
    public static let context = "checklists"
    public static let runChecklist = "runChecklist"
    public static let requestChecklists = "requestChecklists"
    public static let language = "language"
}
```

```swift
public enum ChecklistSyncMessage: Equatable, Sendable {
    /// Phone → watch, via `updateApplicationContext` (latest state wins).
    case context(Data)
    /// Watch → phone, via `transferUserInfo` (queued command).
    case runChecklist(UUID)
    /// Watch → phone, via `transferUserInfo` (cold launch re-push request).
    case requestChecklists
    /// Phone → watch, via `transferUserInfo`: the app-language raw value.
    case language(String)

    public init?(userInfo: [String: Any]) {
        if let data = userInfo[ChecklistSyncKey.context] as? Data {
            self = .context(data)
        } else if let raw = userInfo[ChecklistSyncKey.runChecklist] as? String,
                  let id = UUID(uuidString: raw) {
            self = .runChecklist(id)
        } else if userInfo[ChecklistSyncKey.requestChecklists] as? Bool == true {
            self = .requestChecklists
        } else if let raw = userInfo[ChecklistSyncKey.language] as? String,
                  AppLanguage(rawValue: raw) != nil {
            // A malformed or unknown language string is a rejected message,
            // never a crash.
            self = .language(raw)
        } else {
            return nil
        }
    }

    public var userInfo: [String: Any] {
        switch self {
        // … existing cases unchanged
        case .language(let raw):
            [ChecklistSyncKey.language: raw]
        }
    }
}
```

#### 2. Core: `WatchChecklistStore` applies and persists the language

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify

```swift
@MainActor
@Observable
public final class WatchChecklistStore {
    /// `locale` is injectable so tests use an isolated `UserDefaults` suite;
    /// production gets the process-wide holder.
    public init(transport: ChecklistSyncTransport, locale: AppLocaleState? = nil) {
        self.transport = transport
        self.locale = locale ?? .current
    }
```

`receive(_:)` gains a case:

```swift
        case .language(let raw):
            // Unknown values never clobber the persisted choice; a corrupted
            // *stored* value is handled by AppLanguagePreference (→ .system).
            guard let language = AppLanguage(rawValue: raw) else { break }
            locale.set(language)
        case .runChecklist, .requestChecklists:
            break // phone-only directions
```

and the stored property:

```swift
    private let locale: AppLocaleState
```

The received choice is persisted by `AppLocaleState.set` into the watch's own
`UserDefaults.standard`, so a cold launch with the phone absent keeps it. No new
`start()` behaviour is needed: the phone re-pushes on activation and on
`.requestChecklists`.

#### 3. Core: coordinator pushes the language

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift`
**Action**: modify

```swift
    public init(
        transport: ChecklistSyncTransport,
        snapshot: @escaping () -> [Checklist],
        createReminders: @escaping (Checklist) async -> Void,
        language: @escaping @MainActor () -> AppLanguage
    ) {
        self.transport = transport
        self.snapshot = snapshot
        self.createReminders = createReminders
        self.language = language
    }

    public func start() {
        transport.onMessage = { [weak self] in self?.handle($0) }
        // `activate()` is asynchronous, so the pushes below are dropped on a cold
        // start; `onActivated` is what actually seeds the watch.
        transport.onActivated = { [weak self] in
            self?.pushContext()
            self?.pushLanguage()
        }
        transport.activate()
        pushContext()
        pushLanguage()
    }
```

In `handle(_:)`:

```swift
        case .requestChecklists:
            pushContext()
            pushLanguage()
        case .runChecklist(let id):
            // … unchanged
        case .context, .language:
            break // watch-only directions
```

```swift
    private func pushLanguage() {
        transport.sendUserInfo(.language(language().rawValue))
    }
```

plus `private let language: @MainActor () -> AppLanguage`.

Language travels on the `transferUserInfo` channel, **not** inside
`updateApplicationContext` — `sendContext` owns that dictionary and would
overwrite a sibling key.

#### 4. App: pass the current language to the coordinator

**File**: `CheckStitch/MyApp.swift`
**Action**: modify

```swift
                                let coordinator = ChecklistSyncCoordinator(
                                    transport: PhoneSyncAdapter(),
                                    snapshot: { store.checklists },
                                    createReminders: { await ChecklistReminders.create(from: $0) },
                                    language: { AppLocaleState.current.language })
```

#### 5. Watch: receive `transferUserInfo`

**File**: `CheckStitchWatch/WatchSyncAdapter.swift`
**Action**: modify

The adapter has no `didReceiveUserInfo` today, so a phone `sendUserInfo` would
never arrive. Add, mirroring `PhoneSyncAdapter`:

```swift
    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let message = ChecklistSyncMessage(userInfo: userInfo) else { return }
        Task { @MainActor [weak self] in self?.onMessage?(message) }
    }
```

#### 6. Watch: root locale

**File**: `CheckStitchWatch/CheckStitchWatchApp.swift`
**Action**: modify

```swift
    var body: some Scene {
        WindowGroup {
            WatchChecklistListView()
                .environment(store)
                .environment(\.locale, AppLocaleState.current.effectiveLocale)
        }
    }
```

`AppLocaleState.current` is read inside `body`, so the `@Observable` mutation
from `WatchChecklistStore.receive` re-renders the watch UI live.

#### 7. Tests

**File**: `CheckStitchTests/AppLanguageSyncTests.swift` **Action**: create

```swift
@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct AppLanguageSyncTests {
    @Test
    func languageRoundTripsThroughUserInfo() {
        let message = ChecklistSyncMessage.language("de")
        #expect(ChecklistSyncMessage(userInfo: message.userInfo) == message)
    }

    @Test
    func unknownLanguageStringIsRejectedNotCrashed() {
        #expect(ChecklistSyncMessage(userInfo: [ChecklistSyncKey.language: "xx"]) == nil)
        #expect(ChecklistSyncMessage(userInfo: [ChecklistSyncKey.language: 42]) == nil)
    }

    @Test
    func receivedLanguageAppliesAndPersists() {
        let defaults = makeIsolatedDefaults()
        let transport = FakeChecklistSyncTransport()
        let locale = AppLocaleState(language: .english, defaults: defaults)
        let store = WatchChecklistStore(transport: transport, locale: locale)
        store.start()

        transport.deliver(.language("ja"))

        #expect(locale.language == .japanese)
        #expect(AppLanguage.load(from: defaults) == .japanese)
    }

    @Test
    func persistedLanguageAppliesBeforeAnyMessage() {
        let defaults = makeIsolatedDefaults()
        AppLanguagePreference(defaults: defaults).setRawValue("ja")
        #expect(AppLanguagePreference(defaults: defaults).load() == .japanese)
    }

    @Test
    func garbageLanguageLeavesTheCurrentChoiceAlone() {
        let transport = FakeChecklistSyncTransport()
        let locale = AppLocaleState(language: .japanese, defaults: makeIsolatedDefaults())
        let store = WatchChecklistStore(transport: transport, locale: locale)
        store.start()

        transport.deliver(.language("xx"))

        #expect(locale.language == .japanese)
    }

    @Test
    func languageMessageDoesNotDisturbTheChecklists() throws {
        let transport = FakeChecklistSyncTransport()
        let locale = AppLocaleState(language: .english, defaults: makeIsolatedDefaults())
        let store = WatchChecklistStore(transport: transport, locale: locale)
        store.start()
        let expected = [Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")])]
        transport.deliver(.context(try ChecklistCodec.encode(ChecklistEnvelope(
            version: ChecklistCodec.currentVersion, deviceID: "", checklists: expected))))

        transport.deliver(.language("ja"))

        #expect(store.checklists == expected)
        #expect(locale.language == .japanese)
    }

    @Test
    func repeatedLanguageMessagesAreIdempotent() {
        let defaults = makeIsolatedDefaults()
        let transport = FakeChecklistSyncTransport()
        let locale = AppLocaleState(language: .english, defaults: defaults)
        let store = WatchChecklistStore(transport: transport, locale: locale)
        store.start()

        transport.deliver(.language("de"))
        transport.deliver(.language("de"))

        #expect(locale.language == .german)
        #expect(AppLanguage.load(from: defaults) == .german)
    }
}
```

**File**: `CheckStitchTests/ChecklistSyncCoordinatorTests.swift` **Action**: modify

`makeCoordinator` gains the new argument:

```swift
        ChecklistSyncCoordinator(
            transport: transport,
            snapshot: { checklists },
            createReminders: { await runner.run($0) },
            language: { .system })
```

New test:

```swift
    @Test
    func requestChecklistsRepushesTheLanguage() {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let coordinator = ChecklistSyncCoordinator(
            transport: transport,
            snapshot: { [] },
            createReminders: { await runner.run($0) },
            language: { .japanese })

        coordinator.start()
        transport.sentMessages = []          // ignore the cold-start push
        transport.deliver(.requestChecklists)

        #expect(transport.sentMessages.contains(.language("ja")))
    }
```

(`FakeChecklistSyncTransport.sentMessages` is `private(set)`; if clearing is not
possible, assert `contains(.language("ja"))` without clearing, or add a
`func clearSentMessages()` to the fake in `TestFixtures.swift`.)

### Verification

#### Automated
- [x] `make test-unit` passes
- [x] `make watch-build` compiles (the watchOS leg exercises `WatchSyncAdapter` and the watch root)
- [x] `AppLanguageSyncTests`, `WatchChecklistStoreTests`, `ChecklistSyncCoordinatorTests` green

#### Manual
- [ ] `bash scripts/run-watch.sh` with the watch paired; set **日本語** on the phone
- [ ] Raise/foreground the watch: its UI (list title "Checklists"/"チェックリスト", "Create reminders" button, empty-state text) is Japanese
- [ ] Force-quit the watch app (or the phone) and relaunch the watch: it still opens in Japanese
- [ ] Set the phone back to **System**; the watch returns to the device language on the next activation
- [ ] Known lag, accepted by design: a change made while the watch session is already active lands on the watch's next activation/`requestChecklists`, not instantly

---

## Phase 4: Hardening — close the leaks and make the flip observable

### Changes

#### 1. Core: `ChecklistItemPriority.label` becomes a resource

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistItemPriority.swift`
**Action**: modify

```swift
    /// User-facing name, kept on the model so no view branches over the cases.
    /// A resource so the item editor's rows and its accessibility label follow
    /// the app language.
    public var label: LocalizedStringResource {
        switch self {
        case .none: LocalizedStringResource("None", table: "Localizable", bundle: .module)
        case .low: LocalizedStringResource("Low", table: "Localizable", bundle: .module)
        case .medium: LocalizedStringResource("Medium", table: "Localizable", bundle: .module)
        case .high: LocalizedStringResource("High", table: "Localizable", bundle: .module)
        }
    }
```

#### 2. Core catalog: four new keys

**File**: `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`
**Action**: modify

Same entry shape as the existing `"Dark"` (`"extractionState": "manual"` +
all six `localizations`):

| key | en | de | es | fr | ja | zh-Hans |
|---|---|---|---|---|---|---|
| `None` | None | Keine | Ninguna | Aucune | なし | 无 |
| `Low` | Low | Niedrig | Baja | Basse | 低 | 低 |
| `Medium` | Medium | Mittel | Media | Moyenne | 中 | 中 |
| `High` | High | Hoch | Alta | Haute | 高 | 高 |

All non-English values differ from English, so no canary exclusion is needed
(ja/zh-Hans coincide with each other, which the canary does not compare).

#### 3. Fixtures: Core required keys

**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

```swift
        ("Core", ["System", "Light", "Dark", "None", "Low", "Medium", "High",
                  "Version %@ (%@)", "Version %@"]),
```

#### 4. App: the priority call sites

**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

```swift
                            .accessibilityLabel(Text(priority.label))
```

**File**: `CheckStitch/ItemEditView.swift`
**Action**: modify

No source change needed — `Label(priority.label, systemImage:)`,
`Text(priority.label)` and `Text(item.priority.label)` all accept a
`LocalizedStringResource` and now resolve against `\.locale`. Verify by
compiling; if `Label` rejects the resource, use
`Label { Text(priority.label) } icon: { Image(systemName: "checkmark") }`.

#### 5. App: `ItemRow.displayTitle` fallback

**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

```swift
    static func displayTitle(_ title: String) -> String {
        title.isEmpty
            ? LocalizedStringResource("Item", table: "Localizable", bundle: .main)
                .resolvedInAppLanguage()
            : title
    }
```

Keeps the `ChecklistDetailViewTests` contract (`displayTitle("")` non-empty,
`displayTitle("Milk") == "Milk"`).

#### 6. App: intent + EventKit error text

**File**: `CheckStitch/Intents/RunChecklistIntent.swift`
**Action**: modify

```swift
    var errorDescription: String? {
        LocalizedStringResource("That checklist no longer exists.", table: "Localizable", bundle: .main)
            .resolvedInAppLanguage()
    }
```

**File**: `CheckStitch/EventKitReminderDestination.swift`
**Action**: modify

```swift
    var errorDescription: String? {
        LocalizedStringResource(
            "That list no longer exists, so some reminders may not have been created.",
            table: "Localizable", bundle: .main)
            .resolvedInAppLanguage()
    }
```

#### 7. App catalog: the EventKit error key

**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

| key | en | de | es | fr | ja | zh-Hans |
|---|---|---|---|---|---|---|
| `That list no longer exists, so some reminders may not have been created.` | (as key) | Diese Liste existiert nicht mehr, daher wurden möglicherweise nicht alle Erinnerungen erstellt. | Esa lista ya no existe, por lo que es posible que no se hayan creado algunos recordatorios. | Cette liste n'existe plus, certains rappels n'ont peut-être pas été créés. | そのリストは存在しないため、一部のリマインダーが作成されていない可能性があります。 | 该列表已不存在，因此可能未创建部分提醒。 |

Add the key to `LocalizationFixtures.requiredKeys` App list as well.

#### 8. Watch: the detail button's two strings

**File**: `CheckStitchWatch/WatchChecklistDetailView.swift`
**Action**: modify

```swift
            Button {
                sent = store.run(checklist)
            } label: {
                Text(sent
                    ? LocalizedStringResource("Sent", table: "Localizable", bundle: .main)
                    : LocalizedStringResource("Create reminders", table: "Localizable", bundle: .main))
            }
            .disabled(sent || visibleItems.isEmpty)
```

The old `Button(sent ? String(localized:…) : …)` picked `Button`'s
`StringProtocol` overload, which never localizes and never follows `\.locale`.
The watch's other strings (`WatchChecklistListView`'s literals) are
`LocalizedStringKey`s and already follow the injected locale.

#### 9. Tests

**File**: `CheckStitchTests/ChecklistItemTests.swift` **Action**: modify

```swift
        #expect(!priority.label.key.isEmpty)
```

**File**: `CheckStitchTests/ChecklistDetailViewTests.swift` **Action**: modify

Add a live-mechanism pin for the accessibility label:

```swift
    @Test
    func priorityLabelResolvesThroughTheCoreCatalog() {
        #expect(ChecklistItemPriority.high.label.key == "High")
        #expect(ChecklistItemPriority.high.label.resolved(in: Locale(identifier: "de")) == "Hoch")
    }
```

**File**: `CheckStitchTests/AppLanguageSyncTests.swift` **Action**: modify

Already covers the malformed/duplicate/unknown sad paths added in Phase 3; add
one duplicate-receipt assertion for the coordinator's push if not already
covered:

```swift
    @Test
    func repeatedRequestChecklistsRepushesTheSameLanguage() {
        let transport = FakeChecklistSyncTransport()
        let coordinator = ChecklistSyncCoordinator(
            transport: transport, snapshot: { [] },
            createReminders: { _ in }, language: { .german })
        coordinator.start()
        transport.deliver(.requestChecklists)
        transport.deliver(.requestChecklists)
        #expect(transport.sentMessages.filter { $0 == .language("de") }.count == 3)
    }
```

#### 10. Evidence notes

**File**: `.pi/orksorksorks/alanvardy-var-1033-set-language/verify-language.md`
**Action**: create

Record, in this order:

1. **What the user should see**: after choosing Deutsch, the Settings sheet
   header reads `Einstellungen`, the first section `Oberfläche`, the picker
   `Sprache`, the picker rows System/Hell/Dunkel, and the toolbar button
   `Fertig`; the checklist list empty state and the item editor's priority rows
   are German too.
2. **Why the hosted gate cannot see it**: the unit runner resolves
   `String(localized:)` with the process (English) locale
   (`LocalizationTests.swift:77-78`), so `LocalizationTests` is not evidence for
   the live flip. The live flip is evidenced only by the simulator screenshot
   diff below.
3. **Screenshot-diff procedure** (per the `simulator` skill):
   ```bash
   UDID=D6D3CD6F-F7EF-4265-8E93-389ED04891EB   # this worktree's .simulator_id
   make run
   xcrun simctl io "$UDID" screenshot /tmp/lang-en.png     # Settings sheet, English
   # select Deutsch in the running app
   xcrun simctl io "$UDID" screenshot /tmp/lang-de.png     # same screen, German
   shasum -a 256 /tmp/lang-en.png /tmp/lang-de.png         # digests must differ
   ```
   Paste the two digests and the two screenshot paths into this file. A digest
   match means the flip did not happen — treat as a failure.
4. **macOS**: `make build-mac` compiles the macOS slice (gate leg); runtime
   evidence is the signed `make build-mac-signed` manual run, because container
   launches do not surface to the host (spike finding).

### Verification

#### Automated
- [ ] `bash scripts/test.sh` prints `gate: ok` (build → sim → test → build-mac → watch-build → shell tests → shellcheck)
- [ ] `rg -n "String\(localized" CheckStitch CheckStitchWatch CheckStitchCore/Sources` returns **no** bare eager `String(localized:)`; every remaining hit is inside a `LocalizedStringResource(...).resolved(in:)` / `.resolvedInAppLanguage()` expression
- [ ] `LocalizationTests` green with the four new Core keys (`None`/`Low`/`Medium`/`High`) and the new App key in `requiredKeys`
- [ ] `ChecklistItemTests`, `ChecklistDetailViewTests`, `AppLanguageSyncTests` green

#### Manual
- [ ] Simulator: select Deutsch and walk Settings → Appearance / Background / About, the checklist list, a detail row and the item editor (including the Priority menu); no English text remains on screen
- [ ] `xcrun simctl io` digests differ (see `verify-language.md`) and are recorded in that file
- [ ] Watch (rerun `bash scripts/run-watch.sh`): the detail screen's button reads `Gesendet` / `Erinnerungen erstellen` after the phone is set to Deutsch
- [ ] Delete the `appLanguage` key (or reinstall) and confirm the app opens in the device language (`.system` default)

---

## Testing Checkpoints

- **After Phase 1**: `make test-unit` green **and** the live flip observed on this worktree's simulator. Do not start Phase 2 until it is seen — this is the design's whole risk.
- **After Phase 2**: `make test-unit` + `LocalizationTests` green; one manual pass shows no English residue on Settings or a checklist screen.
- **After Phase 3**: `make test-unit` + `make watch-build` green; the watch shows the phone's language after a cold launch.
- **After Phase 4**: `bash scripts/test.sh` prints `gate: ok`; screenshot evidence recorded in `.pi/orksorksorks/alanvardy-var-1033-set-language/verify-language.md`.

## Notes / deviations from `structure.md`

- `ChecklistItemPriority.label` and `ReminderDestinationError.errorDescription`
  (plus `ItemRow.displayTitle`'s `"Item"`) are converted in Phase 4 even though
  they are not `String(localized:)` sites. They are user-visible English strings
  that Phase 4's goal ("no user-visible residue remains") cannot be met without;
  the conversion adds five catalog keys (`None`/`Low`/`Medium`/`High` to Core,
  the EventKit error to App) with all six translations.
- `AppInfo` is converted in Phase 2 (structure lists its file under Phase 2),
  so Phase 4's grep no longer flags it.
- `WatchSyncAdapter` gains `session(_:didReceiveUserInfo:)` — required, because
  the watch currently only receives `updateApplicationContext` and `sendContext`
  owns that dictionary.
- Pre-existing, deliberately untouched: `SettingsView` renders
  `Text("Import and Export")` while the catalog/required-keys carry the key
  `"Import and export"` (case mismatch), so that header falls back to its
  English literal. Out of this ticket's scope; flagged for a follow-up.
