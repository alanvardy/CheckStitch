@testable import CheckStitch
import Foundation
import Testing

@MainActor
struct AppGroupTests {
    @Test
    func suiteNameMatchesAppGroupEntitlementLiteral() {
        // Must stay byte-identical to `CheckStitch/AppGroup.entitlements` and
        // the watch app's shared container; a rename silently breaks the share.
        #expect(AppGroup.suiteName == "group.app.alanvardy.CheckStitch")
    }

    @Test
    func defaultsRoundTripsAProbeValue() {
        let defaults = AppGroup.defaults
        let key = "test.appGroup.probe.\(UUID().uuidString)"
        defer { defaults.removeObject(forKey: key) }
        defaults.set("probe", forKey: key)
        #expect(defaults.string(forKey: key) == "probe")
    }

    @Test
    func defaultsIsUsableWhenSuiteUnavailable() {
        // The `?? .standard` fallback cannot be forced from a test; this pins
        // that `defaults` is always a usable store and the probe is cleaned up.
        let defaults = AppGroup.defaults
        let key = "test.appGroup.probe.\(UUID().uuidString)"
        defer { defaults.removeObject(forKey: key) }
        defaults.set(true, forKey: key)
        #expect(defaults.bool(forKey: key))
        defaults.removeObject(forKey: key)
        #expect(defaults.object(forKey: key) == nil)
    }
}
