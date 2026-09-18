import CheckStitchCore
import SwiftUI

@main
struct CheckStitchWatchApp: App {
    @State private var store = WatchChecklistStore(transport: WatchSyncAdapter())

    var body: some Scene {
        WindowGroup {
            WatchChecklistListView()
                .environment(store)
                .environment(\.locale, AppLocaleState.current.effectiveLocale)
        }
    }
}
