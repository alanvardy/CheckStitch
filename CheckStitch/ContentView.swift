import SwiftUI

struct ContentView: View {
    @Environment(ChecklistStore.self) private var store

    @AppStorage("appearanceMode")
    var appearanceMode = AppearanceMode.system
    @AppStorage("backgroundEnabled") var backgroundEnabled = true
    @AppStorage("backgroundFadePercent") var backgroundFadePercent = BackgroundFade.defaultValue
    @AppStorage("backgroundPinned") var backgroundPinned = false

    @State private var path: [UUID] = []
    /// Transient per-checklist reminder feedback, keyed by id — never persisted.
    @State private var creating: Set<UUID> = []
    @State private var created: Set<UUID> = []
    @State private var isShowingSettings = false
    @State private var backgroundImage = BackgroundImageStore()
    @State private var settingsBag: SettingsBindings?

    var body: some View {
        ZStack {
            Color.systemBackground.ignoresSafeArea()
            BackgroundPhotoLayer(
                imageData: backgroundImage.imageData,
                isEnabled: backgroundEnabled,
                opacity: BackgroundFade.opacity(for: backgroundFadePercent))
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
                    #if os(macOS)
                        // macOS window actions belong in the title bar, and a
                        // view-level overlay there drifts into the content area.
                        // Trailing keeps the gear in the corner beside create.
                        ToolbarItem(placement: .primaryAction) {
                            settingsButton
                        }
                    #endif
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
            #if os(macOS)
                // The canvas does not pick up the window-level NSWindow.appearance,
                // so thread the scheme through SwiftUI content as well
                // (mirrors the 974 macOS-canvas fix).
                .preferredColorScheme(appearanceMode.colorScheme)
            #endif
            .sheet(isPresented: $isShowingSettings) {
                if let bag = settingsBag {
                    settingsSheetWritebacks(bag)
                }
            }
            .onChange(of: isShowingSettings) { _, showing in
                if !showing { settingsBag = nil }
            }
            #if os(iOS)
                // The overlay hangs off the whole `NavigationStack`, so without
                // the empty-path guard it floats over every pushed screen too —
                // on the detail screen it lands on top of the Done button. Only
                // the root list screen owns this gear.
                .overlay(alignment: .topTrailing) {
                    if path.isEmpty {
                        settingsButton
                            .padding(.top, 8)
                            .padding(.trailing, 12)
                    }
                }
            #endif
        }
        .task {
            // Pin BEFORE the first refresh so a pinned cold launch never
            // refetches a stale stored image (mirrors SingleThread's ordering).
            await backgroundImage.setPinned(backgroundPinned)
            await backgroundImage.refreshIfNeeded()
        }
        .onChange(of: backgroundPinned) { _, pin in
            Task { await backgroundImage.setPinned(pin) }
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

    /// iOS floats the gear as its own 52×52 plate over the content area. A
    /// macOS title bar is about that tall and draws its own button chrome, so
    /// macOS shows the plain glyph and keeps the native style — mirroring how
    /// the create button is built above.
    private var settingsButton: some View {
        #if os(iOS)
            Button {
                settingsBag = makeSettingsBag()
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
        #else
            Button {
                settingsBag = makeSettingsBag()
                isShowingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
        #endif
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

extension ContentView {
    /// Renders the Settings sheet over the staged bag and writes each staged
    /// change back to the `@AppStorage`-backed property so it survives relaunch.
    func settingsSheetWritebacks(_ bag: SettingsBindings) -> some View {
        SettingsView(
            appearanceMode: $appearanceMode,
            bindings: bag,
            backgroundImage: backgroundImage)
            .onChange(of: bag.backgroundEnabled) { _, _ in writeBack(bag) }
            .onChange(of: bag.backgroundFadePercent) { _, _ in writeBack(bag) }
            .onChange(of: bag.backgroundPinned) { _, _ in writeBack(bag) }
    }

    /// Persists every staged background preference. Extracted so it is
    /// exercisable without a live SwiftUI hierarchy (see SettingsBindingsTests).
    func writeBack(_ bag: SettingsBindings) {
        backgroundEnabled = bag.backgroundEnabled
        backgroundFadePercent = bag.backgroundFadePercent
        backgroundPinned = bag.backgroundPinned
    }

    /// Fresh bag snapshotted from the current stored preferences on sheet open.
    func makeSettingsBag() -> SettingsBindings {
        SettingsBindings(
            backgroundEnabled: backgroundEnabled,
            backgroundFadePercent: backgroundFadePercent,
            backgroundPinned: backgroundPinned)
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
