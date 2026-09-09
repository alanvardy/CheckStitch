import EventKit
import SwiftUI

struct ContentView: View {
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
            return
        }
    }
}

#Preview {
    ContentView()
}
