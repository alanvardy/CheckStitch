import CheckStitchCore
import SwiftUI
#if os(iOS)
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif

@main struct MyApp: App {
    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self)
        private var appDelegate
    #endif
    #if os(macOS)
        @NSApplicationDelegateAdaptor(MacAppDelegate.self)
        private var macAppDelegate
    #endif

    @State private var store: ChecklistStore
    @State private var listViewModel: ChecklistListViewModel
    @State private var runViewModel: ChecklistRunViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var importExportViewModel: ChecklistImportExportViewModel
    @State private var backgroundViewModel: BackgroundViewModel
    @State private var appearanceViewModel: AppearanceViewModel
    @State private var syncService: ChecklistSyncService
    #if os(iOS)
        @State private var coordinator: ChecklistSyncCoordinator?
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = ChecklistStore()
        let syncService = ChecklistSyncService(sync: UbiquitousChecklistSync(), store: store)
        syncService.start()
        _store = State(initialValue: store)
        _listViewModel = State(initialValue: ChecklistListViewModel(store: store))
        _runViewModel = State(initialValue: ChecklistRunViewModel(store: store))
        _settingsViewModel = State(initialValue: SettingsViewModel())
        _importExportViewModel = State(initialValue: ChecklistImportExportViewModel(store: store))
        _backgroundViewModel = State(initialValue: BackgroundViewModel())
        _appearanceViewModel = State(initialValue: AppearanceViewModel())
        _syncService = State(initialValue: syncService)
    }

    var body: some Scene {
        #if os(macOS)
            // SwiftUI's macOS scene restore blindly replays the persisted window
            // frame from the preferences — once off-screen it stays unreachable and
            // the close button can never be clicked. Opting out of scene
            // restoration gives the window SwiftUI's default on-screen geometry
            // every launch instead.
            WindowGroup {
                ContentView()
                    .environment(store)
                    .environment(listViewModel)
                    .environment(runViewModel)
                    .environment(settingsViewModel)
                    .environment(importExportViewModel)
                    .environment(backgroundViewModel)
                    .environment(appearanceViewModel)
                    .environment(syncService)
                    .environment(\.locale, AppLocaleState.current.effectiveLocale)
                    .task { await syncService.syncOnLaunch() }
            }
            .restorationBehavior(.disabled)
            .onChange(of: scenePhase) { _, phase in
                // Flush coalesced text edits and push before the app suspends.
                if phase != .active {
                    store.flushPendingSave()
                    syncService.pushNow()
                }
            }
        #else
            WindowGroup {
                ContentView()
                    .environment(store)
                    .environment(listViewModel)
                    .environment(runViewModel)
                    .environment(settingsViewModel)
                    .environment(importExportViewModel)
                    .environment(backgroundViewModel)
                    .environment(appearanceViewModel)
                    .environment(syncService)
                    .environment(\.locale, AppLocaleState.current.effectiveLocale)
                    #if os(iOS)
                        .task {
                            if coordinator == nil {
                                let coordinator = ChecklistSyncCoordinator(
                                    transport: PhoneSyncAdapter(),
                                    snapshot: { store.checklists },
                                    createReminders: { await ChecklistReminders.create(from: $0) },
                                    language: { AppLocaleState.current.language })
                                self.coordinator = coordinator
                                coordinator.start()
                            }
                        }
                        .onChange(of: store.checklists) { _, _ in
                            coordinator?.checklistsDidChange()
                        }
                        // The language picker writes straight to the holder, so
                        // push on the change itself: `start()`/`onActivated`
                        // fire once per session and would leave a mid-session
                        // change unseen until a process restart.
                        .onChange(of: AppLocaleState.current.language) { _, _ in
                            coordinator?.languageDidChange()
                        }
                    #endif
                    .task { await syncService.syncOnLaunch() }
            }
            .onChange(of: scenePhase) { _, phase in
                // Flush coalesced text edits and push before the app suspends.
                if phase != .active {
                    store.flushPendingSave()
                    syncService.pushNow()
                }
            }
        #endif
    }
}