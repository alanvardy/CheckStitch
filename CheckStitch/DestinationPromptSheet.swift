import CheckStitchCore
import SwiftUI

/// One-shot destination chooser for a `.prompt` checklist. Pure presentation:
/// `ChecklistRunViewModel` has already enumerated the options.
struct DestinationPromptSheet: View {
    let checklistName: String
    let options: [ReminderListOption]
    let defaultIdentifier: String?
    let onRun: (ChecklistDestination) -> Void
    let onCancel: () -> Void

    @State private var selection: ChecklistDestination = .systemDefault

    var body: some View {
        NavigationStack {
            Form {
                Section("Destination list") {
                    Picker("List", selection: $selection) {
                        Text("Default (Inbox)").tag(ChecklistDestination.systemDefault)
                        ForEach(options) { list in
                            Text(list.title).tag(ChecklistDestination.list(list.id))
                        }
                    }
                    .accessibilityIdentifier("destinationPromptPicker")
                }
            }
            .navigationTitle("Choose a list")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Run") { onRun(selection) }
                        .accessibilityIdentifier("destinationPromptRunButton")
                }
            }
        }
    }
}