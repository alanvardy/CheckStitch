@testable import CheckStitch
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct ReminderNumberingPreferenceTests {
    @Test
    func missingKeyDefaultsToDisabled() {
        let preference = ReminderNumberingPreference(defaults: makeIsolatedDefaults())
        #expect(!preference.isEnabled)
    }

    @Test
    func enabledValueRoundTrips() {
        let defaults = makeIsolatedDefaults()
        let preference = ReminderNumberingPreference(defaults: defaults)
        preference.setEnabled(true)
        #expect(ReminderNumberingPreference(defaults: defaults).isEnabled)
    }
}