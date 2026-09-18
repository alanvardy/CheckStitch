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
        // The title is a resource (so SwiftUI re-resolves it against
        // `\.locale`), pinned to its catalog key; the second assertion
        // confirms an explicit-locale resolution reaches the embedded core
        // catalog rather than falling back to the key itself.
        #expect(mode.title.key == key)
        #expect(mode.title.resolved(in: Locale(identifier: "en"))
            == String(localized: String.LocalizationValue(key), table: "Localizable", bundle: .core))
    }
}
