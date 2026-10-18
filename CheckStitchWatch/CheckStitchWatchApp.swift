import CheckStitchCore
import SwiftUI

@main
struct CheckStitchWatchApp: App {
    private let seams: LaunchSeams
    @State private var viewModel: WatchChecklistViewModel

    init() {
        let seams = LaunchSeams.current()
        self.seams = seams
        if let language = seams.language { AppLocaleState.current.set(language) }
        let store = WatchChecklistStore(transport: WatchSyncAdapter())
        if seams.isUITesting, let envelope = seams.loadSeedEnvelope() {
            store.seed(envelope)
        }
        _viewModel = State(initialValue: WatchChecklistViewModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            WatchChecklistListView(initialChecklistIndex: seams.openChecklistIndex)
                .environment(viewModel)
                .environment(\.locale, AppLocaleState.current.effectiveLocale)
        }
    }
}
