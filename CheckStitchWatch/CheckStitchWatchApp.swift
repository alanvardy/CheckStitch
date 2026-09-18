import CheckStitchCore
import SwiftUI

@main
struct CheckStitchWatchApp: App {
    @State private var viewModel = WatchChecklistViewModel(
        store: WatchChecklistStore(transport: WatchSyncAdapter()))

    var body: some Scene {
        WindowGroup {
            WatchChecklistListView()
                .environment(viewModel)
                .environment(\.locale, AppLocaleState.current.effectiveLocale)
        }
    }
}
