import CheckStitchCore
import EventKit // required by the `#Preview` environment construction below
import SwiftUI

struct ContentView: View {
    @State private var viewModel: ChecklistViewModel
    @State private var isShowingEditChecklist = false
    @State private var isShowingSettings = false

    @AppStorage(AppearanceModePreference.defaultsKey)
    var appearanceMode = AppearanceMode.system

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: ChecklistViewModel(environment: environment))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
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
        #if os(macOS)
        .preferredColorScheme(appearanceMode.colorScheme)
        #endif
        .sheet(isPresented: $isShowingEditChecklist) {
            EditChecklistView(name: $viewModel.checklistName, items: $viewModel.items)
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
        .checkStitchButton()
    }

    private var createChecklistButton: some View {
        Button {
            Task {
                await viewModel.createChecklist()
                if viewModel.isChecklistCreated {
                    // Flash the checkmark for a beat.
                    try? await Task.sleep(for: .seconds(1))
                    viewModel.dismissCreatedFeedback()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(viewModel.checklistName)
                    .font(.title2.weight(.semibold))
                if viewModel.isCreatingChecklist {
                    ProgressView()
                        .controlSize(.small)
                } else if viewModel.isChecklistCreated {
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
        .accessibilityLabel("Create checklist named \(viewModel.checklistName)")
        .accessibilityIdentifier("checklistButton")
        .checkStitchButton()
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
        .checkStitchButton()
    }
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
                    .checkStitchButton()

                    Button {
                        dismiss()
                    } label: {
                        Label("Remove Checklist", systemImage: "trash")
                    }
                    .accessibilityIdentifier("removeChecklistButton")
                    .checkStitchButton()
                }
            }
            .navigationTitle("Edit checklist")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .checkStitchButton()
                }
            }
        }
    }

    private func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }
}

#Preview {
    ContentView(environment: AppEnvironment(
        reminderCreator: EventKitReminderCreator(eventStore: EKEventStore())))
}
