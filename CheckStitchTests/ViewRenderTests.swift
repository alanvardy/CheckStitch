@testable import CheckStitch
import CheckStitchCore
import SwiftUI
import Testing

@MainActor
struct ViewRenderTests {
    @Test
    func detailViewRendersForEmptyAndNonEmptyChecklists() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let empty = store.create(name: "Empty")
        let filled = store.create(name: "Filled")
        store.addItem(to: filled.id)

        let emptyView = ChecklistDetailView(checklistID: empty.id).environment(store)
        let filledView = ChecklistDetailView(checklistID: filled.id).environment(store)
        // `ImageRenderer` forces a real render pass, so the body evaluates
        // against the injected store. (Calling `.body` on the `ModifiedContent`
        // that `.environment` produces is a SwiftUI runtime trap.)
        #expect(renders(emptyView))
        #expect(renders(filledView))
    }

    /// Renders `view` offscreen and reports whether a frame was produced.
    private func renders(_ view: some View) -> Bool {
        #if os(macOS)
        return ImageRenderer(content: view).nsImage != nil
        #else
        return ImageRenderer(content: view).uiImage != nil
        #endif
    }

    @Test
    func settingsViewListsAllAppearanceModes() {
        let view = SettingsView(
            appearanceMode: .constant(.system),
            appLanguage: .constant(.system),
            bindings: SettingsBindings(),
            backgroundImage: BackgroundImageStore())
        #expect(String(describing: view.body).isEmpty == false)
        // The app target carries its own `AppearanceMode` alongside the
        // core package's, so qualify explicitly to avoid ambiguity. Title is a
        // resource (pinned by key — the app's own catalog carries the text).
        #expect(CheckStitch.AppearanceMode.allCases.map(\.title.key) == ["System", "Light", "Dark"])
        #expect(CheckStitch.AppearanceMode.allCases.map(\.systemImage).allSatisfy { !$0.isEmpty })
    }

    @Test
    func settingsViewExposesAboutRow() {
        let view = SettingsView(
            appearanceMode: .constant(.system),
            appLanguage: .constant(.system),
            bindings: SettingsBindings(),
            backgroundImage: BackgroundImageStore())
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("About"))
        #expect(bodyDescription.contains("Background"))
    }

    @Test
    func settingsViewExposesPurchaseRow() {
        let service = PurchaseService(
            provider: SpyPurchaseProvider(),
            cache: PurchaseEntitlementCache(defaults: makeIsolatedDefaults()))
        let view = SettingsView(
            appearanceMode: .constant(.system),
            appLanguage: .constant(.system),
            bindings: SettingsBindings(),
            backgroundImage: BackgroundImageStore(),
            purchases: service)
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("Unlock CheckStitch"),
                "a locked user can reach the purchase screen from Settings")
    }

    @Test
    func settingsViewRendersWithImportAndExportRows() {
        let view = SettingsView(
            appearanceMode: .constant(.system),
            appLanguage: .constant(.system),
            bindings: SettingsBindings(),
            backgroundImage: BackgroundImageStore(),
            onExport: {},
            onImport: {})
        #expect(renders(view))
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
