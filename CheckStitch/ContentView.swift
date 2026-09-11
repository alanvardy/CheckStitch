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
    @State private var isShowingSettings = false
    @State private var isCreatingChecklist = false
    @State private var isChecklistCreated = false

    @AppStorage("appearanceMode")
    var appearanceMode = AppearanceMode.system

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 16) {
                createChecklistButton
                editChecklistButton
            }
            .frame(maxWidth: ChecklistWidth.maxContentWidth(viewportWidth: geometry.size.width))
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onChange(of: appearanceMode) { _, new in
            #if os(iOS)
                AppDelegate.applyAppearance(new)
            #endif
            #if os(macOS)
                MacAppDelegate.applyAppearance(new)
            #endif
        }
        .sheet(isPresented: $isShowingEditChecklist) {
            EditChecklistView(name: $checklistName, items: $items)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(appearanceMode: $appearanceMode)
        }
        .overlay(alignment: .topTrailing) {
            settingsButton
                .padding(.top, 8)
                .padding(.trailing, 12)
        }
    }

    private var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.tint, lineWidth: 2)
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("settingsButton")
    }

    private var createChecklistButton: some View {
        Button {
            Task {
                isCreatingChecklist = true
                // Hold the spinner for at least a second so saving quickly
                // doesn't flash the progress feedback past the user.
                async let minimumSpinner: Void = Task.sleep(for: .seconds(1))
                await createChecklistReminders()
                try? await minimumSpinner
                isCreatingChecklist = false
                isChecklistCreated = true
                try? await Task.sleep(for: .seconds(1))
                isChecklistCreated = false
            }
        } label: {
            HStack(spacing: 8) {
                Text(checklistName)
                    .font(.title2.weight(.semibold))
                if isCreatingChecklist {
                    ProgressView()
                        .controlSize(.small)
                } else if isChecklistCreated {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
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
                // Skip blank titles so an emptied row can't produce a meaningless reminder.
                guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
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

/// Viewport-relative cap for the checklist content, mirroring SingleThread's
/// CardWidth. Returns `min(ceiling, fraction)` so the content hugs narrow
/// screens but never balloons on wide (iPad) screens.
///
/// `maxContentWidth` is `nonisolated` so the pure math stays callable outside
/// the app target's `MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`).
enum ChecklistWidth {
    nonisolated static func maxContentWidth(viewportWidth: CGFloat) -> CGFloat {
        min(340, viewportWidth * 0.6)
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

                    Button {
                        dismiss()
                    } label: {
                        Label("Remove Checklist", systemImage: "trash")
                    }
                    .accessibilityIdentifier("removeChecklistButton")
                }
            }
            .navigationTitle("Edit checklist")
            .toolbarTitleDisplayMode(.inline)
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
