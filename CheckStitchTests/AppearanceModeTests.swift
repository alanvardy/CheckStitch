@testable import CheckStitchCore
import Foundation
import Testing

struct AppearanceModeTests {
    @Test(arguments: ["system", "light", "dark"])
    func appearanceModeLoadsValidRawValue(_ raw: String) {
        let defaults = makeIsolatedDefaults()
        AppearanceModePreference(defaults: defaults).setRawValue(raw)
        #expect(AppearanceMode.load(from: defaults) == AppearanceMode(rawValue: raw))
    }

    @Test(arguments: [nil, "", " ", "\n", ".light", "bogus"] as [String?])
    func invalidRawValueFallsBackToSystem(_ raw: String?) {
        let defaults = makeIsolatedDefaults()
        if let raw { AppearanceModePreference(defaults: defaults).setRawValue(raw) }
        #expect(AppearanceMode.load(from: defaults) == .system)
    }

    @Test(arguments: [
        (AppearanceMode.system, "System"),
        (.light, "Light"),
        (.dark, "Dark"),
    ])
    func titlesResolveThroughTheCoreCatalog(_ mode: AppearanceMode, _ key: String) {
        // Resolve against the core bundle with the same default-locale semantics
        // as `SharedStrings`, rather than pinning `en`, so the assertion does not
        // depend on the test host's locale.
        #expect(mode.title == String(
            localized: String.LocalizationValue(key), table: "Localizable", bundle: .core))
    }
}
