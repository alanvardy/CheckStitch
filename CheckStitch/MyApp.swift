import CheckStitchCore
import EventKit // EKEventStore() below — EventKit symbol, same plan-gap as ContentView's preview
import SwiftUI
#if os(iOS)
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif

@main struct MyApp: App {
    // One long-lived store for the app: EKReminder weakly references it, and a
    // fresh store per creation would be deallocated underneath the reminders.
    private let environment = AppEnvironment(
        reminderCreator: EventKitReminderCreator(eventStore: EKEventStore()))

    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self)
        private var appDelegate
    #endif
    #if os(macOS)
        @NSApplicationDelegateAdaptor(MacAppDelegate.self)
        private var macAppDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView(environment: environment)
        }
    }
}