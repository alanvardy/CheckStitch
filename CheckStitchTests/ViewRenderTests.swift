@testable import CheckStitch
import SwiftUI
import Testing

@MainActor
struct ViewRenderTests {
    @Test
    func settingsViewListsAllAppearanceModes() {
        let view = SettingsView(
            appearanceMode: .constant(.system),
            bindings: SettingsBindings(),
            backgroundImage: BackgroundImageStore())
        #expect(String(describing: view.body).isEmpty == false)
        // The app target carries its own `AppearanceMode` alongside the
        // core package's, so qualify explicitly to avoid ambiguity.
        #expect(CheckStitch.AppearanceMode.allCases.map(\.title) == ["System", "Light", "Dark"])
        #expect(CheckStitch.AppearanceMode.allCases.map(\.systemImage).allSatisfy { !$0.isEmpty })
    }

    @Test
    func syncStatusIsSilentWhenSynced() {
        #expect(SyncStatusView(outcome: .synced, isSyncing: false).message == nil)
    }

    @Test
    func syncStatusShowsFailureReason() {
        #expect(SyncStatusView(outcome: .failed("boom"), isSyncing: false).message == "boom")
    }

    @Test
    func syncStatusShowsActivityWhileSyncing() {
        #expect(SyncStatusView(outcome: nil, isSyncing: true).message != nil)
    }

    @Test
    func syncStatusSurfacesUnavailable() {
        #expect(SyncStatusView(outcome: .unavailable, isSyncing: false).message == "iCloud unavailable")
    }
}
