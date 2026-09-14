import Foundation
import CheckStitchCore
import Testing

/// Exercises `AppInfo` against a `StubBundle` in place of the real bundle's
/// Info.plist. The version strings resolve through the shared `String.en`
/// helper against the embedded Core bundle — the hosted test runner cannot use
/// the package-only `Bundle.module`.
struct AppInfoTests {
    @Test
    func readsMarketingVersionBuildNumberAndDisplayName() {
        let info = AppInfo(bundle: StubBundle(info: [
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleDisplayName": "CheckStitch"
        ]))

        #expect(info.marketingVersion == "1.0")
        #expect(info.buildNumber == "1")
        #expect(info.displayName == "CheckStitch")
        #expect(info.versionDescription == String.en(
            "Version \(info.marketingVersion!) (\(info.buildNumber!))",
            bundle: .core))
    }

    @Test
    func fallsBackWhenIdentityKeysAreAbsent() {
        let info = AppInfo(bundle: StubBundle(info: [:]))

        #expect(info.marketingVersion == nil)
        #expect(info.buildNumber == nil)
        #expect(info.displayName == "CheckStitch")
        #expect(info.versionDescription.isEmpty)
    }

    @Test
    func omitsBuildParentheticalWhenBuildIsAbsent() {
        let info = AppInfo(bundle: StubBundle(info: [
            "CFBundleShortVersionString": "1.0"
        ]))

        #expect(info.marketingVersion == "1.0")
        #expect(info.buildNumber == nil)
        #expect(info.versionDescription == String.en(
            "Version \(info.marketingVersion!)",
            bundle: .core))
    }

    @Test
    func emptyVersionWhenMarketingAbsentButBuildPresent() {
        let info = AppInfo(bundle: StubBundle(info: [
            "CFBundleVersion": "1"
        ]))

        #expect(info.marketingVersion == nil)
        #expect(info.buildNumber == "1")
        #expect(info.versionDescription.isEmpty)
    }

    @Test
    func fallsBackToBundleNameWhenDisplayNameAbsent() {
        let info = AppInfo(bundle: StubBundle(info: [
            "CFBundleName": "CheckStitch"
        ]))

        #expect(info.displayName == "CheckStitch")
    }
}
