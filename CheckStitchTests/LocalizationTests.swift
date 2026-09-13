import Foundation
import Testing

/// Validates the string-catalog and InfoPlist.strings resource layer.
/// Catalogs are read from the source tree (synchronized folder groups), so
/// `#filePath` resolves to the checkout's source path; no bundle lookup is needed.
struct LocalizationTests {
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

    @Test
    func coreCatalogValuesAreEmbeddedInTheResourceBundle() throws {
        let coreKeys = try Catalogs.load(
            contentsOf: try Catalogs.url(forCatalog: "Core"), catalog: "Core")
        let dark = try #require(coreKeys.first { $0.key == "Dark" })
        // The compiled core catalog is embedded in the test host as a resource
        // bundle. The hosted runner resolves `String(localized:)` with the process
        // locale (English here), so a locale pin cannot observe e.g. German;
        // instead resolve the embedded `de.lproj` table via Foundation's own
        // resource lookup and compare it against the source-tree catalog.
        let germanURL = try #require(
            Bundle.core.url(
                forResource: "Localizable", withExtension: "strings",
                subdirectory: "", localization: "de"),
            "Core bundle has no de table at runtime")
        let germanTable = try #require(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: germanURL), format: nil)
                as? [String: String],
            "Core bundle de table is not a readable key/value plist")
        #expect(germanTable["Dark"] == dark.localizations["de"],
            "Core bundle is not carrying the German catalog")
    }

    @Test
    func appCatalogIsEmbeddedInTheMainBundle() throws {
        let appKeys = try Catalogs.load(
            contentsOf: try Catalogs.url(forCatalog: "App"), catalog: "App")
        let settings = try #require(appKeys.first { $0.key == "Settings" })
        // Same locale-pin limitation as the core bundle: the hosted runner
        // resolves `String(localized:)` with the process locale, so resolve the
        // embedded German table directly and compare it against the catalog.
        let germanURL = try #require(
            Bundle.main.url(
                forResource: "Localizable", withExtension: "strings",
                subdirectory: "", localization: "de"),
            "Main bundle has no de table at runtime")
        let germanTable = try #require(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: germanURL), format: nil)
                as? [String: String],
            "Main bundle de table is not a readable key/value plist")
        #expect(germanTable["Settings"] == settings.localizations["de"],
            "Main bundle is not carrying the German catalog")
    }

    @Test
    func unknownKeyFallsBackToItsOwnText() {
        #expect(String.en("__missing_key__", bundle: .main) == "__missing_key__")
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