import EventKit
import os
import SwiftUI

struct ContentView: View {
    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "Checklist")

    @State private var checklistName = "checklist"
    @State private var items = [
        ChecklistItem(title: "one"),
        ChecklistItem(title: "two"),
        ChecklistItem(title: "three"),
    ]
    @State private var isShowingEditChecklist = false

    var body: some View {
        HStack(spacing: 16) {
            createChecklistButton
            editChecklistButton
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .sheet(isPresented: $isShowingEditChecklist) {
            EditChecklistView(name: $checklistName, items: $items)
        }
    }

    private var createChecklistButton: some View {
        Button {
            Task { await createChecklistReminders() }
        } label: {
            Text(checklistName)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.tint, lineWidth: 2)
                )
        }
        .accessibilityLabel("Create checklist named \(checklistName)")
        .accessibilityIdentifier("checklistButton")
    }

    private var editChecklistButton: some View {
        Button {
            isShowingEditChecklist = true
        } label: {
            Image(systemName: "pencil")
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.tint, lineWidth: 2)
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Edit checklist")
        .accessibilityIdentifier("editChecklistButton")
    }

    func createChecklistReminders() async {
        let eventStore = EKEventStore()
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            if !granted { return }
            // One reminder per checklist item, in the Reminders Inbox.
            for item in items {
                let reminder = EKReminder(eventStore: eventStore)
                reminder.title = item.title
                reminder.calendar = eventStore.defaultCalendarForNewReminders()
                try eventStore.save(reminder, commit: true)
            }
        } catch {
            Self.logger.error("Failed to create checklist reminders: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Editable row model for a checklist item. The ID is stable so rows can be
/// added, removed, and edited without conflating duplicate titles.
struct ChecklistItem: Identifiable {
    let id = UUID()
    var title: String
}

/// Overlay sheet for renaming the checklist and adding, removing, and editing
/// its items.
struct EditChecklistView: View {
    @Binding var name: String
    @Binding var items: [ChecklistItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Checklist name") {
                    TextField("Checklist name", text: $name)
                        .accessibilityIdentifier("checklistNameField")
                }
                Section("Items") {
                    ForEach($items) { $item in
                        TextField("Item", text: $item.title)
                    }
                    .onDelete(perform: remove)
                }
                Section {
                    Button {
                        items.append(ChecklistItem(title: "New item"))
                    } label: {
                        Label("Add Item", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("addItemButton")
                }
            }
            .navigationTitle("Edit checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }
}

#Preview {
    ContentView()
}
