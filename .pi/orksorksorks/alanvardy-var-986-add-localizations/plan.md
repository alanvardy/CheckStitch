# Implementation Plan

## Overview

Introduce string-catalog localization (de, en, es, fr, ja, zh-Hans) to
CheckStitch: one `Localizable.xcstrings` per target (app, watch, core package),
typed core string access via `SharedStrings` + `Bundle.module`, per-language
`.lproj/InfoPlist.strings`, and a `LocalizationTests` suite that parses the
catalogs from the source tree and proves six-language completeness. The full
gate (`bash scripts/test.sh` → `gate: ok`) stays green.

Work is ordered bottom-up in six phases. Every resource is added inside a
directory-synchronized root group, so **no pbxproj file references are added**;
the only pbxproj edits are `knownRegions` (Phase 1).

**Verification commands used throughout** (from `conventions.md`):

| Command | Scope |
|---|---|
| `make test-unit` | macOS-hosted unit tests, unsigned — the fast checkpoint |
| `make build` | iOS Simulator slice |
| `make build-mac` | macOS slice, unsigned |
| `make watch-build` | watchOS simulator compile of `CheckStitchWatch` |
| `bash scripts/test.sh` | the full gate, prints `gate: ok` |

**Working-tree note:** `SWIFT_EMIT_LOC_STRINGS = YES` is on for the app and
watch targets, so a build (re-)writes extracted keys into the catalogs. After
the first build in Phase 2, run `git status` / `git diff` on the three
`Localizable.xcstrings` files and adopt Xcode's canonical output (it may set
`extractionState` on entries and sort keys). Any *new* key Xcode extracts must
be given all six translations before the completeness tests go green.

**Key-identity note:** catalogs use the English source text as the key (no
renaming), except for the three interpolation-derived keys
`%lld%%`, `Photo by %@ on Unsplash`, and
`Another checklist already uses %@ — choose a different name.`

---

## Phase 1: Foundation — resource plumbing, test harness, language registration

Delivers everything later phases compile and assert against: the core package
compiles its catalog into `Bundle.module`, the test target has locale-pinned
lookup helpers and a catalog parser, and Xcode knows the six languages.

### Changes

#### 1. Core package declares its resource directory
**File**: `CheckStitchCore/Package.swift`
**Action**: modify

```swift
    targets: [
        .target(
            name: "CheckStitchCore",
            resources: [.process("Resources")])
    ])
```

Without this the catalog never reaches `Bundle.module`. The `Resources`
directory must exist in the same commit (step 3) or SPM errors.

#### 2. Register the six languages
**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify (`knownRegions`, ~line 260)

```
			knownRegions = (
				en,
				Base,
				de,
				es,
				fr,
				ja,
				zh-Hans,
			);
```

#### 3. Skeleton catalogs
**Files**: `CheckStitch/Localizable.xcstrings`, `CheckStitchWatch/Localizable.xcstrings`, `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`
**Action**: create

Each is a valid, empty catalog. `sourceLanguage: "en"`, nothing else:

```json
{
  "sourceLanguage" : "en",
  "strings" : {

  },
  "version" : "1.0"
}
```

(Exact whitespace does not matter; Xcode rewrites it on the first build.)

#### 4. Test helpers + catalog reader
**File**: `CheckStitchTests/LocalizationTestHelpers.swift`
**Action**: create

```swift
import Foundation

extension String {
    /// Localizes a key from the given bundle with the test suite's pinned locale,
    /// so unit tests assert deterministic English output regardless of host locale.
    ///
    /// Takes a `String` (not `String.LocalizationValue`) so argument-driven and
    /// table-driven tests can pass runtime keys.
    static func en(_ key: String, bundle: Bundle, table: String = "Localizable") -> String {
        String(localized: String.LocalizationValue(key), table: table, bundle: bundle,
               locale: Locale(identifier: "en"))
    }
}

extension Bundle {
    /// Resolves a Swift-package resource bundle embedded in `parent`. Xcode names
    /// them `<PackageName>_<TargetName>.bundle` and embeds them in the app bundle.
    static func resourceBundle(named name: String, in parent: Bundle = .main) -> Bundle? {
        guard let url = parent.url(forResource: name, withExtension: "bundle") else { return nil }
        return Bundle(url: url)
    }

    /// The CheckStitchCore resource bundle as embedded in the app that hosts the
    /// test runner. The tests cannot use the package-only `Bundle.module`.
    /// Fails loudly rather than falling back to `.main`: a silent fallback would
    /// let key-equal-value assertions pass with a missing resource bundle,
    /// masking a packaging regression.
    static var core: Bundle {
        guard let core = resourceBundle(named: "CheckStitchCore_CheckStitchCore") else {
            preconditionFailure("CheckStitchCore_CheckStitchCore.bundle is not embedded in the test host")
        }
        return core
    }
}

/// A key identity within a specific catalog, for the translation-canary exclusions.
struct ExclusionEntry: Hashable {
    let catalog: String
    let key: String
}

/// One parsed key from a `.xcstrings` catalog plus the value it supplies per language.
struct CatalogKey {
    let catalog: String
    let key: String
    let localizations: [String: String]
}

enum CatalogLoadError: Error, Equatable {
    /// The file is not JSON, has no `strings` object, or is otherwise unreadable.
    case malformed(catalog: String)
}

/// Reads the `.xcstrings` catalogs straight from the source tree: they live in
/// directory-synchronized folders, so `#filePath` resolves to the checkout path
/// and no bundle lookup is needed.
enum Catalogs {
    static let languages = ["en", "de", "es", "fr", "ja", "zh-Hans"]
    static let nonEnglishLanguages = ["de", "es", "fr", "ja", "zh-Hans"]

    /// Repo root, derived from this file's path (`CheckStitchTests/` → up one).
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CheckStitchTests/
        .deletingLastPathComponent() // repo root

    /// The three catalogs under test.
    static let all: [(name: String, url: URL)] = [
        ("App", repoRoot.appendingPathComponent("CheckStitch/Localizable.xcstrings")),
        ("Watch", repoRoot.appendingPathComponent("CheckStitchWatch/Localizable.xcstrings")),
        ("Core", repoRoot.appendingPathComponent(
            "CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings")),
    ]

    static func url(forCatalog name: String) throws -> URL {
        guard let match = all.first(where: { $0.name == name }) else {
            throw CatalogLoadError.malformed(catalog: name)
        }
        return match.url
    }

    /// Every key of every catalog, in catalog order.
    static func loadAll() throws -> [CatalogKey] {
        try all.flatMap { try load(contentsOf: $0.url, catalog: $0.name) }
    }

    static func load(contentsOf url: URL, catalog: String) throws -> [CatalogKey] {
        try load(data: Data(contentsOf: url), catalog: catalog)
    }

    static func load(data: Data, catalog: String) throws -> [CatalogKey] {
        let object = try? JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let strings = root["strings"] as? [String: Any]
        else { throw CatalogLoadError.malformed(catalog: catalog) }

        return strings.keys.sorted().map { key in
            let entry = strings[key] as? [String: Any] ?? [:]
            let rawLocalizations = entry["localizations"] as? [String: Any] ?? [:]
            var values: [String: String] = [:]
            for (language, raw) in rawLocalizations {
                guard let raw = raw as? [String: Any],
                      let unit = raw["stringUnit"] as? [String: Any],
                      let value = unit["value"] as? String
                else { continue }
                values[language] = value
            }
            return CatalogKey(catalog: catalog, key: key, localizations: values)
        }
    }
}
```

#### 5. Test fixtures
**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: create

```swift
import Foundation

/// Shared expectations for the localization suites.
enum LocalizationFixtures {
    /// Catalogs guarded by the non-English-differs canary.
    static let guardedCatalogs: Set<String> = ["App", "Core"]

    /// Every key each catalog must carry. Guards against a key being dropped
    /// from the catalog (the UI would then render the raw key at runtime).
    static let requiredKeys: [(catalog: String, keys: [String])] = [
        ("App", [
            "%lld%%",
            "Add Item",
            "Another checklist already uses %@ — choose a different name.",
            "Appearance",
            "Background",
            "Background Fade",
            "Checklist name",
            "Checklist not found",
            "Choose between system, light, and dark mode.",
            "Create a checklist to turn its items into reminders.",
            "Create checklist",
            "Create reminders from checklist",
            "Dark",
            "Done",
            "Edit checklist",
            "How much the wallpaper fades for readability.",
            "Item",
            "Items",
            "Light",
            "Name",
            "Name already in use",
            "No checklists",
            "OK",
            "Photo by %@ on Unsplash",
            "Pin wallpaper",
            "Prevents the background from refreshing automatically.",
            "Refresh wallpaper",
            "Remove Checklist",
            "Settings",
            "Show a wallpaper behind the checklist.",
            "System",
        ]),
        ("Core", ["System", "Light", "Dark"]),
        ("Watch", [
            "No checklists",
            "Open CheckStitch on your iPhone.",
            "Checklists",
            "Sent",
            "Create reminders",
        ]),
    ]

    /// Per-target `InfoPlist.strings` files and the keys each must carry.
    ///
    /// The watch target carries no reminders usage description: the watch never
    /// touches EventKit (it forwards run requests to the phone via
    /// `WatchChecklistStore`, `CheckStitchCore/.../ChecklistSync.swift:65-95`),
    /// so its generated Info.plist has no such key.
    static let infoPlistTargets: [(name: String, path: String, keys: [String])] = [
        ("App", "CheckStitch", [
            "NSRemindersFullAccessUsageDescription",
            "NSRemindersUsageDescription",
            "CFBundleDisplayName",
        ]),
        ("Watch", "CheckStitchWatch", [
            "CFBundleDisplayName",
        ]),
    ]

    /// Keys whose non-English value may be byte-identical to the English source.
    static let excludedIdentities: Set<ExclusionEntry> = [
        // de "System" — standard German computing term, same spelling as English
        ExclusionEntry(catalog: "App", key: "System"),
        ExclusionEntry(catalog: "Core", key: "System"),
        // de "Name" — same spelling as English
        ExclusionEntry(catalog: "App", key: "Name"),
        // "OK" — same in de/es/fr/ja
        ExclusionEntry(catalog: "App", key: "OK"),
        // percent format string is locale-invariant
        ExclusionEntry(catalog: "App", key: "%lld%%"),
    ]

    /// Keys that are absent or empty in `plist`. Extracted so the incomplete-plist
    /// sad path is testable without a crashing fixture.
    static func missingInfoPlistKeys(in plist: [String: String], required: [String]) -> [String] {
        required.filter { plist[$0]?.isEmpty != false }
    }
}
```

#### 6. Localization suites
**File**: `CheckStitchTests/LocalizationTests.swift`
**Action**: create

Phase 1 ships only the parser proof; Phase 2 adds the content assertions.

```swift
import Foundation
import Testing

/// Validates the string-catalog and InfoPlist.strings resource layer.
/// Catalogs are read from the source tree (synchronized folder groups), so
/// `#filePath` resolves to the checkout's source path; no bundle lookup is needed.
struct LocalizationTests {
    @Test
    func catalogsParse() throws {
        let catalogs = try Catalogs.loadAll()
        #expect(catalogs.count >= Catalogs.all.count)
    }

    @Test
    func malformedCatalogThrows() {
        #expect(throws: CatalogLoadError.malformed(catalog: "Broken")) {
            try Catalogs.load(data: Data("{ not json".utf8), catalog: "Broken")
        }
        // Valid JSON, but no `strings` object.
        #expect(throws: CatalogLoadError.malformed(catalog: "Broken")) {
            try Catalogs.load(data: Data(#"{"sourceLanguage":"en"}"#.utf8), catalog: "Broken")
        }
    }

    @Test
    func missingResourceBundleResolvesToNil() {
        #expect(Bundle.resourceBundle(named: "CheckStitchCore_DoesNotExist") == nil)
    }
}
```

### Verification
#### Automated
- [x] `make test-unit` passes (`catalogsParse`, `malformedCatalogThrows`, `missingResourceBundleResolvesToNil`, existing `SmokeTests`/`HarnessTests`)
- [x] `make build` compiles with the package resource change
- [x] `make build-mac` compiles
- [x] `make watch-build` compiles
- [x] `git status` shows no pbxproj changes beyond `knownRegions`

#### Manual
- [ ] Inspect the built products and confirm `CheckStitchCore_CheckStitchCore.bundle` is embedded inside the built `CheckStitch.app` (macOS: `CheckStitch.app/Contents/Resources/`)

---

## Phase 2: Catalog content — all keys × six languages

Populates the three catalogs with the full inventory and all six translations,
and turns on the completeness / canary assertions.

### Changes

#### 1. Author the app catalog
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Every key uses this exact shape (`state` is always `"translated"`; the file is
UTF-8 and Xcode's writer uses 2-space indentation):

```json
    "System" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "System"
          }
        },
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "System"
          }
        },
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sistema"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Système"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "システム"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "系统"
          }
        }
      }
    },
```

All 31 keys (English = the key itself). Columns are the translation per language:

| Key | de | es | fr | ja | zh-Hans |
|---|---|---|---|---|---|
| `%lld%%` | `%lld%%` | `%lld%%` | `%lld%%` | `%lld%%` | `%lld%%` |
| `Add Item` | Eintrag hinzufügen | Añadir elemento | Ajouter un élément | 項目を追加 | 添加项目 |
| `Another checklist already uses %@ — choose a different name.` | Eine andere Checkliste verwendet bereits %@ – wähle einen anderen Namen. | Otra lista ya usa %@ — elige otro nombre. | Une autre liste utilise déjà %@ — choisissez un autre nom. | 別のチェックリストがすでに %@ を使用しています。別の名前を選んでください。 | 另一个清单已使用 %@ — 请选择其他名称。 |
| `Appearance` | Darstellung | Apariencia | Apparence | 外観 | 外观 |
| `Background` | Hintergrund | Fondo | Arrière-plan | 背景 | 背景 |
| `Background Fade` | Hintergrund-Ausblendung | Atenuación del fondo | Atténuation de l'arrière-plan | 背景のフェード | 背景淡出 |
| `Checklist name` | Name der Checkliste | Nombre de la lista | Nom de la liste | チェックリスト名 | 清单名称 |
| `Checklist not found` | Checkliste nicht gefunden | Lista no encontrada | Liste introuvable | チェックリストが見つかりません | 找不到清单 |
| `Choose between system, light, and dark mode.` | Wähle zwischen System-, Hell- und Dunkelmodus. | Elige entre modo del sistema, claro y oscuro. | Choisissez entre le mode système, clair et sombre. | システム、ライト、ダークモードから選択します。 | 在系统、浅色和深色模式之间选择。 |
| `Create a checklist to turn its items into reminders.` | Erstelle eine Checkliste, um ihre Einträge in Erinnerungen umzuwandeln. | Crea una lista para convertir sus elementos en recordatorios. | Créez une liste pour transformer ses éléments en rappels. | チェックリストを作成すると、項目がリマインダーになります。 | 创建清单，将其中的项目转换为提醒事项。 |
| `Create checklist` | Checkliste erstellen | Crear lista | Créer une liste | チェックリストを作成 | 创建清单 |
| `Create reminders from checklist` | Erinnerungen aus Checkliste erstellen | Crear recordatorios desde la lista | Créer des rappels à partir de la liste | チェックリストからリマインダーを作成 | 从清单创建提醒事项 |
| `Dark` | Dunkel | Oscuro | Sombre | ダーク | 深色 |
| `Done` | Fertig | Listo | Terminé | 完了 | 完成 |
| `Edit checklist` | Checkliste bearbeiten | Editar lista | Modifier la liste | チェックリストを編集 | 编辑清单 |
| `How much the wallpaper fades for readability.` | Wie stark das Hintergrundbild für bessere Lesbarkeit ausgeblendet wird. | Cuánto se atenúa el fondo para mejorar la legibilidad. | Dans quelle mesure le fond d'écran s'atténue pour la lisibilité. | 読みやすさのために壁紙をどれだけフェードさせるかを設定します。 | 为提高可读性，壁纸淡出的程度。 |
| `Item` | Eintrag | Elemento | Élément | 項目 | 项目 |
| `Items` | Einträge | Elementos | Éléments | 項目 | 项目 |
| `Light` | Hell | Claro | Clair | ライト | 浅色 |
| `Name` | Name | Nombre | Nom | 名前 | 名称 |
| `Name already in use` | Name bereits verwendet | Nombre ya en uso | Nom déjà utilisé | 名前はすでに使用されています | 名称已被使用 |
| `No checklists` | Keine Checklisten | Sin listas | Aucune liste | チェックリストがありません | 没有清单 |
| `OK` | OK | OK | OK | OK | 好 |
| `Photo by %@ on Unsplash` | Foto von %1$@ auf Unsplash | Foto de %1$@ en Unsplash | Photo de %1$@ sur Unsplash | Unsplash の %1$@ による写真 | 照片来自 Unsplash 的 %1$@ |
| `Pin wallpaper` | Hintergrundbild anheften | Fijar fondo | Épingler le fond d'écran | 壁紙を固定 | 固定壁纸 |
| `Prevents the background from refreshing automatically.` | Verhindert, dass der Hintergrund automatisch aktualisiert wird. | Evita que el fondo se actualice automáticamente. | Empêche l'actualisation automatique du fond d'écran. | 背景が自動的に更新されないようにします。 | 阻止背景自动刷新。 |
| `Refresh wallpaper` | Hintergrundbild aktualisieren | Actualizar fondo | Actualiser le fond d'écran | 壁紙を更新 | 刷新壁纸 |
| `Remove Checklist` | Checkliste entfernen | Eliminar lista | Supprimer la liste | チェックリストを削除 | 删除清单 |
| `Settings` | Einstellungen | Ajustes | Réglages | 設定 | 设置 |
| `Show a wallpaper behind the checklist.` | Zeigt ein Hintergrundbild hinter der Checkliste. | Muestra un fondo detrás de la lista. | Affiche un fond d'écran derrière la liste. | チェックリストの背景に壁紙を表示します。 | 在清单后面显示壁纸。 |
| `System` | System | Sistema | Système | システム | 系统 |

Notes:
- `%lld%%` (from `Text("\(percent)%")`) and `Photo by %@ on Unsplash` are format
  strings: keep every `%` specifier in the translation. Use `%1$@` to reorder.
- Language register is informal (`du`) in German, `tú` in Spanish, `vous` in
  French, standard polite forms in Japanese/Chinese — matching the reference
  project.

#### 2. Author the core catalog
**File**: `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`
**Action**: modify

Same entry shape as above. Exactly three keys:

| Key | de | es | fr | ja | zh-Hans |
|---|---|---|---|---|---|
| `System` | System | Sistema | Système | システム | 系统 |
| `Light` | Hell | Claro | Clair | ライト | 浅色 |
| `Dark` | Dunkel | Oscuro | Sombre | ダーク | 深色 |

#### 3. Author the watch catalog
**File**: `CheckStitchWatch/Localizable.xcstrings`
**Action**: modify

Same entry shape. Exactly five keys:

| Key | de | es | fr | ja | zh-Hans |
|---|---|---|---|---|---|
| `No checklists` | Keine Checklisten | Sin listas | Aucune liste | チェックリストがありません | 没有清单 |
| `Open CheckStitch on your iPhone.` | Öffne CheckStitch auf deinem iPhone. | Abre CheckStitch en tu iPhone. | Ouvrez CheckStitch sur votre iPhone. | iPhone で CheckStitch を開いてください。 | 在 iPhone 上打开 CheckStitch。 |
| `Checklists` | Checklisten | Listas | Listes | チェックリスト | 清单 |
| `Sent` | Gesendet | Enviado | Envoyé | 送信済み | 已发送 |
| `Create reminders` | Erinnerungen erstellen | Crear recordatorios | Créer des rappels | リマインダーを作成 | 创建提醒事项 |

#### 4. Turn on the completeness and canary suites
**File**: `CheckStitchTests/LocalizationTests.swift`
**Action**: modify

Replace `catalogsParse` and add the content tests:

```swift
    @Test
    func catalogsParseAndHaveNonEmptyEnglish() throws {
        for catalog in Catalogs.all {
            let keys = try Catalogs.load(contentsOf: catalog.url, catalog: catalog.name)
            #expect(!keys.isEmpty, "\(catalog.name) catalog has no keys")
        }
        for entry in try Catalogs.loadAll() {
            let english = try #require(
                entry.localizations["en"], "\(entry.catalog)/\(entry.key) missing en")
            #expect(!english.isEmpty, "\(entry.catalog)/\(entry.key) has empty en value")
        }
    }

    @Test
    func catalogsHaveAllSixLanguages() throws {
        for entry in try Catalogs.loadAll() {
            for language in Catalogs.languages {
                let value = try #require(
                    entry.localizations[language],
                    "\(entry.catalog)/\(entry.key) missing \(language)")
                #expect(!value.isEmpty, "\(entry.catalog)/\(entry.key) has empty \(language) value")
            }
        }
    }

    @Test
    func everyRequiredKeyIsPresent() throws {
        for requirement in LocalizationFixtures.requiredKeys {
            let keys = try Catalogs.load(
                contentsOf: try Catalogs.url(forCatalog: requirement.catalog),
                catalog: requirement.catalog)
            let present = Set(keys.map(\.key))
            let missing = requirement.keys.filter { !present.contains($0) }
            #expect(missing.isEmpty, "\(requirement.catalog) catalog missing: \(missing)")
        }
    }

    @Test
    func nonEnglishValuesDifferFromEnglish() throws {
        for entry in try Catalogs.loadAll() where LocalizationFixtures.guardedCatalogs.contains(entry.catalog) {
            guard let english = entry.localizations["en"] else { continue }
            if LocalizationFixtures.excludedIdentities.contains(
                ExclusionEntry(catalog: entry.catalog, key: entry.key)) { continue }
            for language in Catalogs.nonEnglishLanguages {
                guard let value = entry.localizations[language] else { continue }
                #expect(
                    value != english,
                    "\(entry.catalog)/\(entry.key) \(language) is identical to English: \"\(value)\"")
            }
        }
    }
```

### Verification
#### Automated
- [x] `make test-unit` — `catalogsParseAndHaveNonEmptyEnglish`, `catalogsHaveAllSixLanguages`, `everyRequiredKeyIsPresent`, `nonEnglishValuesDifferFromEnglish` all pass
- [x] If the canary fails on a `(catalog, key)` pair that is legitimately identical in one language, add that pair to `LocalizationFixtures.excludedIdentities` with a comment naming the language (the failure message names both) and re-run
- [x] `make build` then `git diff -- '*Localizable.xcstrings'` — adopt Xcode's canonical rewrite; if Xcode extracted a key that is not in the tables, add all six translations
- [x] `make build-mac`, `make watch-build` still compile

#### Manual
- [ ] Open each `.xcstrings` in Xcode (`open CheckStitch/Localizable.xcstrings`) and confirm the six languages appear with no "needs translation" markers

---

## Phase 3: Core string access — `SharedStrings` + localized `AppearanceMode`

Routes core-owned user-facing strings through the core catalog via
`Bundle.module`.

### Changes

#### 1. New typed string access
**File**: `CheckStitchCore/Sources/CheckStitchCore/SharedStrings.swift`
**Action**: create

```swift
import Foundation

/// Centralized, typed access to the Core package's user-facing strings. Every
/// value resolves through `Bundle.module` (the package's compiled
/// `Localizable.xcstrings`), never a caller's bundle.
public enum SharedStrings {
    public static var system: String {
        String(localized: "System", table: "Localizable", bundle: .module)
    }

    public static var light: String {
        String(localized: "Light", table: "Localizable", bundle: .module)
    }

    public static var dark: String {
        String(localized: "Dark", table: "Localizable", bundle: .module)
    }
}
```

#### 2. Core `AppearanceMode.title` reads the catalog
**File**: `CheckStitchCore/Sources/CheckStitchCore/AppearanceMode.swift`
**Action**: modify (`title`, ~lines 68-76)

```swift
    /// Human-readable label shown in the appearance picker.
    public var title: String {
        switch self {
        case .system: SharedStrings.system
        case .light: SharedStrings.light
        case .dark: SharedStrings.dark
        }
    }
```

Persisted defaults (`"New checklist"`, `"New item"`, `"one"/"two"/"three"`,
`"checklist"`) are **not** localized (Design Decision 2) and stay untouched.

#### 3. Prove the compiled core bundle is embedded and localized
**File**: `CheckStitchTests/LocalizationTests.swift`
**Action**: modify

Add — this is the test that distinguishes a real `Bundle.module` lookup from
the key-equals-value fallback:

```swift
    @Test
    func coreCatalogValuesAreEmbeddedInTheResourceBundle() throws {
        let coreKeys = try Catalogs.load(
            contentsOf: try Catalogs.url(forCatalog: "Core"), catalog: "Core")
        let dark = try #require(coreKeys.first { $0.key == "Dark" })
        let german = String(
            localized: "Dark", table: "Localizable", bundle: .core,
            locale: Locale(identifier: "de"))
        #expect(german == dark.localizations["de"], "Core bundle is not carrying the German catalog")
    }
```

#### 4. Core `AppearanceMode.title` test
**File**: `CheckStitchTests/AppearanceModeTests.swift`
**Action**: modify

This file imports only `CheckStitchCore`, so `AppearanceMode` here is the core
type. Add:

```swift
    @Test(arguments: [
        (AppearanceMode.system, "System"),
        (.light, "Light"),
        (.dark, "Dark"),
    ])
    func titlesResolveThroughTheCoreCatalog(_ mode: AppearanceMode, _ key: String) {
        #expect(mode.title == String.en(key, bundle: .core))
    }
```

### Verification
#### Automated
- [x] `make test-unit` — `coreCatalogValuesAreEmbeddedInTheResourceBundle` and the extended `AppearanceModeTests` pass; existing `AppearanceModePreferenceTests` unchanged and green
- [x] `make watch-build` compiles (the watch links the package)

#### Manual
- [ ] Run the macOS app and confirm the appearance picker still shows System / Light / Dark in English

---

## Phase 4: App string migration

Routes the app target's copy through `CheckStitch/Localizable.xcstrings`.
Only two call sites need code changes: every other user-facing string is a
SwiftUI literal in a `LocalizedStringKey` position (`Text`, `Label`, `Button`,
`Section`, `TextField` placeholder, `ContentUnavailableView`, `navigationTitle`,
`.accessibilityLabel`, `.alert`) and is therefore extracted by
`SWIFT_EMIT_LOC_STRINGS = YES` and resolved from the catalog at runtime.

### Changes

#### 1. App `AppearanceMode.title` reads the app catalog
**File**: `CheckStitch/AppearanceMode.swift`
**Action**: modify (`title`, ~lines 69-76)

```swift
    /// Human-readable label shown in the appearance picker.
    var title: String {
        switch self {
        case .system: String(localized: "System", table: "Localizable", bundle: .main)
        case .light: String(localized: "Light", table: "Localizable", bundle: .main)
        case .dark: String(localized: "Dark", table: "Localizable", bundle: .main)
        }
    }
```

#### 2. Localize the photo credit (a `String`, not a SwiftUI literal)
**File**: `CheckStitch/BackgroundSettingsView.swift`
**Action**: modify (line 67)

```swift
                    let credit = String(
                        localized: "Photo by \(photographer) on Unsplash",
                        table: "Localizable", bundle: .main)
```

`credit` is inferred as `String`, so SwiftUI's `Link`/`Text` treat it verbatim —
without this change the credit is never localized. The interpolation compiles
to the catalog key `Photo by %@ on Unsplash`.

#### 3. App runtime-key assertions
**File**: `CheckStitchTests/LocalizationTests.swift`
**Action**: modify

```swift
    @Test
    func appCatalogIsEmbeddedInTheMainBundle() throws {
        let appKeys = try Catalogs.load(
            contentsOf: try Catalogs.url(forCatalog: "App"), catalog: "App")
        let settings = try #require(appKeys.first { $0.key == "Settings" })
        let german = String(
            localized: "Settings", table: "Localizable", bundle: .main,
            locale: Locale(identifier: "de"))
        #expect(german == settings.localizations["de"], "App bundle is not carrying the German catalog")
    }

    @Test
    func unknownKeyFallsBackToItsOwnText() {
        #expect(String.en("__missing_key__", bundle: .main) == "__missing_key__")
    }
```

#### 4. No other app source changes
**Files**: `CheckStitch/ContentView.swift`, `CheckStitch/ChecklistDetailView.swift`,
`CheckStitch/SettingsView.swift`, `CheckStitch/BackgroundSettingsView.swift` (beyond step 2)
**Action**: verify only — no edits

Explicitly **not** touched:
- `ContentView.swift:344`'s shadowed `enum ChecklistWidth` (and its use at `:214`)
- `ChecklistStore.swift` defaults / storage key `"checklists.v1"`
- `AppearanceMode` raw values / `defaultsKey`
- `#Preview("Dark")` label in `SettingsView.swift`

`CheckStitchTests/ViewRenderTests.swift` is verify-only: it renders
`SettingsView.body` for all appearance modes and must stay green now that
`title` reads `.main`.

### Verification
#### Automated
- [ ] `make test-unit` — `appCatalogIsEmbeddedInTheMainBundle`, `unknownKeyFallsBackToItsOwnText`, and `ViewRenderTests` pass
- [ ] `make build` compiles
- [ ] `make build-mac` compiles
- [ ] After a build, `git diff -- CheckStitch/Localizable.xcstrings` shows no unexpected keys (new keys ⇒ add six translations, Phase 2 step 1)

#### Manual
- [ ] `make build` then confirm the built `CheckStitch.app` contains `en.lproj/Localizable.strings` (and `de.lproj` etc.) inside the bundle

---

## Phase 5: Watch string migration

### Changes

#### 1. Localize the run/sent button title
**File**: `CheckStitchWatch/WatchChecklistDetailView.swift`
**Action**: modify (line 21)

The ternary currently has no unambiguous localized overload; make the lookup
explicit:

```swift
        .safeAreaInset(edge: .bottom) {
            Button(sent
                ? String(localized: "Sent", table: "Localizable", bundle: .main)
                : String(localized: "Create reminders", table: "Localizable", bundle: .main)) {
                sent = store.run(checklist)
            }
            .disabled(sent || visibleItems.isEmpty)
        }
```

#### 2. No other watch source changes
**File**: `CheckStitchWatch/WatchChecklistListView.swift`
**Action**: verify only

`ContentUnavailableView("No checklists", ..., description: Text("Open CheckStitch on your iPhone."))`
and `.navigationTitle("Checklists")` are `LocalizedStringKey` literals and are
extracted by the watch target's `SWIFT_EMIT_LOC_STRINGS = YES`; no code change.

#### 3. Watch key assertion
**File**: `CheckStitchTests/LocalizationTests.swift`
**Action**: modify

```swift
    @Test
    func watchCatalogCarriesEveryUIKey() throws {
        let requirements = try #require(
            LocalizationFixtures.requiredKeys.first { $0.catalog == "Watch" })
        let keys = Set(try Catalogs.load(
            contentsOf: try Catalogs.url(forCatalog: "Watch"), catalog: "Watch").map(\.key))
        #expect(keys.isSuperset(of: requirements.keys))
    }
```

(`everyRequiredKeyIsPresent` in Phase 2 already covers this generically; this
explicit test documents the watch surface and was introduced because the watch
target is not macOS-hosted, so its strings can only be asserted against the
source-tree catalog.)

### Verification
#### Automated
- [ ] `make watch-build` compiles
- [ ] `make test-unit` — `watchCatalogCarriesEveryUIKey` passes
- [ ] After `make watch-build`, `git diff -- CheckStitchWatch/Localizable.xcstrings` shows no unexpected keys

#### Manual
- [ ] Build the watch scheme and confirm `CheckStitchWatch.app` contains `en.lproj/Localizable.strings`

---

## Phase 6: Localized Info.plist metadata

### Changes

#### 1. App per-language `InfoPlist.strings`
**Files**: `CheckStitch/en.lproj/InfoPlist.strings`, `CheckStitch/de.lproj/InfoPlist.strings`, `CheckStitch/es.lproj/InfoPlist.strings`, `CheckStitch/fr.lproj/InfoPlist.strings`, `CheckStitch/ja.lproj/InfoPlist.strings`, `CheckStitch/zh-Hans.lproj/InfoPlist.strings`
**Action**: create

UTF-8, old-style plist (`"key" = "value";`). English file:

```
"NSRemindersFullAccessUsageDescription" = "CheckStitch needs access to create reminders.";
"NSRemindersUsageDescription" = "CheckStitch needs access to create reminders.";
"CFBundleDisplayName" = "CheckStitch";
```

Translations (both usage-description keys get the same value; the display name
is `CheckStitch` in every language):

| Language | Usage description |
|---|---|
| de | CheckStitch benötigt Zugriff, um Erinnerungen zu erstellen. |
| es | CheckStitch necesita acceso para crear recordatorios. |
| fr | CheckStitch a besoin d'un accès pour créer des rappels. |
| ja | CheckStitch がリマインダーを作成するためのアクセスを必要としています。 |
| zh-Hans | CheckStitch 需要访问权限来创建提醒事项。 |

The English values at the `INFOPLIST_KEY_*` level in `project.pbxproj` remain
unchanged (reference pattern); translations come only from these files.

#### 2. Watch per-language `InfoPlist.strings`
**Files**: `CheckStitchWatch/{en,de,es,fr,ja,zh-Hans}.lproj/InfoPlist.strings`
**Action**: create

```
"CFBundleDisplayName" = "CheckStitch";
```

Only the display name (see Phase 1 step 5 rationale: the watch has no EventKit
access, so it has no reminders usage-description key to localize). The
`INFOPLIST_KEY_CFBundleDisplayName = CheckStitch` build setting stays — it
provides the base value.

#### 3. InfoPlist assertion
**File**: `CheckStitchTests/LocalizationTests.swift`
**Action**: modify

```swift
    @Test
    func infoPlistStringsHaveRequiredKeysPerLanguage() throws {
        for target in LocalizationFixtures.infoPlistTargets {
            for language in Catalogs.languages {
                let url = Catalogs.repoRoot
                    .appendingPathComponent(target.path)
                    .appendingPathComponent("\(language).lproj/InfoPlist.strings")
                let data = try Data(contentsOf: url)
                let plist = try #require(
                    try PropertyListSerialization.propertyList(from: data, format: nil)
                        as? [String: String],
                    "\(target.name)/\(language) is not a key-value plist")
                let missing = LocalizationFixtures.missingInfoPlistKeys(
                    in: plist, required: target.keys)
                #expect(missing.isEmpty, "\(target.name)/\(language) missing or empty: \(missing)")
            }
        }
    }

    @Test
    func incompleteInfoPlistIsReportedMissing() {
        let missing = LocalizationFixtures.missingInfoPlistKeys(
            in: ["CFBundleDisplayName": "CheckStitch", "NSRemindersUsageDescription": ""],
            required: ["NSRemindersFullAccessUsageDescription", "NSRemindersUsageDescription", "CFBundleDisplayName"])
        #expect(missing == ["NSRemindersFullAccessUsageDescription", "NSRemindersUsageDescription"])
    }
```

### Verification
#### Automated
- [ ] `make test-unit` — `infoPlistStringsHaveRequiredKeysPerLanguage`, `incompleteInfoPlistIsReportedMissing` pass
- [ ] `make build` compiles and the built app bundle contains all six `.lproj` directories
- [ ] `make build-mac` compiles
- [ ] `make watch-build` compiles
- [ ] `bash scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] Set a simulator/device to German and relaunch from clean (delete app + revoke Reminders access so the prompt reappears):
  ```bash
  xcrun simctl spawn <UDID> defaults write -g AppleLanguages -array de
  xcrun simctl spawn <UDID> defaults write -g AppleLocale -string de_DE
  xcrun simctl shutdown <UDID> && xcrun simctl boot <UDID>
  ```
  or via Settings → General → Language & Region → German.
- [ ] Confirm translated UI copy: nav titles `Einstellungen` / `Hintergrund` / `Checkliste bearbeiten`, empty state `Keine Checklisten`, picker row `Hell`/`Dunkel`, photo credit `Foto von … auf Unsplash`
- [ ] Confirm the Reminders permission prompt shows the German usage description
- [ ] Confirm the home-screen app name still reads **CheckStitch** (and the watch app name too)
- [ ] Switch the device to `ja` or `zh-Hans` and spot-check the same screens

**Non-horizontal caveat:** generated-Info.plist precedence (`INFOPLIST_KEY_*`
vs `.lproj`) cannot be asserted from unit tests — the manual locale smoke above
is the only proof that the localized metadata actually surfaces.

---

## Files touched — summary

| Phase | File | Action |
|---|---|---|
| 1 | `CheckStitchCore/Package.swift` | modify |
| 1 | `CheckStitch.xcodeproj/project.pbxproj` (`knownRegions`) | modify |
| 1,2 | `CheckStitch/Localizable.xcstrings` | create, then fill |
| 1,2 | `CheckStitchWatch/Localizable.xcstrings` | create, then fill |
| 1,2 | `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings` | create, then fill |
| 1 | `CheckStitchTests/LocalizationTestHelpers.swift` | create |
| 1 | `CheckStitchTests/LocalizationFixtures.swift` | create |
| 1,2,3,4,5,6 | `CheckStitchTests/LocalizationTests.swift` | create, then extend |
| 3 | `CheckStitchCore/Sources/CheckStitchCore/SharedStrings.swift` | create |
| 3 | `CheckStitchCore/Sources/CheckStitchCore/AppearanceMode.swift` | modify |
| 3 | `CheckStitchTests/AppearanceModeTests.swift` | modify |
| 4 | `CheckStitch/AppearanceMode.swift` | modify |
| 4 | `CheckStitch/BackgroundSettingsView.swift` | modify |
| 4 | `CheckStitchTests/ViewRenderTests.swift` | verify only |
| 5 | `CheckStitchWatch/WatchChecklistDetailView.swift` | modify |
| 5 | `CheckStitchWatch/WatchChecklistListView.swift` | verify only |
| 6 | `CheckStitch/{en,de,es,fr,ja,zh-Hans}.lproj/InfoPlist.strings` | create (6) |
| 6 | `CheckStitchWatch/{en,de,es,fr,ja,zh-Hans}.lproj/InfoPlist.strings` | create (6) |

No `PBXBuildFile` / `PBXFileReference` / build-phase edits; the only pbxproj
change is `knownRegions`.

## Deviations from `structure.md` (and why)

1. **Accessibility labels and alert strings stay SwiftUI literals** (structure
   Layer 4 said convert them to `String(localized:)`). `.accessibilityLabel`,
   `.alert(_:isPresented:)` and `Text`/`Label` all take `LocalizedStringKey`
   overloads, so literals there are extracted by `SWIFT_EMIT_LOC_STRINGS = YES`
   and resolved from the catalog at runtime — this is exactly what the
   reference project does (`SingleThread/ContentView.swift:193` keeps
   `.accessibilityLabel("Settings")` as a literal, and `"Settings"` is a key in
   its catalog). Only genuinely `String`-typed copy needs code changes: the
   Unsplash credit and the watch's ternary button title.
2. **Watch `.lproj/InfoPlist.strings` carries only `CFBundleDisplayName`**
   (structure Layer 6 listed `NSRemindersFullAccessUsageDescription` too).
   CheckStitch's watch never touches EventKit — `WatchChecklistDetailView`
   calls `WatchChecklistStore.run`, which only sends a `WCSession` message
   (`CheckStitchCore/.../ChecklistSync.swift:65-95`), and the watch target's
   generated Info.plist has no reminders usage key. SingleThread's watch *does*
   touch EventKit, which is why its lproj carries the key. Adding the build
   setting plus a translated string here would have been inert.
3. **`AppearanceMode`'s property is `title`, not `label`** (structure Layer 3
   used `label`). The plan uses the actual name.
4. **`String.en` takes `String`, not `String.LocalizationValue`.** Swift does
   not implicitly convert `String` to `String.LocalizationValue` (verified with
   `swiftc -typecheck`), so the reference signature would break the
   argument-driven tests in Phases 3-4.
5. **Two additions beyond the structure's test list**, both strengthening the
   design's stated checks: `everyRequiredKeyIsPresent` (the catalog tests only
   assert keys *present in the catalog*, so a dropped key would otherwise ship
   silently) and a pure `missingInfoPlistKeys` helper so the incomplete-plist
   sad path is testable without triggering `preconditionFailure`.
6. **Phase 1's parse test omits the "catalog has keys" guard**; it is added in
   Phase 2 when the catalogs are non-empty, otherwise Phase 1's skeletons would
   fail their own test.

## No open questions

The only remaining uncertainty is the exact set of `excludedIdentities`
entries. The canary test's failure message names the offending
`(catalog, key, language)`, so the resolution is mechanical: translate it, or
add the pair to `LocalizationFixtures.excludedIdentities` with a comment. The
plan seeds the list with the five identities known up front.
