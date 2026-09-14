import CheckStitchCore
import Testing

/// Exercises `AppInfo` against a `StubBundle` in place of the real bundle's
/// Info.plist. Assertions use the concrete English output; that the version
/// keys are embedded in the compiled Core catalog is covered separately by
/// `LocalizationTests.coreCatalogValuesAreEmbeddedInTheResourceBundle`.
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
        #expect(info.versionDescription == "Version 1.0 (1)")
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
        #expect(info.versionDescription == "Version 1.0")
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
