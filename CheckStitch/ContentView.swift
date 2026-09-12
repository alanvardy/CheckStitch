import SwiftUI

struct ContentView: View {
    @Environment(ChecklistStore.self) private var store

    @AppStorage("appearanceMode")
    var appearanceMode = AppearanceMode.system

    @State private var path: [UUID] = []
    /// Transient per-checklist reminder feedback, keyed by id — never persisted.
    @State private var creating: Set<UUID> = []
    @State private var created: Set<UUID> = []
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.checklists.isEmpty {
                    emptyState
                } else {
                    checklistList
                }
            }
            .navigationTitle("Checklists")
            .toolbar {
                ToolbarItem(placement: createButtonPlacement) {
                    Button {
                        createChecklist()
                    } label: {
                        Label("Create checklist", systemImage: "plus")
                    }
                    .accessibilityIdentifier("createChecklistButton")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ChecklistDetailView(checklistID: id)
            }
        }
        .onChange(of: appearanceMode) { _, new in
            #if os(iOS)
                AppDelegate.applyAppearance(new)
            #endif
            #if os(macOS)
                MacAppDelegate.applyAppearance(new)
            #endif
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

    /// `topBarLeading` is iOS-only; on macOS the leading navigation slot is
    /// the same visual position.
    private var createButtonPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .topBarLeading
        #else
            .navigation
        #endif
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

    private var checklistList: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.checklists) { checklist in
                        checklistRow(for: checklist)
                        if checklist.id != store.checklists.last?.id {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: ChecklistWidth.maxContentWidth(viewportWidth: geometry.size.width))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.tint, lineWidth: 2)
                )
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    /// One checklist row inside the width-capped card: the name navigates to
    /// the detail screen, the play button turns the list into reminders.
    private func checklistRow(for checklist: Checklist) -> some View {
        HStack(spacing: 12) {
            NavigationLink(checklist.name, value: checklist.id)
                .frame(maxWidth: .infinity, alignment: .leading)
            createRemindersButton(for: checklist.id)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No checklists", systemImage: "checklist")
        } description: {
            Text("Create a checklist to turn its items into reminders.")
        } actions: {
            Button("Create checklist") { createChecklist() }
                .accessibilityIdentifier("emptyStateCreateButton")
        }
    }

    @ViewBuilder
    private func createRemindersButton(for id: UUID) -> some View {
        Button {
            createReminders(for: id)
        } label: {
            if creating.contains(id) {
                ProgressView()
                    .controlSize(.small)
            } else if created.contains(id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "play.circle.fill")
            }
        }
        .buttonStyle(.borderless)
        .disabled(creating.contains(id))
        .accessibilityLabel("Create reminders from checklist")
        .accessibilityIdentifier("createRemindersButton")
    }

    private func createChecklist() {
        let checklist = store.create()
        path.append(checklist.id)
    }

    private func createReminders(for id: UUID) {
        // Mark the checklist as creating before spawning the task so a second
        // tap can't enqueue duplicate reminders while the first task starts.
        guard !creating.contains(id), let checklist = store.checklist(id: id) else { return }
        creating.insert(id)
        Task {
            // Hold the spinner for at least a second so saving quickly
            // doesn't flash the progress feedback past the user.
            async let minimumSpinner: Void = Task.sleep(for: .seconds(1))
            await ChecklistReminders.create(from: checklist)
            try? await minimumSpinner
            creating.remove(id)
            created.insert(id)
            try? await Task.sleep(for: .seconds(1))
            created.remove(id)
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

#Preview {
    ContentView()
        .environment(ChecklistStore())
}
