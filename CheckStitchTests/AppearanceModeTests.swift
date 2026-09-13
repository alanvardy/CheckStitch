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
        #expect(mode.title == String.en(key, bundle: .core))
    }
}
