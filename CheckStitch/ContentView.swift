import EventKit
import os
import SwiftUI

struct ContentView: View {
    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "Checklist")
    var body: some View {
        Button("checklist") {
            Task { await createChecklistReminders() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    func createChecklistReminders() async {
        let eventStore = EKEventStore()
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            if !granted { return }
            for title in ["one", "two", "three"] {
                let reminder = EKReminder(eventStore: eventStore)
                reminder.title = title
                reminder.calendar = eventStore.defaultCalendarForNewReminders()
                try eventStore.save(reminder, commit: true)
            }
        } catch {
            Self.logger.error("Failed to create checklist reminders: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#Preview {
    ContentView()
}
