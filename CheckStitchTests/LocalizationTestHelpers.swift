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