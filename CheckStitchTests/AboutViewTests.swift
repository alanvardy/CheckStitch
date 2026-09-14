@testable import CheckStitch
import CheckStitchCore
import SwiftUI
import Testing

/// Exercises the About screen's identity/attribution rendering, including the
/// macOS `settingsSubscreenLayout()` canary that is a no-op on iOS.
@MainActor
struct AboutViewTests {
    @Test
    func aboutViewRendersAttributionAndIdentity() {
        let view = AboutView(appInfo: stubAppInfo())
        let bodyDescription = String(describing: view.body)
        for expected in [
            "Copyright 2026 Alan Vardy",
            "Made with love by a lone developer",
            "Version 1.0 (1)",
            "CheckStitch",
            "alan@vardy.cc",
        ] {
            #expect(bodyDescription.contains(expected))
        }
        #if os(macOS)
            #expect(bodyDescription.contains("SettingsSubscreenLayout"))
        #endif
    }

    @Test
    func aboutViewRendersWithoutCrashingWhenVersionIsNil() {
        let view = AboutView(appInfo: AppInfo(bundle: StubBundle(info: [:])))
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("Copyright 2026 Alan Vardy"))
        #expect(bodyDescription.contains("Made with love by a lone developer"))
        // Display name falls back to the "CheckStitch" literal.
        #expect(bodyDescription.contains("CheckStitch"))
    }

    private func stubAppInfo() -> AppInfo {
        AppInfo(bundle: StubBundle(info: [
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleDisplayName": "CheckStitch",
        ]))
    }
}