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

    @State private var store = ChecklistStore()
    @Environment(\.scenePhase) private var scenePhase

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
            }
            .restorationBehavior(.disabled)
            .onChange(of: scenePhase) { _, phase in
                // Flush coalesced text edits before the app suspends.
                if phase != .active { store.flushPendingSave() }
            }
        #else
            WindowGroup {
                ContentView()
                    .environment(store)
            }
            .onChange(of: scenePhase) { _, phase in
                // Flush coalesced text edits before the app suspends.
                if phase != .active { store.flushPendingSave() }
            }
        #endif
    }
}
