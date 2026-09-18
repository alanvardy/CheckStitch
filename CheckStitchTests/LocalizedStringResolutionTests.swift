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
            forResource: "Localizable", withExtension: "strings",
            subdirectory: "", localization: "de"))
        return try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), format: nil) as? [String: String])
    }
}