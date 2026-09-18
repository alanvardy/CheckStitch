@testable import CheckStitch
import Foundation
import Testing

/// The app target's default actor isolation marks `OrientationPreference`'s
/// members `@MainActor`, so the suite opts in like `TextSizeTests`.
@MainActor
struct OrientationPreferenceTests {
    @Test
    func missingKeyDefaultsToLandscapeEnabled() {
        let defaults = makeIsolatedDefaults()
        // Sad path: no stored value at all.
        #expect(OrientationPreference(defaults: defaults).isLandscapeEnabled)
    }

    @Test
    func storedValueRoundTrips() {
        let defaults = makeIsolatedDefaults()
        let preference = OrientationPreference(defaults: defaults)
        preference.setLandscapeEnabled(false)
        #expect(!preference.isLandscapeEnabled)
        preference.setLandscapeEnabled(true)
        #expect(preference.isLandscapeEnabled)
    }

    @Test
    func nonBooleanStoredValueFallsBackToEnabled() {
        let defaults = makeIsolatedDefaults()
        defaults.set("yes", forKey: OrientationPreference.defaultsKey)
        #expect(OrientationPreference(defaults: defaults).isLandscapeEnabled)
    }

    @Test
    func policySelectsTheLockForEachToggleValue() {
        // Platform-agnostic stand-in for the UIKit mask: the mask conversion
        // (`OrientationPolicy.mask`) is iOS-only and exercised manually.
        #expect(OrientationPolicy(allowsLandscape: true) == .allButUpsideDown)
        #expect(OrientationPolicy(allowsLandscape: false) == .portrait)
        #expect(OrientationPolicy.allCases.map(\.rawValue) == ["portrait", "allButUpsideDown"])
    }
}