# Implementation Plan

## Overview

Add an **Interface** settings subscreen to CheckStitch holding the existing
Appearance picker, a new **Text Size** picker (System / Small / Medium / Large /
Extra Large) that scales text app-wide via SwiftUI Dynamic Type, and an
iOS-only **Allow landscape** toggle that locks the phone to portrait when off.
The shape is ported from `/Users/vardy/dev/SingleThread`
(`TextSize.swift`, `TextSizeModifier.swift`, `InterfaceSettingsView.swift`,
`AppDelegate.swift`) onto CheckStitch's own settings architecture:
`SettingsView` → subscreen, staged `SettingsBindings` bag, `@AppStorage` on
`ContentView`, and the `CheckStitch/AppDelegate.swift` platform bridge.

## Recon notes (decisions already made — do not re-litigate)

- **No `project.pbxproj` edit.** `CheckStitch/` is a
  `PBXFileSystemSynchronizedRootGroup`; new files under it are picked up
  automatically.
- **No `Info.plist` / build-setting change.** `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`
  already lists Portrait + Landscape, and the portrait lock is enforced at
  runtime by the app-delegate mask (`application(_:supportedInterfaceOrientationsFor:)`),
  which overrides the Info.plist value. Default `allowsLandscape == true`
  (missing key → `true`) therefore preserves today's behaviour exactly.
- **macOS only runs the unit suites.** `make test-unit` (and therefore
  `make test`) uses `platform=macOS`; only the single `CheckStitchUITests` smoke
  runs on the simulator. So the orientation decision cannot be tested through a
  `#if os(iOS)` mask — it is expressed as a cross-platform
  `OrientationPolicy` enum (`.portrait` / `.allButUpsideDown`) whose UIKit mask
  conversion lives in an iOS-only extension. This is the one deliberate
  deviation from a literal copy of SingleThread's inline `#if os(iOS)` mask.
- **`LocalizationTests` are strict**: every `Localizable.xcstrings` entry must
  carry all six languages (`catalogsHaveAllSixLanguages`), and every non-English
  value must differ from English unless listed in
  `LocalizationFixtures.excludedIdentities`
  (`nonEnglishValuesDifferFromEnglish`). New App-catalog keys ship with all six
  translations (taken from SingleThread's catalog, which already carries every
  one of them), and `Interface` needs an exclusion entry because **fr
  "Interface" is byte-identical to English**.
- **Decision:** the existing Appearance picker **moves** from `SettingsView`
  into the new `InterfaceSettingsView` (SingleThread groups it there, and
  `medium.md` lists appearance as part of the subscreen). No test asserts the
  picker's location, so nothing breaks.
- Watch target is untouched: `TextSize`/`OrientationPreference` live in the app
  target, and `CheckStitchCore` gains nothing.

## Conventions to follow (from the existing code)

- App-target enum style: `CheckStitch/AppearanceMode.swift` — `String, CaseIterable`,
  `systemImage: String`, and `title: String` via
  `String(localized: "…", table: "Localizable", bundle: .main)`.
- Subscreen style: `CheckStitch/BackgroundSettingsView.swift` — `Form`,
  `.navigationTitle`, `.settingsSubscreenLayout()`, a
  `@ViewBuilder private func caption(_ text: LocalizedStringKey)` helper.
- Staging: `SettingsBindings` holds prefs while the sheet is open; `ContentView.writeBack(_:)`
  persists them; `settingsSheetWritebacks(_:)` chains one
  `.onChange(of: bag.x) { _, _ in writeBack(bag) }` per staged key.
- Tests: Swift Testing, `@Test` behaviour-named functions, isolated
  `UserDefaults` via `makeIsolatedDefaults()` (`CheckStitchTests/TestFixtures.swift`)
  for pure preference types; app-target/`ContentView` suites use
  `@MainActor @Suite(.serialized)` with an explicit `clearPreferences()` helper
  and `UserDefaults.standard` (`CheckStitchTests/SettingsBindingsTests.swift`).
- Fast check is `make test-unit`; the full gate is `bash scripts/test.sh`
  (run once, at the end).

---

## Phase 1: Interface subscreen — Appearance moves behind a new row (walking skeleton)

Thinnest end-to-end path: Settings → Interface → the appearance control still
works, now pushed instead of inline.

### Changes

#### 1. Interface subscreen
**File**: `CheckStitch/InterfaceSettingsView.swift`
**Action**: create

```swift
import SwiftUI

/// Interface preferences: appearance, text size, and (on iOS) the orientation
/// lock. Takes only the bindings it needs rather than the whole settings bag,
/// matching `BackgroundSettingsView`.
struct InterfaceSettingsView: View {
    @Binding var appearanceMode: AppearanceMode

    var body: some View {
        Form {
            Picker(selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("Appearance")
                    caption("Choose between system, light, and dark mode.")
                }
            }
            .accessibilityIdentifier("appearancePicker")
        }
        .navigationTitle("Interface")
        .settingsSubscreenLayout()
    }

    @ViewBuilder
    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    NavigationStack {
        InterfaceSettingsView(appearanceMode: .constant(AppearanceMode.system))
    }
}
```

#### 2. Settings row
**File**: `CheckStitch/SettingsView.swift`
**Action**: modify

Replace the whole first `Section { Picker(…) }` (the inline appearance picker,
currently the body's first section) with the Interface navigation row, and
update the type's doc comment to say it holds the Interface row over the staged
bag:

```swift
                Section {
                    NavigationLink {
                        InterfaceSettingsView(appearanceMode: $appearanceMode)
                    } label: {
                        Label("Interface", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("settingsInterfaceRow")
                }
```

`appearanceMode` stays a direct `@Binding` on `SettingsView` (it is still needed
for the macOS `.preferredColorScheme` at the bottom of `body`) — do not move it
into the bag.

#### 3. Localization
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Add one entry, `"Interface"`, matching the existing entry shape
(`"extractionState" : "manual"`, one `stringUnit` with `"state" : "translated"`
per language), in the file's alphabetical position:

- en: `Interface`, de: `Oberfläche`, es: `Interfaz`, fr: `Interface`,
  ja: `インターフェース`, zh-Hans: `界面`

(`Appearance` and `Choose between system, light, and dark mode.` already exist —
do not re-add them.)

#### 4. Localization fixture (canary exclusion + required key)
**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

- Add `"Interface",` to the `App` list in `requiredKeys` (alphabetical position).
- Add to `excludedIdentities`, with a comment:

```swift
        // fr "Interface" — same spelling as English
        ExclusionEntry(catalog: "App", key: "Interface"),
```

#### 5. Tests
**File**: `CheckStitchTests/InterfaceSettingsViewTests.swift`
**Action**: create

```swift
@testable import CheckStitch
import SwiftUI
import Testing

/// The Interface subscreen renders its controls and stays compilable on both
/// platforms (`settingsSubscreenLayout()` is the macOS-only canary).
@MainActor
struct InterfaceSettingsViewTests {
    @Test
    func interfaceSubscreenRendersAppearance() {
        let view = InterfaceSettingsView(appearanceMode: .constant(AppearanceMode.system))
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("Appearance"))
        #expect(bodyDescription.contains("Choose between system, light, and dark mode."))
        #if os(macOS)
            #expect(bodyDescription.contains("SettingsSubscreenLayout"))
        #endif
    }

    @Test
    func interfaceSubscreenRendersAtAllAppearanceModes() {
        for mode in CheckStitch.AppearanceMode.allCases {
            let view = InterfaceSettingsView(appearanceMode: .constant(mode))
            #expect(!String(describing: view.body).isEmpty)
        }
    }
}
```

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `make build` (iOS simulator) succeeds — proves the new app-target file compiles for iOS
- [x] `make build-mac` succeeds — proves it compiles for macOS too
- [x] `bash scripts/tests/run.sh` passes (unchanged, sanity)

#### Manual
- [ ] `make run`: gear → Settings now shows an **Interface** row; tapping it
      pushes a screen titled "Interface" holding the Appearance picker; picking
      **Dark** still applies app-wide and survives dismissal.

---

## Phase 2: Text Size — picker scales text app-wide

### Changes

#### 1. Text size enum
**File**: `CheckStitch/TextSize.swift`
**Action**: create

```swift
import SwiftUI

// MARK: - TextSize

/// User-selectable text size preference, persisted in `UserDefaults` via
/// `@AppStorage`. Follows the same `String, CaseIterable` pattern as
/// ``AppearanceMode`` so it slots into the Interface picker.
enum TextSize: String, CaseIterable {
    case system
    case small
    case medium
    case large
    case extraLarge

    // MARK: Internal

    /// The `DynamicTypeSize` to apply, or `nil` to follow the system.
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: nil
        case .small: .small
        case .medium: .medium
        case .large: .xLarge
        case .extraLarge: .xxxLarge
        }
    }

    /// SF Symbol shown alongside the label in the text-size picker.
    var systemImage: String {
        switch self {
        case .system: "textformat.size"
        case .small: "textformat.size.smaller"
        case .medium: "textformat.size"
        case .large: "textformat.size.larger"
        case .extraLarge: "textformat.size.larger"
        }
    }

    /// Human-readable label shown in the text-size picker.
    var title: String {
        switch self {
        case .system: String(localized: "System", table: "Localizable", bundle: .main)
        case .small: String(localized: "Small", table: "Localizable", bundle: .main)
        case .medium: String(localized: "Medium", table: "Localizable", bundle: .main)
        case .large: String(localized: "Large", table: "Localizable", bundle: .main)
        case .extraLarge: String(localized: "Extra Large", table: "Localizable", bundle: .main)
        }
    }
}
```

#### 2. Text size modifier
**File**: `CheckStitch/TextSizeModifier.swift`
**Action**: create

```swift
import SwiftUI

// MARK: - TextSizeModifier

/// Conditionally applies ``TextSize`` to the view hierarchy. When the user
/// selects `.system`, no `dynamicTypeSize` override is applied so the view
/// follows the system Dynamic Type setting.
struct TextSizeModifier: ViewModifier {
    let textSize: TextSize

    func body(content: Content) -> some View {
        if let size = textSize.dynamicTypeSize {
            content.dynamicTypeSize(size)
        } else {
            content
        }
    }
}
```

#### 3. Staged pref
**File**: `CheckStitch/SettingsBindings.swift`
**Action**: modify

Add `textSize: TextSize = .system` as the **last** init parameter (after
`backgroundPinned`) and `var textSize: TextSize` as the last property, and
extend the doc comment to mention the staged interface keys.

#### 4. Root plumbing
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

- After `@AppStorage("backgroundPinned") var backgroundPinned = false` add:

```swift
    @AppStorage("textSize") var textSize = TextSize.system
```

- Apply the modifier to the root `ZStack` — insert between the ZStack's closing
  brace and the following `.task {` (the anchor is
  `        }` / `        .task {` right after the iOS overlay `#endif`):

```swift
        }
        .modifier(TextSizeModifier(textSize: textSize))
        .task {
```

- In `settingsSheetWritebacks(_:)` add, alongside the background `onChange`s:

```swift
            .onChange(of: bag.textSize) { _, _ in writeBack(bag) }
```

- In `writeBack(_:)` add `textSize = bag.textSize`; in `makeSettingsBag()` pass
  `textSize: textSize`.

#### 5. Picker row
**File**: `CheckStitch/InterfaceSettingsView.swift`
**Action**: modify

Add `@Binding var textSize: TextSize` after the appearance binding, and this
picker directly after the appearance picker in the `Form`:

```swift
            Picker(selection: $textSize) {
                ForEach(TextSize.allCases, id: \.self) { size in
                    Label(size.title, systemImage: size.systemImage)
                        .tag(size)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("Text Size")
                    caption("Adjust the size of text throughout the app.")
                }
            }
            .accessibilityIdentifier("textSizePicker")
```

Update the `#Preview` to pass `textSize: .constant(.system)`.

#### 6. Pass the binding through
**File**: `CheckStitch/SettingsView.swift`
**Action**: modify

In the Interface `NavigationLink` destination add
`textSize: $bindings.textSize` after `appearanceMode: $appearanceMode`.

#### 7. Localization
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Add these entries (same shape as Phase 1; `System` already exists — reuse it,
do not add it), one per language en/de/es/fr/ja/zh-Hans:

| key | de | es | fr | ja | zh-Hans |
| --- | --- | --- | --- | --- | --- |
| `Text Size` | Textgröße | Tamaño de texto | Taille du texte | テキストサイズ | 文字大小 |
| `Small` | Klein | Pequeño | Petit | 小 | 小 |
| `Medium` | Mittel | Mediano | Moyen | 中 | 中 |
| `Large` | Groß | Grande | Grand | 大 | 大 |
| `Extra Large` | Extra groß | Extra grande | Très grand | 特大 | 特大 |
| `Adjust the size of text throughout the app.` | Passe die Textgröße in der gesamten App an. | Ajusta el tamaño del texto en toda la app. | Ajustez la taille du texte dans toute l'app. | アプリ全体のテキストサイズを調整します。 | 调整整个应用中的文字大小。 |

#### 8. Localization fixture
**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add the six new keys to the `App` list in `requiredKeys`, in alphabetical
position (`Adjust the size of text throughout the app.`, `Extra Large`, `Large`,
`Medium`, `Small`, `Text Size`). No new `excludedIdentities` entries: every new
translation above differs from English.

#### 9. Tests
**File**: `CheckStitchTests/TextSizeTests.swift`
**Action**: create

```swift
@testable import CheckStitch
import SwiftUI
import Testing

struct TextSizeTests {
    @Test
    func dynamicTypeSizeMapsEachCase() {
        #expect(TextSize.system.dynamicTypeSize == nil)
        #expect(TextSize.small.dynamicTypeSize == .small)
        #expect(TextSize.medium.dynamicTypeSize == .medium)
        #expect(TextSize.large.dynamicTypeSize == .xLarge)
        #expect(TextSize.extraLarge.dynamicTypeSize == .xxxLarge)
    }

    @Test
    func allCasesAreOrderedAndUnique() {
        #expect(TextSize.allCases.map(\.rawValue) ==
            ["system", "small", "medium", "large", "extraLarge"])
        #expect(Set(TextSize.allCases.map(\.rawValue)).count == TextSize.allCases.count)
    }

    @Test
    func titlesAndSymbolsResolveThroughTheAppCatalog() {
        // Same pinned-locale approach as ViewRenderTests' appearance assertion.
        #expect(TextSize.allCases.map(\.title) ==
            ["System", "Small", "Medium", "Large", "Extra Large"])
        #expect(TextSize.allCases.map(\.systemImage).allSatisfy { !$0.isEmpty })
    }

    @Test
    func unknownRawValueDoesNotResolve() {
        // `@AppStorage` falls back to the declared default for a bad string.
        #expect(TextSize(rawValue: "gigantic") == nil)
        #expect(TextSize(rawValue: "extraLarge") == .extraLarge)
    }
}
```

**File**: `CheckStitchTests/SettingsBindingsTests.swift`
**Action**: modify

- `defaultsMatchPreferenceDefaults`: add `#expect(bag.textSize == .system)`.
- `snapshotReadsCurrentUserDefaults`: set
  `UserDefaults.standard.set("large", forKey: "textSize")` and assert
  `bag.textSize == .large`.
- `writeBackPersistsEachKey`: build the bag with `textSize: .extraLarge` and
  assert `UserDefaults.standard.string(forKey: "textSize") == "extraLarge"`.
- `clearPreferences()`: add `"textSize"` to the keys it removes.

**File**: `CheckStitchTests/InterfaceSettingsViewTests.swift`
**Action**: modify

Extend the render assertion to `#expect(bodyDescription.contains("Text Size"))`
and pass `textSize: .constant(.system)` in both tests.

### Verification
#### Automated
- [x] `make test-unit` passes (TextSize mapping + titles, bag staging/write-back, render)
- [x] `make build` and `make build-mac` both succeed
- [x] `bash scripts/tests/run.sh` passes

#### Manual
- [ ] `make run`: Interface → **Text Size** = Extra Large grows all app text
      (checklist rows, Settings itself); **System** restores the device size.
- [ ] Kill and relaunch the app: the chosen size is still applied.
- [ ] macOS (`make build-mac-signed` / run the macOS app): the Text Size picker
      is present and changes the macOS window's text too.

---

## Phase 3: Allow landscape — iOS-only orientation lock

### Changes

#### 1. Orientation preference + policy
**File**: `CheckStitch/OrientationPreference.swift`
**Action**: create

```swift
import Foundation
#if os(iOS)
    import UIKit
#endif

// MARK: - OrientationPreference

/// Persists the "allow landscape" preference in `UserDefaults.standard`.
///
/// This key is read at launch by `AppDelegate` before any SwiftUI view exists
/// (so the persisted lock takes effect without a wrong-orientation flash),
/// hence plain `UserDefaults` rather than the App Group suite. An absent key
/// resolves to `true` — landscape enabled, which is the Info.plist default.
struct OrientationPreference {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Internal

    /// Single shared key used by `AppDelegate`, `@AppStorage`, and settings.
    static let defaultsKey = "allowsLandscape"

    /// Whether landscape orientation is enabled. `nil` (missing key) → `true`.
    var isLandscapeEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    func setLandscapeEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}

// MARK: - OrientationPolicy

/// Which orientations the app allows, derived from ``OrientationPreference``.
///
/// Deliberately cross-platform so the selection logic is unit-testable on the
/// macOS-hosted suite; the UIKit mask lives in the iOS-only extension below.
enum OrientationPolicy: String, CaseIterable {
    case portrait
    case allButUpsideDown

    init(allowsLandscape: Bool) {
        self = allowsLandscape ? .allButUpsideDown : .portrait
    }
}

#if os(iOS)
    extension OrientationPolicy {
        var mask: UIInterfaceOrientationMask {
            switch self {
            case .portrait: .portrait
            case .allButUpsideDown: .allButUpsideDown
            }
        }
    }
#endif
```

#### 2. Platform bridge
**File**: `CheckStitch/AppDelegate.swift`
**Action**: modify

Inside the existing `#if os(iOS)` `AppDelegate`, add (and extend the class doc
comment to mention the orientation lock):

```swift
        /// Re-evaluates the orientation lock and requests an immediate rotation
        /// if the current orientation violates the new mask.
        ///
        /// Call this from SwiftUI when the `allowsLandscape` toggle changes.
        /// On iPad in Split View or Slide Over the request may be denied
        /// (`Code=101`), but the mask still prevents auto-rotation.
        static func applyLock(allowsLandscape: Bool) {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let controller = scene.keyWindow?.rootViewController
            else { return }

            controller.setNeedsUpdateOfSupportedInterfaceOrientations()
            let mask = OrientationPolicy(allowsLandscape: allowsLandscape).mask
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                print("Orientation request failed: \(error.localizedDescription)")
            }
        }

        func application(
            _: UIApplication,
            supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
            OrientationPolicy(
                allowsLandscape: OrientationPreference().isLandscapeEnabled).mask
        }
```

The macOS `MacAppDelegate` is not touched.

#### 3. Staged pref
**File**: `CheckStitch/SettingsBindings.swift`
**Action**: modify

Add `allowsLandscape: Bool = true` as the **last** init parameter and
`var allowsLandscape: Bool` as the last property.

#### 4. Root plumbing
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

- After the `textSize` `@AppStorage` added in Phase 2 add:

```swift
    @AppStorage("allowsLandscape") var allowsLandscape = true
```

- After the `.onChange(of: appearanceMode) { … }` block, add:

```swift
            .onChange(of: allowsLandscape) { _, new in
                #if os(iOS)
                    AppDelegate.applyLock(allowsLandscape: new)
                #endif
            }
```

- In `settingsSheetWritebacks(_:)` add
  `.onChange(of: bag.allowsLandscape) { _, _ in writeBack(bag) }`; in
  `writeBack(_:)` add `allowsLandscape = bag.allowsLandscape`; in
  `makeSettingsBag()` pass `allowsLandscape: allowsLandscape`.

#### 5. Toggle row
**File**: `CheckStitch/InterfaceSettingsView.swift`
**Action**: modify

Add, above the closing brace of the `Form`, after the text-size picker:

```swift
            #if os(iOS)
                Toggle(isOn: $allowsLandscape) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Allow landscape")
                            caption("Let the app rotate on iPhone.")
                        }
                    } icon: {
                        Image(systemName: "rectangle.landscape.rotate")
                    }
                }
                .accessibilityIdentifier("allowLandscapeToggle")
            #endif
```

Add the binding declarations alongside the others:

```swift
    #if os(iOS)
        @Binding var allowsLandscape: Bool
    #endif
```

Update `#Preview` so the iOS branch passes `allowsLandscape: .constant(true)`
(`#if os(iOS)` inside the preview, as SingleThread does) and the macOS branch
omits it.

#### 6. Pass the binding through
**File**: `CheckStitch/SettingsView.swift`
**Action**: modify

The Interface `NavigationLink` destination gains the iOS-only argument:

```swift
                    NavigationLink {
                        InterfaceSettingsView(
                            appearanceMode: $appearanceMode,
                            textSize: $bindings.textSize,
                            #if os(iOS)
                                allowsLandscape: $bindings.allowsLandscape,
                            #endif
                        )
                    } label: {
```

#### 7. Localization
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

| key | en | de | es | fr | ja | zh-Hans |
| --- | --- | --- | --- | --- | --- | --- |
| `Allow landscape` | Allow landscape | Querformat erlauben | Permitir modo horizontal | Autoriser le mode paysage | 横向きを許可 | 允许横屏 |
| `Let the app rotate on iPhone.` | Let the app rotate on iPhone. | Erlaube der App die Drehung auf dem iPhone. | Permite que la app gire en el iPhone. | Autorisez la rotation de l'app sur iPhone. | iPhone でアプリの回転を許可します。 | 允许应用在 iPhone 上旋转。 |

#### 8. Localization fixture
**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add `"Allow landscape"` and `"Let the app rotate on iPhone."` to the `App` list
in `requiredKeys`. No new exclusions.

#### 9. Tests
**File**: `CheckStitchTests/OrientationPreferenceTests.swift`
**Action**: create

```swift
@testable import CheckStitch
import Foundation
import Testing

struct OrientationPreferenceTests {
    @Test
    func missingKeyDefaultsToLandscapeEnabled() {
        let defaults = makeIsolatedDefaults()
        // Sad path: no stored value at all.
        #expect(OrientationPreference(defaults: defaults).isLandscapeEnabled)
    }

    @Test
    func storedValueRoundTrips() {
        let defaults = makeIsolatedDefaults()
        let preference = OrientationPreference(defaults: defaults)
        preference.setLandscapeEnabled(false)
        #expect(!preference.isLandscapeEnabled)
        preference.setLandscapeEnabled(true)
        #expect(preference.isLandscapeEnabled)
    }

    @Test
    func nonBooleanStoredValueFallsBackToEnabled() {
        let defaults = makeIsolatedDefaults()
        defaults.set("yes", forKey: OrientationPreference.defaultsKey)
        #expect(OrientationPreference(defaults: defaults).isLandscapeEnabled)
    }

    @Test
    func policySelectsTheLockForEachToggleValue() {
        // Platform-agnostic stand-in for the UIKit mask: the mask conversion
        // (`OrientationPolicy.mask`) is iOS-only and exercised manually.
        #expect(OrientationPolicy(allowsLandscape: true) == .allButUpsideDown)
        #expect(OrientationPolicy(allowsLandscape: false) == .portrait)
        #expect(OrientationPolicy.allCases.map(\.rawValue) == ["portrait", "allButUpsideDown"])
    }
}
```

**File**: `CheckStitchTests/SettingsBindingsTests.swift`
**Action**: modify

- `defaultsMatchPreferenceDefaults`: add `#expect(bag.allowsLandscape)`.
- `snapshotReadsCurrentUserDefaults`: set
  `UserDefaults.standard.set(false, forKey: "allowsLandscape")` and assert
  `!bag.allowsLandscape`.
- `writeBackPersistsEachKey`: build the bag with `allowsLandscape: false` and
  assert `UserDefaults.standard.bool(forKey: "allowsLandscape") == false`.
- `clearPreferences()`: add `"allowsLandscape"` to the keys it removes.

**File**: `CheckStitchTests/InterfaceSettingsViewTests.swift`
**Action**: modify

Extend the render assertion to include `"Interface"`; keep the iOS-only toggle
assertions out of the suite (this suite runs on macOS — the row's presence on
iPhone is a manual check below).

### Verification
#### Automated
- [x] `make test-unit` passes (preference default/round-trip, policy selection, bag write-back, render)
- [x] `make build` (iOS simulator), `make build-mac`, `make watch-build` all succeed
- [x] `bash scripts/test.sh` prints `gate: ok` — the single full gate run for this branch

#### Manual
- [ ] `make run` on the iPhone simulator: Interface shows **Allow landscape**
      (ON by default). Rotate with ⌘←/⌘→ → the app rotates.
- [ ] Toggle **Allow landscape** off → the app immediately snaps back to
      portrait and no longer rotates; toggle on → it rotates again.
- [ ] Relaunch the app with the toggle off: it launches in portrait with no
      landscape flash, and Rotation Lock-independent ⌘→ does nothing.
- [ ] macOS app: no landscape row on the Interface screen; Text Size still applies.

---

## Out of scope (do not touch)

- `CheckStitchCore`, the watch target, and the watch catalog.
- `project.pbxproj`, `Info.plist` build settings, `AppGroup.entitlements`.
- The macOS window-clamp behaviour in `MacAppDelegate`.
- Any refactor of the `SettingsBindings` staging mechanism or the settings
  sheet's import/export queue.
