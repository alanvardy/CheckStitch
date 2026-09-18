# Implementation Plan

## Overview

Add a Settings **Interface** section with a Language picker
(`System, English, Deutsch, Español, Français, 日本語, 简体中文`) that immediately
re-renders the whole app — Settings, `ContentView`, its subscreens and
Core-sourced labels — with no restart, persists the choice across launches, and
pushes the same language to the paired watch over the existing
WatchConnectivity application context. The mechanism (a
`Bundle`-instance override in Core + SwiftUI `\.locale` environment) is
**spike-gated**: Phase 0 must return GO before any shippable code is written.

## Spike note (applies to all phases)

`make test-unit` can prove the **resolution logic** (compiled `de.lproj` values,
fallbacks), but it cannot prove the `isa` swap or `Text` literal localization —
those are runtime/OS behaviours. Those are proven by Phase 0 and by the manual
steps. Do not weaken the manual checklists because unit tests are green.

---

## Phase 0: Spike gate — prove the override mechanism (throwaway, not merged)

### Purpose

Retire the ticket's core unknown before building UI. Code lives in a scratch
branch or a `#if DEBUG` probe file and is **deleted before Phase 1 begins**.

### Changes

#### 1. Scratch probe file (throwaway)
**File**: `CheckStitch/SpikeLanguageOverride.swift` (create, delete before Phase 1)
**Action**: create

Sketch (throwaway — shape only):

```swift
#if DEBUG
import Foundation

final class ProbeBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let code = ProbeLanguage.code,
              let path = path(forResource: code, ofType: "lproj"),
              let sub = Bundle(path: path) else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return sub.localizedString(forKey: key, value: value, table: tableName)
    }
}

enum ProbeLanguage { nonisolated(unsafe) static var code: String? }
#endif
```

Probe body (in a temporary `#Preview` or a debug button):
1. `object_setClass(Bundle.main, ProbeBundle.self)`, `ProbeLanguage.code = "de"`,
   then `String(localized: "Settings", table: "Localizable", bundle: .main)`.
2. Temporarily self-install on Core's `Bundle.module` and read
   `String(localized: "Dark", table: "Localizable", bundle: .module)`.
3. Render `Text("Settings")` inside `.environment(\.locale, Locale(identifier: "de"))`
   and confirm it re-renders German after toggling `\.locale` at runtime.
4. Set `ProbeLanguage.code = nil`; confirm both reads are byte-identical to the
   pre-swap English values.

Run the probe on the **iOS 18.7 simulator** (`make run`) and **macOS**
(`make build-mac-signed`, launch). Also verify whether `String(localized:)`
routes through `localizedString(forKey:value:table:)` or
`localizedString(forKey:value:table:localizations:)` — if the latter, the
subclass must override that method too.

#### 2. Go/no-go record
**File**: `.pi/orksorksorks/alanvardy-var-1033-set-language/spike.md` (create)
**Action**: create

Record exactly what was run, on which simulator/OS, the observed outputs, and a
single verdict: **GO** (proceed to Phase 1) or **NO-GO** (stop; re-run `design`
for the restart-based fallback + "Restart to apply" alert, design Open Risk 1).
Also record here whether `Text("literal")` followed `\.locale` (this decides the
optional `.id(appLanguage)` in Phase 2).

### Verification

#### Automated
- [x] `make build` succeeds with the probe present (probe compiles, is `#if DEBUG`)
- [x] `make test-unit` still passes (probe is unreferenced by tests)

#### Manual
- [ ] iOS 18.7 simulator: `String(localized:)` from `.main` returns German under the swap
- [ ] macOS: same `.main` check returns German
- [ ] Core `.module` check returns German under the swap
- [ ] `Text("literal")` follows `\.locale` through a live toggle
- [ ] `code == nil` path is byte-identical to today's English output
- [ ] `spike.md` contains a GO verdict (NO-GO → stop, re-run `design`)

---

## Phase 1: Walking skeleton — pick a language, Settings switches, persists

Settings gains an **Interface** section whose Language picker immediately
re-renders Settings' own labels and the Core-sourced `AppearanceMode.title`
German, and the choice survives relaunch. The apply call is inline here
(centralised into the delegates in Phase 2).

### Changes

#### 1. `AppLanguage` enum + key + load
**File**: `CheckStitchCore/Sources/CheckStitchCore/AppLanguage.swift`
**Action**: create

```swift
import Foundation

/// A user-selectable UI language. `.system` installs no override, so the app
/// follows the process language (and pre-existing behaviour is unchanged).
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case en
    case de
    case es
    case fr
    case ja
    case zhHans = "zh-Hans"

    /// Single shared `UserDefaults` key. Shared with the watch, which reads the
    /// last pushed code from its own local defaults.
    public static let defaultsKey = "appLanguage"

    /// The override code (`"de"`, `"zh-Hans"`), or `nil` for `.system`.
    public var code: String? { self == .system ? nil : rawValue }

    /// The locale fed to SwiftUI's `\.locale` environment (drives `Text` literals).
    public var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    /// Label shown in the picker, written in the language's own language.
    /// `.system` is the one localized value (Core catalog key "System").
    public var endonym: String {
        switch self {
        case .system: SharedStrings.system
        case .en: "English"
        case .de: "Deutsch"
        case .es: "Español"
        case .fr: "Français"
        case .ja: "日本語"
        case .zhHans: "简体中文"
        }
    }

    /// Validates a stored/wire raw string, falling back to `.system`.
    public static func resolve(_ raw: String?) -> AppLanguage {
        guard let raw, let value = AppLanguage(rawValue: raw) else { return .system }
        return value
    }

    /// Reads the persisted selection, mirroring `AppearanceMode.load(from:)`.
    public static func load(from defaults: UserDefaults = .standard) -> AppLanguage {
        resolve(defaults.string(forKey: defaultsKey))
    }
}
```

#### 2. `LanguageOverride` + `LanguageBundle`
**File**: `CheckStitchCore/Sources/CheckStitchCore/LanguageBundle.swift`
**Action**: create

`LanguageOverride` is the one shared, lock-guarded in-memory code store.
`LanguageBundle` is a **stateless** `Bundle` subclass (`object_setClass` swaps
onto instances whose stored properties were never initialised — stored
properties would be undefined behaviour, so there are none). It must restate
`@unchecked Sendable` (Swift 6 + warnings-as-errors; see `StubBundle.swift`).

```swift
import Foundation
import ObjectiveC

/// The single shared override code read by every `LanguageBundle` instance.
public enum LanguageOverride {
    public static func set(_ code: String?) {
        lock.lock(); defer { lock.unlock() }; self.code = code
    }

    public static var currentCode: String? {
        lock.lock(); defer { lock.unlock() }; return code
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var code: String?
}

/// A `Bundle` whose localized lookups forward to the selected `xx.lproj`
/// sub-bundle, so `String(localized:bundle:)` callers switch language without
/// a restart. Installed by swapping the instance's `isa`.
public final class LanguageBundle: Bundle, @unchecked Sendable {
    /// Resolves `key` from the `code.lproj` inside `bundle`, or the plain
    /// bundle value when `code` is nil/unsupported. Pure and directly testable.
    public static func resolvedString(
        forKey key: String,
        value: String?,
        table tableName: String?,
        code: String?,
        in bundle: Bundle
    ) -> String {
        guard let code,
              let path = bundle.path(forResource: code, ofType: "lproj"),
              let sub = Bundle(path: path) else {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return sub.localizedString(forKey: key, value: value, table: tableName)
    }

    /// Installs the override on the app bundle and on Core's own resource
    /// bundle (`Bundle.module` is internal, so only Core can swap it).
    public static func install(appBundle: Bundle) {
        object_setClass(appBundle, LanguageBundle.self)
        object_setClass(Bundle.module, LanguageBundle.self)
    }

    public override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        Self.resolvedString(forKey: key, value: value, table: tableName,
                            code: LanguageOverride.currentCode, in: self)
    }
}
```

If the Phase 0 spike showed `String(localized:)` routes through
`localizedString(forKey:value:table:localizations:)`, add an override for it
that forwards to the same `resolvedString` logic (forwarding to
`Bundle(path:).localizedString(...localizations:)`).

#### 3. `AppLanguagePreference` (app-side)
**File**: `CheckStitch/AppLanguagePreference.swift`
**Action**: create

Mirrors `AppearanceModePreference` (`CheckStitch/AppearanceMode.swift:81-90`):

```swift
import Foundation
import CheckStitchCore

/// Persists the language raw string in `UserDefaults.standard`.
/// An absent or unrecognized key resolves to `"system"`.
struct AppLanguagePreference {
    init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    static let defaultsKey = AppLanguage.defaultsKey  // "appLanguage"

    var rawValue: String {
        AppLanguage.resolve(defaults.string(forKey: key)).rawValue
    }

    func setRawValue(_ raw: String) {
        defaults.set(AppLanguage.resolve(raw).rawValue, forKey: key)
    }

    private let defaults: UserDefaults
    private let key: String
}
```

#### 4. Settings picker + Interface section
**File**: `CheckStitch/SettingsView.swift`
**Action**: modify

Add a required binding and fold the App-catalog keys into the first section:

```swift
struct SettingsView: View {
    @Binding var appearanceMode: AppearanceMode
    @Binding var appLanguage: AppLanguage          // NEW
    @Bindable var bindings: SettingsBindings
    var backgroundImage: BackgroundImageStore
    var onExport: () -> Void = {}
    var onImport: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    // ...
    Section("Interface") {                          // was `Section {`
        Picker(selection: $appearanceMode) { /* unchanged */ }
            .accessibilityIdentifier("appearancePicker")

        Picker(selection: $appLanguage) {
            ForEach(AppLanguage.allCases, id: \.self) { language in
                Text(verbatim: language.endonym).tag(language)
            }
        } label: {
            Text("Language")
        }
        .accessibilityIdentifier("languagePicker")
    }
```

`Text(verbatim:)` is deliberate: endonyms are not catalog keys (design
Decision 4). Update both `#Preview`s to pass `appLanguage: .constant(.system)`.

#### 5. ContentView wiring
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

- Add the stored preference next to `appearanceMode` (match the literal-key
  precedent at `ContentView.swift:11`):

```swift
@AppStorage("appLanguage")
var appLanguage = AppLanguage.system
```

- Root: apply the SwiftUI locale to the whole tree (the sheet and its
  subscreens inherit environment from the presenter). Put it on the `ZStack`
  root's chain, alongside the existing `.preferredColorScheme` region:

```swift
.environment(\.locale, appLanguage.locale)
```

- Apply the bundle override inline for now, next to the existing appearance
  `onChange`:

```swift
.onChange(of: appLanguage) { _, new in
    LanguageOverride.set(new.code)
    LanguageBundle.install(appBundle: .main)
}
```

- Pass the binding through the sheet builder (`ContentView.swift:540-544`):

```swift
SettingsView(
    appearanceMode: $appearanceMode,
    appLanguage: $appLanguage,
    bindings: bag,
    backgroundImage: backgroundImage,
    onExport: { requestDataAction(.export) },
    onImport: { requestDataAction(.importChecklists) })
```

- Startup replay in `MyApp.init()` (before first render; see `MyApp.swift:26-33`):

```swift
let language = AppLanguage.load()
LanguageOverride.set(language.code)
LanguageBundle.install(appBundle: .main)
```

#### 6. App catalog keys
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Add two keys with all six translations (the canary requires non-English ≠
English, so no exclusions are needed):

| key | en | de | es | fr | ja | zh-Hans |
|---|---|---|---|---|---|---|
| `Interface` | Interface | Darstellung | Interfaz | Affichage | インターフェース | 界面 |
| `Language` | Language | Sprache | Idioma | Langue | 言語 | 语言 |

#### 7. Test fixtures
**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add `"Interface"` and `"Language"` to the `"App"` entry of `requiredKeys`.

#### 8. Tests
**Files**:
- `CheckStitchTests/AppLanguageTests.swift` (create)
- `CheckStitchTests/AppLanguagePreferenceTests.swift` (create)
- `CheckStitchTests/LanguageBundleTests.swift` (create)
- `CheckStitchTests/ViewRenderTests.swift` (modify)

`AppLanguageTests` (Swift Testing, no `@MainActor` needed):
```swift
@testable import CheckStitchCore
import Foundation
import Testing

struct AppLanguageTests {
    @Test
    func resolveMapsEveryRawValue() {
        for language in AppLanguage.allCases {
            #expect(AppLanguage.resolve(language.rawValue) == language)
        }
    }

    @Test
    func resolveFallsBackToSystemForUnknownOrMissingValue() {
        #expect(AppLanguage.resolve("klingon") == .system)
        #expect(AppLanguage.resolve(nil) == .system)
    }

    @Test
    func systemHasNoCode() {
        #expect(AppLanguage.system.code == nil)
    }

    @Test(arguments: [AppLanguage.de, .es, .fr, .ja, .zhHans])
    func nonSystemCasesExposeCodeAndLocale(_ language: AppLanguage) {
        #expect(language.code == language.rawValue)
        #expect(language.locale.identifier == language.rawValue)
    }

    @Test
    func endonymsAreNonEmpty() {
        #expect(AppLanguage.allCases.allSatisfy { !$0.endonym.isEmpty })
        #expect(AppLanguage.system.endonym == SharedStrings.system)
    }
}
```

`AppLanguagePreferenceTests` (mirrors `AppearanceModePreferenceTests.swift`):
```swift
@testable import CheckStitch
import CheckStitchCore
import Foundation
import Testing

struct AppLanguagePreferenceTests {
    @Test
    func preferenceSetThenReadRoundTrips() {
        let defaults = makeIsolatedDefaults()
        let preference = AppLanguagePreference(defaults: defaults)
        preference.setRawValue("de")
        #expect(preference.rawValue == "de")
        #expect(AppLanguage.load(from: defaults) == .de)
    }

    @Test
    func preferenceIgnoresUnknownStoredValue() {
        let defaults = makeIsolatedDefaults()
        defaults.set("klingon", forKey: AppLanguagePreference.defaultsKey)
        #expect(AppLanguagePreference(defaults: defaults).rawValue == "system")
    }

    @Test
    func defaultsKeyMatchesTheAppStorageKey() {
        #expect(AppLanguagePreference.defaultsKey == "appLanguage")
    }
}
```

`LanguageBundleTests` — unit-test the **pure resolver** against the compiled
`de.lproj` (the real non-English assertion the `String.en` pin cannot make).
Do **not** mutate `Bundle.main`'s isa or the global override here; the swap is
Phase 0's evidence:
```swift
@testable import CheckStitchCore
import Foundation
import Testing

struct LanguageBundleTests {
    @Test
    func germanCodeResolvesTheCompiledGermanValue() throws {
        let germanURL = try #require(
            Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                            subdirectory: "", localization: "de"))
        let table = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: germanURL), format: nil) as? [String: String])

        let resolved = LanguageBundle.resolvedString(
            forKey: "Settings", value: nil, table: "Localizable",
            code: "de", in: .main)

        #expect(resolved == table["Settings"])
    }

    @Test
    func unsupportedCodeFallsBackToTheBundleValue() {
        let system = LanguageBundle.resolvedString(
            forKey: "Settings", value: nil, table: "Localizable",
            code: "klingon", in: .main)
        #expect(system == String.en("Settings", bundle: .main))
    }

    @Test
    func missingCodeUsesTheBundleValue() {
        let system = LanguageBundle.resolvedString(
            forKey: "Settings", value: nil, table: "Localizable",
            code: nil, in: .main)
        #expect(system == String.en("Settings", bundle: .main))
    }
}
```

`ViewRenderTests`:
- Add `appLanguage: .constant(.system)` to all four existing
  `SettingsView(...)` constructions (`settingsViewListsAllAppearanceModes`,
  `settingsViewExposesAboutRow`, `settingsViewRendersWithImportAndExportRows`),
  and to the previews (source, not test).
- Add the analogue test:
```swift
@Test
func settingsViewListsAllLanguages() {
    let view = SettingsView(
        appearanceMode: .constant(.system),
        appLanguage: .constant(.system),
        bindings: SettingsBindings(),
        backgroundImage: BackgroundImageStore())
    #expect(String(describing: view.body).isEmpty == false)
    #expect(AppLanguage.allCases.map(\.endonym).first == "System")
    #expect(AppLanguage.allCases.count == 7)
    #expect(AppLanguage.allCases.allSatisfy { !$0.endonym.isEmpty })
}
```

### Verification

#### Automated
- [ ] `make test-unit` passes (new suites + updated `ViewRenderTests` + localization suites with the two new keys)
- [ ] `make build` succeeds
- [ ] `make build-mac` succeeds

#### Manual
- [ ] Simulator: open Settings → Interface shows Appearance + Language; pick Deutsch → the Language/Appearance labels and the Core-sourced `AppearanceMode.title` values render German immediately
- [ ] Pick System → labels return to English
- [ ] Relaunch the app after picking Deutsch → still German
- [ ] macOS: same two checks

---

## Phase 2: Whole-app immediate re-render (all screens + Core strings)

Every screen switches on pick, not just Settings; the apply path is centralised
into the per-OS delegates and replayed at launch/activation, mirroring
`applyAppearance`.

### Changes

#### 1. iOS delegate apply seam
**File**: `CheckStitch/AppDelegate.swift`
**Action**: modify

```swift
#if os(iOS)
    /// Installs the language override on the app bundle (and Core's resource
    /// bundle, via `LanguageBundle.install`). `.system` clears the override so
    /// lookups fall back to the process language.
    static func applyLanguage(_ language: AppLanguage) {
        LanguageOverride.set(language.code)
        LanguageBundle.install(appBundle: .main)
    }

    func applicationDidBecomeActive(_: UIApplication) {
        Self.applyAppearance(AppearanceMode.load())
        Self.applyLanguage(AppLanguage.load())
    }
#endif
```

#### 2. macOS delegate apply seam
**File**: `CheckStitch/AppDelegate.swift`
**Action**: modify

```swift
#if os(macOS)
    static func applyLanguage(_ language: AppLanguage) {
        LanguageOverride.set(language.code)
        LanguageBundle.install(appBundle: .main)
    }

    func applicationDidFinishLaunching(_: Notification) {
        Self.applyAppearance(AppearanceMode.load())
        Self.applyLanguage(AppLanguage.load())
        clampWindowsToScreen()
        // ... existing observers unchanged
    }

    func applicationDidBecomeActive(_: Notification) {
        Self.applyAppearance(AppearanceMode.load())
        Self.applyLanguage(AppLanguage.load())
        clampWindowsToScreen()
    }
#endif
```

`import CheckStitchCore` is already at the top of `MyApp.swift`; add it to
`AppDelegate.swift` if `AppLanguage` is not already in scope (it is re-exported
via the app's `CheckStitchCore` import chain — verify at compile time).

#### 3. ContentView switches to the delegate seam
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Replace the Phase 1 inline body:

```swift
.onChange(of: appLanguage) { _, new in
    #if os(iOS)
        AppDelegate.applyLanguage(new)
    #endif
    #if os(macOS)
        MacAppDelegate.applyLanguage(new)
    #endif
}
```

Keep `.environment(\.locale, appLanguage.locale)` on the root. Only add a root
`.id(appLanguage)` if the Phase 0 spike showed stale `Text` literals — and if
so, place it on the `NavigationStack`'s content group rather than the `ZStack`
root, and accept that the presented Settings sheet is recreated (reopen the
sheet after switching). Default: **no `.id`**.

#### 4. MyApp startup replay via the delegate
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

```swift
init() {
    #if os(iOS)
        AppDelegate.applyLanguage(AppLanguage.load())
    #endif
    #if os(macOS)
        MacAppDelegate.applyLanguage(AppLanguage.load())
    #endif
    let store = ChecklistStore()
    // ... unchanged
}
```

#### 5. `SharedStrings` — consume only
**File**: `CheckStitchCore/Sources/CheckStitchCore/SharedStrings.swift`
**Action**: none

No change. It already resolves through `Bundle.module`; `LanguageBundle.install`
swaps that bundle, so `AppearanceMode.title` (Core) follows automatically.
Documented here so the phase is not mistaken for a missed edit.

#### 6. Tests
**File**: `CheckStitchTests/ViewRenderTests.swift`
**Action**: modify

- Add a render test that builds `SettingsView` inside
  `.environment(\.locale, Locale(identifier: "de"))` and asserts it renders
  (exercises the locale-threaded path; it does **not** assert German text —
  the pin cannot).
```swift
@Test
func settingsViewRendersUnderANonSystemLocale() {
    let view = SettingsView(
        appearanceMode: .constant(.system),
        appLanguage: .constant(.de),
        bindings: SettingsBindings(),
        backgroundImage: BackgroundImageStore())
        .environment(\.locale, Locale(identifier: "de"))
    #expect(renders(view))
}
```
- Add a `LanguageBundleTests` baseline test that the no-code path is
  byte-identical for a Core key:
```swift
@Test
func missingCodeLeavesCoreValuesUnchanged() {
    let resolved = LanguageBundle.resolvedString(
        forKey: "Dark", value: nil, table: "Localizable",
        code: nil, in: .module)
    #expect(resolved == String.en("Dark", bundle: .module))
}
```

### Verification

#### Automated
- [ ] `make test-unit` passes
- [ ] `make build-mac` succeeds

#### Manual
- [ ] iOS: pick Deutsch → `ContentView` (empty state / list chrome / nav title), the Settings sheet and the Background and About subscreens all switch, with no stale English text and no restart
- [ ] iOS: pick System → the whole app returns to the process language
- [ ] macOS: same two checks
- [ ] No mixed-language screen observed (if any stale literal appears, add the conditional `.id(appLanguage)` and re-check — record the decision in `plan`/PR notes)

---

## Phase 3: Watch renders the phone's language

The phone pushes its language inside the existing application context; the
watch applies it live and remembers it for cold launches.

### Changes

#### 1. Message + transport wire shape
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify

```swift
public enum ChecklistSyncKey {
    public static let context = "checklists"
    public static let runChecklist = "runChecklist"
    public static let requestChecklists = "requestChecklists"
    public static let language = "language"          // NEW
}

public enum ChecklistSyncMessage: Equatable, Sendable {
    /// Phone → watch. `language` is the raw `AppLanguage` value (`"system"`,
    /// `"de"`, …); `nil` means an older phone that predates the key.
    case context(Data, language: String?)            // CHANGED
    case runChecklist(UUID)
    case requestChecklists

    public init?(userInfo: [String: Any]) {
        if let data = userInfo[ChecklistSyncKey.context] as? Data {
            self = .context(data, language: userInfo[ChecklistSyncKey.language] as? String)
        } else if let raw = userInfo[ChecklistSyncKey.runChecklist] as? String,
                  let id = UUID(uuidString: raw) {
            self = .runChecklist(id)
        } else if userInfo[ChecklistSyncKey.requestChecklists] as? Bool == true {
            self = .requestChecklists
        } else {
            return nil
        }
    }

    public var userInfo: [String: Any] {
        switch self {
        case .context(let data, let language):
            var info: [String: Any] = [ChecklistSyncKey.context: data]
            if let language { info[ChecklistSyncKey.language] = language }
            return info
        case .runChecklist(let id):
            [ChecklistSyncKey.runChecklist: id.uuidString]
        case .requestChecklists:
            [ChecklistSyncKey.requestChecklists: true]
        }
    }
}
```

Transport protocol gains the language on the context send:

```swift
    /// Sends the phone's checklist context plus its current language code.
    @discardableResult func sendContext(_ data: Data, language: String?) -> Bool
```

Tolerance: a missing `language` key decodes to `nil`; an unknown raw string is
ignored by the receiver — old phone/watch combinations keep working.

#### 2. Phone coordinator + adapter
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift`
**Action**: modify

```swift
    private func pushContext() {
        guard let data = try? ChecklistCodec.encode(ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: "", checklists: snapshot())) else { return }
        // Always send a raw value so an explicit System choice propagates;
        // a *missing* key (older phone) means "keep the last language".
        transport.sendContext(data, language: LanguageOverride.currentCode ?? AppLanguage.system.rawValue)
    }
```

**File**: `CheckStitch/PhoneSyncAdapter.swift`
**Action**: modify

```swift
    @discardableResult
    func sendContext(_ data: Data, language: String?) -> Bool {
        guard session.activationState == .activated else { return false }
        do {
            try session.updateApplicationContext(
                ChecklistSyncMessage.context(data, language: language).userInfo)
            return true
        } catch {
            Self.logger.error("Failed to push checklist context: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
```

**File**: `CheckStitchWatch/WatchSyncAdapter.swift`
**Action**: modify

```swift
    @discardableResult
    func sendContext(_: Data, language _: String?) -> Bool { false }
```

#### 3. Watch store applies + remembers the language
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify

`WatchChecklistStore` gains an injectable `UserDefaults` and an observable
`language`; the persisted raw code is validated by `AppLanguage` so a cold
unsynced launch is correct. The class swap itself happens once at watch startup
(step 4); the store only steers the shared `LanguageOverride`.

```swift
@MainActor
@Observable
public final class WatchChecklistStore {
    public init(transport: ChecklistSyncTransport, defaults: UserDefaults = .standard) {
        self.transport = transport
        self.defaults = defaults
        self.language = AppLanguage.load(from: defaults)
    }

    public private(set) var language: AppLanguage

    // in `receive`, the context case becomes:
    private func receive(_ message: ChecklistSyncMessage) {
        switch message {
        case .context(let data, let language):
            applyLanguage(language)
            switch ChecklistCodec.classify(data) {
            case .loaded(let envelope):
                checklists = envelope.checklists
            case .migratable(let from, let envelope) where from >= 2:
                checklists = envelope.checklists
            default:
                break
            }
        case .runChecklist, .requestChecklists:
            break
        }
    }

    /// Applies a pushed raw code. Absent (`nil`) or unrecognized values keep the
    /// previous language; `"system"` explicitly clears the override.
    private func applyLanguage(_ raw: String?) {
        guard let raw, let resolved = AppLanguage(rawValue: raw) else { return }
        language = resolved
        defaults.set(resolved.rawValue, forKey: AppLanguage.defaultsKey)
        LanguageOverride.set(resolved.code)
    }

    private let defaults: UserDefaults
}
```

#### 4. Watch app startup + locale environment
**File**: `CheckStitchWatch/CheckStitchWatchApp.swift`
**Action**: modify

```swift
import CheckStitchCore
import SwiftUI

@main
struct CheckStitchWatchApp: App {
    @State private var store = WatchChecklistStore(transport: WatchSyncAdapter())

    init() {
        // Apply the last pushed language before first render; the store then
        // keeps `LanguageOverride` in sync live (the class swap reads it per lookup).
        LanguageOverride.set(store.language.code)
        LanguageBundle.install(appBundle: .main)
    }

    var body: some Scene {
        WindowGroup {
            WatchChecklistListView()
                .environment(store)
                .environment(\.locale, store.language.locale)
        }
    }
}
```

Note: `@State` is not readable in `init()` — read the persisted value directly
instead: `let persisted = AppLanguage.load()` in `init()`, and pass it into the
store or read it from `store` after construction. Concretely:

```swift
    init() {
        let language = AppLanguage.load()
        LanguageOverride.set(language.code)
        LanguageBundle.install(appBundle: .main)
    }
```

The `@State` store initialiser already reads the same key, so both agree.

#### 5. Test fixture
**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify

`FakeChecklistSyncTransport` records the language index-aligned with contexts
(keeps every existing `sentContexts` assertion valid):

```swift
    private(set) var sentContexts: [Data] = []
    private(set) var sentLanguages: [String?] = []      // NEW

    @discardableResult
    func sendContext(_ data: Data, language: String?) -> Bool {
        sentContexts.append(data)
        sentLanguages.append(language)
        return acceptsSends
    }
```

#### 6. Tests
**Files**:
- `CheckStitchTests/ChecklistSyncMessageTests.swift` (modify)
- `CheckStitchTests/ChecklistSyncCoordinatorTests.swift` (modify)
- `CheckStitchTests/WatchChecklistStoreTests.swift` (modify)

`ChecklistSyncMessageTests`:
```swift
    @Test
    func contextWithLanguageRoundTripsThroughUserInfo() {
        let data = Data("hello".utf8)
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.context(data, language: "de").userInfo)
            == .context(data, language: "de"))
    }

    @Test
    func contextWithoutLanguageRoundTripsThroughUserInfo() {
        let data = Data("hello".utf8)
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.context(data, language: nil).userInfo)
            == .context(data, language: nil))
    }

    @Test
    func wrongLanguageTypeIsIgnored() {
        let data = Data("hello".utf8)
        #expect(ChecklistSyncMessage(userInfo: [
            ChecklistSyncKey.context: data, ChecklistSyncKey.language: 42,
        ]) == .context(data, language: nil))
    }
```
Update the existing `contextRoundTripsThroughUserInfo` call to the new case
shape (`.context(data, language: nil)`).

`ChecklistSyncCoordinatorTests`:
```swift
    @Test
    func coordinatorPushCarriesTheCurrentLanguage() {
        LanguageOverride.set("de")
        defer { LanguageOverride.set(nil) }
        let transport = FakeChecklistSyncTransport()
        let coordinator = makeCoordinator(transport: transport, checklists: [], runner: SpyChecklistRunner())

        coordinator.start()

        #expect(transport.sentLanguages == ["de"])
    }

    @Test
    func coordinatorPushSendsSystemWhenNoOverrideIsInstalled() {
        LanguageOverride.set(nil)
        let transport = FakeChecklistSyncTransport()
        let coordinator = makeCoordinator(transport: transport, checklists: [], runner: SpyChecklistRunner())

        coordinator.start()

        #expect(transport.sentLanguages == ["system"])
    }
```

`WatchChecklistStoreTests` (use `makeIsolatedDefaults()` and reset the global):
```swift
    @Test
    func pushedLanguageIsStoredAndPersisted() throws {
        LanguageOverride.set(nil)
        defer { LanguageOverride.set(nil) }
        let defaults = makeIsolatedDefaults()
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport, defaults: defaults)
        store.start()

        let payload = try ChecklistCodec.encode(ChecklistEnvelope(
            version: ChecklistCodec.currentVersion, deviceID: "", checklists: []))
        transport.deliver(.context(payload, language: "de"))

        #expect(store.language == .de)
        #expect(defaults.string(forKey: AppLanguage.defaultsKey) == "de")
        #expect(LanguageOverride.currentCode == "de")
    }

    @Test
    func absentLanguageKeepsThePreviousOne() throws {
        LanguageOverride.set(nil)
        defer { LanguageOverride.set(nil) }
        let defaults = makeIsolatedDefaults()
        defaults.set("de", forKey: AppLanguage.defaultsKey)
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport, defaults: defaults)
        store.start()

        let payload = try ChecklistCodec.encode(ChecklistEnvelope(
            version: ChecklistCodec.currentVersion, deviceID: "", checklists: []))
        transport.deliver(.context(payload, language: nil))

        #expect(store.language == .de)
        #expect(LanguageOverride.currentCode == "de")
    }

    @Test
    func unknownLanguageKeepsThePreviousOne() throws {
        LanguageOverride.set(nil)
        defer { LanguageOverride.set(nil) }
        let defaults = makeIsolatedDefaults()
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport, defaults: defaults)
        store.start()

        let payload = try ChecklistCodec.encode(ChecklistEnvelope(
            version: ChecklistCodec.currentVersion, deviceID: "", checklists: []))
        transport.deliver(.context(payload, language: "klingon"))

        #expect(store.language == .system)
        #expect(defaults.string(forKey: AppLanguage.defaultsKey) == nil)
    }

    @Test
    func pushedSystemClearsTheOverride() throws {
        LanguageOverride.set(nil)
        defer { LanguageOverride.set(nil) }
        let defaults = makeIsolatedDefaults()
        defaults.set("de", forKey: AppLanguage.defaultsKey)
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport, defaults: defaults)
        store.start()

        let payload = try ChecklistCodec.encode(ChecklistEnvelope(
            version: ChecklistCodec.currentVersion, deviceID: "", checklists: []))
        transport.deliver(.context(payload, language: "system"))

        #expect(store.language == .system)
        #expect(LanguageOverride.currentCode == nil)
    }
```

### Verification

#### Automated
- [ ] `make test-unit` passes (message/coordinator/watch suites updated)
- [ ] `make watch-build` succeeds
- [ ] `make build` succeeds (phone adapter protocol change compiles)

#### Manual
- [ ] Phone in Deutsch → `bash scripts/run-watch.sh`, watch shows `Checklists`/`No checklists` and the other watch catalog strings in German after the push (or after a refresh)
- [ ] Kill and cold-launch the watch unsynced → it keeps the last pushed language
- [ ] Switch the phone to System → the next push returns the watch to the process language

---

## Phase 4: Hardening — sad paths, fallback, no mixed-language UI

No new surface. Residual robustness and final validation only.

### Changes

#### 1. Finalize the `.id(appLanguage)` decision
**File**: `CheckStitch/ContentView.swift`
**Action**: modify only if Phase 0 recorded stale literals

If the spike showed stale `Text` literals, add a scoped `.id(appLanguage)` and
re-verify the Settings sheet (it is recreated; reopening shows the new
language). If not, leave as is. Record the decision in the PR description.

#### 2. Failing-first sad-path tests (only add tests that were not already
written in Phases 1/3, plus any assertion the manual run surfaced)

**Files**:
- `CheckStitchTests/LanguageBundleTests.swift`
- `CheckStitchTests/AppLanguagePreferenceTests.swift`
- `CheckStitchTests/ChecklistSyncMessageTests.swift`

Cover, if not already:
```swift
    @Test
    func unsupportedStoredCodeResolvesToSystem() {
        let defaults = makeIsolatedDefaults()
        defaults.set("klingon", forKey: AppLanguagePreference.defaultsKey)
        #expect(AppLanguage.load(from: defaults) == .system)
    }
```
and the malformed-context-keeps-previous case (deliver `Data("not json".utf8)`
with `language: "de"`; assert the list is intact **and** `store.language == .de`).

#### 3. Catalog discipline re-check
**File**: `CheckStitchTests/LocalizationTests.swift`
**Action**: none expected

The existing `everyRequiredKeyIsPresent`, `catalogsHaveAllSixLanguages` and
`nonEnglishValuesDifferFromEnglish` suites cover the two new keys once
`LocalizationFixtures.requiredKeys` is updated (Phase 1) and the catalog carries
six translations. Only touch this file if the gate surfaces a gap.

#### 4. Fixes surfaced by the platform legs
Any compile fix required by `make build-mac` / `make watch-build` lands here.
No refactoring of adjacent code.

### Verification

#### Automated
- [ ] `make test-unit` passes
- [ ] `bash scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] Relaunch checks: Deutsch persists across relaunch on iOS + macOS; System returns to English
- [ ] Watch cold launch unsynced keeps the last pushed language, and an updated phone's next push wins
- [ ] Watch with no language ever pushed shows the system language (legitimate fallback)
- [ ] No screen shows mixed languages (catalog strings and literals agree) after switching in both directions

---

## Testing Checkpoints (mirrors `structure.md`)

- [ ] After Phase 0: `spike.md` records GO; NO-GO → stop and re-run `design`
- [ ] After Phase 1: `make test-unit` + `make build` green; picker switch + relaunch persist demonstrated
- [ ] After Phase 2: `make test-unit` + `make build-mac` green; whole-app switch and System restore demonstrated
- [ ] After Phase 3: `make test-unit` + `make watch-build` green; watch receives the language
- [ ] After Phase 4: `bash scripts/test.sh` → `gate: ok`

## Deviations from `structure.md`

1. **Phase 1 file list** names `CheckStitch/AppLanguagePreference.swift` (kept —
   design Decision 8) but the Phase 3 watch needs the same defaults key from
   Core. Resolved by adding `AppLanguage.defaultsKey` to the Core enum; the
   app-side preference aliases it. No watch-side preference type is introduced.
2. **Phase 3 sync test files**: `structure.md` cites `CheckStitchTests/ChecklistSyncTests.swift`,
   which does not exist. The work maps to the real files
   `ChecklistSyncMessageTests.swift`, `ChecklistSyncCoordinatorTests.swift` and
   `WatchChecklistStoreTests.swift`.
3. **Phase 3 transport signature**: `structure.md` says the coordinator "adds the
   code to the same dictionary". To make an explicit **System** choice propagate
   (and keep a missing key meaning "keep previous" for older phones), the
   coordinator sends the raw value (`currentCode ?? "system"`) over a
   `sendContext(_:language:)` transport method rather than only an optional code.
4. **Phase 1 puts the apply inline** and Phase 2 centralises it into
   `applyLanguage(_:)`; this preserves the 1 → 2 vertical slices in
   `structure.md` (walking skeleton first, delegate seam second).

No open questions remain.
