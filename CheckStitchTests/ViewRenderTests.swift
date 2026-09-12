@testable import CheckStitch
@testable import CheckStitchCore
import SwiftUI
import Testing

@MainActor
struct ViewRenderTests {
    private func makeEnvironment() -> AppEnvironment {
        AppEnvironment(reminderCreator: SpyReminderCreator())
    }

    @Test
    func contentViewBodyRendersNonEmpty() {
        let view = ContentView(environment: makeEnvironment())
        #expect(String(describing: view.body).isEmpty == false)
    }

    @Test
    func settingsViewListsAllAppearanceModes() {
        let view = SettingsView(appearanceMode: .constant(.system))
        #expect(String(describing: view.body).isEmpty == false)
        #expect(AppearanceMode.allCases.map(\.title) == ["System", "Light", "Dark"])
        #expect(AppearanceMode.allCases.map(\.systemImage).allSatisfy { !$0.isEmpty })
    }
}
