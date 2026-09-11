@testable import CheckStitchCore
import Foundation
import Testing

struct AppearanceModePreferenceTests {
    @Test
    func preferenceSetThenReadRoundTrips() {
        let defaults = makeIsolatedDefaults()
        let preference = AppearanceModePreference(defaults: defaults)
        preference.setRawValue("dark")
        #expect(preference.rawValue == "dark")
        #expect(AppearanceMode.load(from: defaults) == .dark)
    }

    @Test
    func preferenceIgnoresUnknownStoredValue() {
        let defaults = makeIsolatedDefaults()
        defaults.set("sepia", forKey: AppearanceModePreference.defaultsKey)
        #expect(AppearanceModePreference(defaults: defaults).rawValue == "system")
    }
}