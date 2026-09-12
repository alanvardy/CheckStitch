@testable import CheckStitch
import SwiftUI
import Testing

@MainActor
struct ViewRenderTests {
    @Test
    func settingsViewListsAllAppearanceModes() {
        let view = SettingsView(appearanceMode: .constant(.system))
        #expect(String(describing: view.body).isEmpty == false)
        // The app target carries its own `AppearanceMode` alongside the
        // core package's, so qualify explicitly to avoid ambiguity.
        #expect(CheckStitch.AppearanceMode.allCases.map(\.title) == ["System", "Light", "Dark"])
        #expect(CheckStitch.AppearanceMode.allCases.map(\.systemImage).allSatisfy { !$0.isEmpty })
    }
}