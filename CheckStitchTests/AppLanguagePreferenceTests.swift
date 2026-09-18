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