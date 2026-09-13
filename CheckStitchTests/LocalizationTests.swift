import Foundation
import Testing

/// Validates the string-catalog and InfoPlist.strings resource layer.
/// Catalogs are read from the source tree (synchronized folder groups), so
/// `#filePath` resolves to the checkout's source path; no bundle lookup is needed.
struct LocalizationTests {
    @Test
    func catalogsParse() throws {
        // Phase 1 catalogs are empty skeletons, so the proof is that all three
        // load without throwing (`loadAll` throws on unreadable/malformed
        // files). The `catalogs.count >= Catalogs.all.count` form in the plan
        // requires non-empty keys and would fail against the Phase 1 skeletons;
        // Phase 2 replaces this test with `catalogsParseAndHaveNonEmptyEnglish`.
        let catalogs = try Catalogs.loadAll()
        #expect(catalogs.isEmpty)
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