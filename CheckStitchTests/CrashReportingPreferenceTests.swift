import Foundation
@testable import CheckStitchCore
import Testing

@MainActor
struct CrashReportingPreferenceTests {
    @Test
    func absentKeyDefaultsToEnabled() {
        #expect(CrashReportingPreference(defaults: makeIsolatedDefaults()).isEnabled)
    }

    @Test
    func explicitFalseDisables() {
        let defaults = makeIsolatedDefaults()
        CrashReportingPreference(defaults: defaults).setEnabled(false)
        #expect(!CrashReportingPreference(defaults: defaults).isEnabled)
        #expect(defaults.object(forKey: CrashReportingPreference.defaultsKey) as? Bool == false)
    }

    @Test
    func explicitTrueEnables() {
        let defaults = makeIsolatedDefaults()
        CrashReportingPreference(defaults: defaults).setEnabled(true)
        #expect(CrashReportingPreference(defaults: defaults).isEnabled)
        #expect(defaults.object(forKey: CrashReportingPreference.defaultsKey) as? Bool == true)
    }

    @Test
    func setEnabledRoundTrips() {
        let defaults = makeIsolatedDefaults()
        let preference = CrashReportingPreference(defaults: defaults)

        preference.setEnabled(false)
        #expect(!preference.isEnabled)
        #expect(defaults.object(forKey: CrashReportingPreference.defaultsKey) as? Bool == false)

        preference.setEnabled(true)
        #expect(preference.isEnabled)
        #expect(defaults.object(forKey: CrashReportingPreference.defaultsKey) as? Bool == true)
    }
}
