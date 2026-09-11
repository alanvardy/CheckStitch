import SwiftUI
#if os(iOS)
    import UIKit
#endif

@main struct MyApp: App {
    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self)
        private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
