import CheckStitchCore
import SwiftUI
import CheckStitchCore
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(ChecklistStore.self) private var store
    @Environment(ChecklistSyncService.self) private var syncService
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("appearanceMode")
    var appearanceMode = AppearanceMode.system
    @AppStorage("backgroundEnabled") var backgroundEnabled = true
    @AppStorage("backgroundFadePercent") var backgroundFadePercent = BackgroundFade.defaultValue
    @AppStorage("backgroundPinned") var backgroundPinned = false
    @AppStorage("textSize") var textSize = TextSize.system
    @AppStorage("allowsLandscape") var allowsLandscape = true

    @State private var path: [UUID] = []
    /// Present when the main-screen rows are in edit mode (remove/move
    /// controls instead of navigation and the run button).
    @State private var isEditing = false
    /// The checklist waiting for its confirm/cancel in the remove dialog;
    /// `nil` hides it.
    @State private var checklistPendingRemoval: UUID?
    /// Transient per-checklist reminder feedback, keyed by id — never persisted.
    @State private var creating: Set<UUID> = []
    @State private var created: Set<UUID> = []
    @State private var isShowingSettings = false
    /// Import/export chosen in the Settings menu, handed over once the settings
    /// sheet has dismissed (see `requestDataAction`).
    @State private var dataActionQueue = SettingsDataActionQueue()
    @State private var backgroundImage = BackgroundImageStore()
    @State private var settingsBag: SettingsBindings?
    /// Message for the run-failure alert; `nil` hides it. Set only when a run
    /// produced no reminders (missing destination, permission, or a thrown error).
    @State private var runErrorMessage: String?
    @State private var isShowingExport = false
    @State private var exportSelection: Set<UUID> = []
    @State private var exportDocument: ChecklistExportDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importSession: ChecklistImportSession?
    @State private var conflict: ChecklistImportCandidate?
    @State private var importErrorMessage: String?
    @State private var exportErrorMessage: String?

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
                #if os(macOS)
                    .toolbar {
                        ToolbarItem(placement: createButtonPlacement) {
                            createButton
                        }
                        // macOS window actions belong in the title bar, and a
                        // view-level overlay there drifts into the content area.
                        // Trailing keeps the gear in the corner beside create.
                        ToolbarItem(placement: .primaryAction) {
                            settingsButton
                        }
                        // Edit is hidden while the list is empty: the empty
                        // state owns that screen, and a stray edit toggle
                        // there would edit nothing.
                        if !store.checklists.isEmpty {
                            ToolbarItem(placement: .primaryAction) {
                                editToggleButton
                            }
                        }
                    }
                #endif
                .navigationDestination(for: UUID.self) { id in
                    ChecklistDetailView(checklistID: id)
                }
                #if os(iOS)
                    // iOS 26's NavigationStack paints an opaque container behind
                    // its content, so the ZStack photo is invisible on iPhone/iPad
                    // (macOS's stack is already transparent). Clearing the
                    // navigation container background lets the photo show.
                    .containerBackground(.clear, for: .navigation)
                #endif
                .safeAreaInset(edge: .bottom) {
                    SyncStatusView(outcome: syncService.lastOutcome, isSyncing: syncService.isSyncing)
                }
                // On the `Group` so the empty state is refreshable too — a fresh
                // device has no rows to pull down, and that is exactly when a
                // manual force-refresh matters most.
                .refreshable { _ = await syncService.refresh() }
                .alert("Couldn't import",
                       isPresented: Binding(get: { importErrorMessage != nil },
                                            set: { if !$0 { importErrorMessage = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: { Text(importErrorMessage ?? "") }
            }
            .onChange(of: appearanceMode) { _, new in
                #if os(iOS)
                    AppDelegate.applyAppearance(new)
                #endif
                #if os(macOS)
                    MacAppDelegate.applyAppearance(new)
                #endif
            }
            .onChange(of: allowsLandscape) { _, new in
                #if os(iOS)
                    AppDelegate.applyLock(allowsLandscape: new)
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
                guard !showing else { return }
                settingsBag = nil
                guard let action = dataActionQueue.take() else { return }
                // The file panels live on this root view: a sheet-nested
                // `.fileExporter` never presents on macOS. So the settings
                // sheet has to finish dismissing before the panel is asked for.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    perform(action)
                }
            }
            #if os(iOS)
                // The chrome plates float as overlays instead of toolbar
                // items: iOS 26's navigation toolbar paints a translucent
                // chip plate behind its buttons (visible on device), and an
                // overlay button does not. The matching top padding keeps the
                // 52×52 plates on one row (create leading, settings trailing);
                // the empty-path guard keeps them off pushed screens, whose
                // own toolbars own the top bar. Import/export live in the
                // settings sheet, not on the root chrome.
                .overlay(alignment: .topLeading) {
                    if path.isEmpty {
                        createButton
                            .padding(.top, 8)
                            .padding(.leading, 12)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if path.isEmpty {
                        settingsButton
                            .padding(.top, 8)
                            .padding(.trailing, 12)
                    }
                }
            #endif
        }
        .modifier(TextSizeModifier(textSize: textSize))
        .task {
            // Pin BEFORE the first refresh so a pinned cold launch never
            // refetches a stale stored image (mirrors SingleThread's ordering).
            await backgroundImage.setPinned(backgroundPinned)
            await backgroundImage.refreshIfNeeded()
        }
        .onChange(of: backgroundPinned) { _, pin in
            Task { await backgroundImage.setPinned(pin) }
        }
        .alert("Couldn't create reminders", isPresented: Binding(
            get: { runErrorMessage != nil },
            set: { if !$0 { runErrorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("runErrorMessageButton")
        } message: {
            Text(runErrorMessage ?? "")
        }
        .sheet(isPresented: $isShowingExport) {
            ExportChecklistsView(selection: $exportSelection) { exportSelected() }
        }
        .fileExporter(isPresented: $isExporting,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: ChecklistExport.filename()) { result in
            if case .failure(let error) = result { exportErrorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): importFile(at: url)
            case .failure(let error): importErrorMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Name conflict",
                            isPresented: conflictPresented,
                            presenting: conflict) { candidate in
            Button("Replace") { choose(.replace) }
            Button("Keep Both") { choose(.keepBoth) }
            Button("Keep Existing", role: .cancel) { choose(.keepExisting) }
        } message: { candidate in
            Text("“\(candidate.checklist.name)” already exists.")
        }
        .alert("Couldn't export",
               isPresented: Binding(get: { exportErrorMessage != nil },
                                    set: { if !$0 { exportErrorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportErrorMessage ?? "") }
        // Two-step removal gate, mirroring the detail screen: the per-row
        // minus only raises this dialog, and its destructive button performs
        // the removal.
        .confirmationDialog(
            "Remove Checklist",
            isPresented: Binding(get: { checklistPendingRemoval != nil },
                                 set: { if !$0 { checklistPendingRemoval = nil } }),
            presenting: checklistPendingRemoval
        ) { id in
            Button("Remove", role: .destructive) {
                // Clear the pending id explicitly rather than relying on the
                // dialog's dismissal to fire the `isPresented` setter.
                checklistPendingRemoval = nil
                removeChecklist(id: id)
            }
            .accessibilityIdentifier("confirmRemoveChecklistButton")
            Button("Cancel", role: .cancel) { checklistPendingRemoval = nil }
                .accessibilityIdentifier("cancelRemoveChecklistButton")
        } message: { _ in
            Text("This removes the checklist and all its items.")
        }
        // Leave edit mode when the last checklist goes: the empty state has no
        // toggle, so a later create must not open into a stale edit state.
        .onChange(of: store.checklists.isEmpty) { _, isEmpty in
            if isEmpty { isEditing = false }
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

    /// iOS floats both plates over the content area as matched overlays
    /// (see the overlay comment in `body`). A macOS title bar is about that
    /// tall and draws its own button chrome, so macOS shows the plain glyph
    /// and keeps the native style.
    private var createButton: some View {
        #if os(iOS)
            Button {
                createChecklist()
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(CardPlate.iconForeground(for: colorScheme))
                    .frame(width: 52, height: 52)
                    .background {
                        RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                            .fill(CardPlate.iconPlateFill(for: colorScheme))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                            .stroke(.tint, lineWidth: 2)
                    )
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Create checklist")
            .accessibilityIdentifier("createChecklistButton")
            .checkStitchButton()
        #else
            Button {
                createChecklist()
            } label: {
                Label("Create checklist", systemImage: "plus")
            }
            .accessibilityIdentifier("createChecklistButton")
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
                    .foregroundStyle(CardPlate.iconForeground(for: colorScheme))
                    .frame(width: 52, height: 52)
                    .background {
                        RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                            .fill(CardPlate.iconPlateFill(for: colorScheme))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
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

    /// Shared by the macOS toolbar and the iOS in-content header row. The bare
    /// "Edit" key is new; "Done" is already registered.
    private var editToggleButton: some View {
        Button(isEditing ? "Done" : "Edit") {
            withAnimation { isEditing.toggle() }
        }
        .accessibilityIdentifier("editChecklistsButton")
    }

    private var checklistList: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    #if os(iOS)
                        // No toolbar on the iOS root, and both chrome corners
                        // are taken by the create/settings plates, so the edit
                        // toggle lives in the scroll content as a right-aligned
                        // header row sharing the card's 32pt margins. Plated
                        // like the chrome buttons so it stays legible over the
                        // photo.
                        HStack {
                            Spacer()
                            editToggleButton
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background {
                                    RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                                        .fill(CardPlate.iconPlateFill(for: colorScheme))
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                                        .stroke(.tint, lineWidth: 2)
                                )
                        }
                        .frame(maxWidth: ChecklistWidth.maxContentWidth(viewportWidth: geometry.size.width))
                        .padding(.horizontal, 32)
                        .padding(.bottom, 8)
                    #endif
                    LazyVStack(spacing: 0) {
                        ForEach(store.checklists) { checklist in
                            checklistRow(for: checklist)
                            if checklist.id != store.checklists.last?.id {
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: ChecklistWidth.maxContentWidth(viewportWidth: geometry.size.width))
                    // Off-white/black plate keeps the rows readable over the photo —
                    // SingleThread's card treatment at CheckStitch's 14pt radius.
                    .background {
                        RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                            .fill(CardPlate.plateFill(for: colorScheme))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                            .stroke(.tint, lineWidth: 2)
                    )
                    .padding(.horizontal, 32)
                }
                #if os(iOS)
                    // Start below the floating 52×52 chrome plates (8pt top
                    // inset + 52pt tall) with extra headroom below them.
                    .padding(.top, CardPlate.checklistTopMargin)
                #else
                    .padding(.top, 16)
                #endif
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    /// One checklist row inside the width-capped card: the name navigates to
    /// the detail screen, the play button turns the list into reminders. In
    /// edit mode the row swaps to a leading remove control and plain name text,
    /// so a tap can neither push the detail screen nor create reminders.
    private func checklistRow(for checklist: Checklist) -> some View {
        HStack(spacing: 12) {
            if isEditing {
                Button {
                    checklistPendingRemoval = checklist.id
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove")
                .accessibilityIdentifier("removeChecklist-\(checklist.id.uuidString)")
            }
            if isEditing {
                Text(checklist.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                checklistMoveControls(for: checklist)
            } else {
                NavigationLink(checklist.name, value: checklist.id)
                    .frame(maxWidth: .infinity, alignment: .leading)
                createRemindersButton(for: checklist.id)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Trailing per-row move controls in edit mode. The first row cannot move
    /// up and the last cannot move down, so those chevrons are disabled.
    @ViewBuilder
    private func checklistMoveControls(for checklist: Checklist) -> some View {
        HStack(spacing: 4) {
            Button { moveChecklist(checklist.id, up: true) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(store.checklists.first?.id == checklist.id)
            .accessibilityLabel("Move up")
            .accessibilityIdentifier("moveChecklistUp-\(checklist.id.uuidString)")

            Button { moveChecklist(checklist.id, up: false) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(store.checklists.last?.id == checklist.id)
            .accessibilityLabel("Move down")
            .accessibilityIdentifier("moveChecklistDown-\(checklist.id.uuidString)")
        }
    }

    private var emptyState: some View {
        // Wrapped in a `ScrollView` so the `Group`'s `.refreshable` has a
        // scrollable host on a device with no local checklists yet.
        ScrollView {
            ContentUnavailableView {
                Label("No checklists", systemImage: "checklist")
            } description: {
                Text("Create a checklist to turn its items into reminders.")
            } actions: {
                Button("Create checklist") { createChecklist() }
                    .accessibilityIdentifier("emptyStateCreateButton")
            }
            .padding(.top, 80)
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
        // `create()` disambiguates a duplicate name ("New checklist 2") rather
        // than failing, so there is always a checklist to open.
        path.append(store.create().id)
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
            let outcome = await ChecklistReminders.create(from: checklist)
            try? await minimumSpinner
            creating.remove(id)
            switch outcome {
            case .created:
                created.insert(id)
                try? await Task.sleep(for: .seconds(1))
                created.remove(id)
            case .destinationMissing, .permissionDenied, .partiallyCreated, .failed:
                // Never flash success: nothing (or only part) was created.
                runErrorMessage = outcome.errorMessage
            }
        }
    }

    /// Performs the destructive half of the removal gate: a single-row batch
    /// into the store's `removeChecklists` (one tombstone, one save). The
    /// animation transaction makes the row's removal (and any new last-row
    /// divider) animate.
    private func removeChecklist(id: UUID) {
        guard let index = store.checklists.firstIndex(where: { $0.id == id }) else { return }
        withAnimation { store.removeChecklists(at: IndexSet(integer: index)) }
    }

    /// Converts a one-row nudge into the `moved` index arithmetic: one row up
    /// is `destination == index - 1`, one row down is `index + 2` (the
    /// destination is adjusted for the removed element). The animation
    /// transaction is what makes the swap animate in the `LazyVStack`.
    private func moveChecklist(_ id: UUID, up: Bool) {
        guard let index = store.checklists.firstIndex(where: { $0.id == id }) else { return }
        withAnimation {
            store.moveChecklists(from: IndexSet(integer: index), to: up ? index - 1 : index + 2)
        }
    }
}

extension ContentView {
    /// Write-through language binding: reads the live holder (so a value that
    /// arrives over sync or lands from another scene updates the picker) and
    /// persists immediately on change — no staging bag (design decision 9).
    var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLocaleState.current.language },
            set: { AppLocaleState.current.set($0) })
    }

    /// Renders the Settings sheet over the staged bag and writes each staged
    /// change back to the `@AppStorage`-backed property so it survives relaunch.
    func settingsSheetWritebacks(_ bag: SettingsBindings) -> some View {
        SettingsView(
            appearanceMode: $appearanceMode,
            appLanguage: appLanguageBinding,
            bindings: bag,
            backgroundImage: backgroundImage,
            onExport: { requestDataAction(.export) },
            onImport: { requestDataAction(.importChecklists) })
            .onChange(of: bag.backgroundEnabled) { _, _ in writeBack(bag) }
            .onChange(of: bag.backgroundFadePercent) { _, _ in writeBack(bag) }
            .onChange(of: bag.backgroundPinned) { _, _ in writeBack(bag) }
            .onChange(of: bag.textSize) { _, _ in writeBack(bag) }
            .onChange(of: bag.allowsLandscape) { _, _ in writeBack(bag) }
    }

    /// Persists every staged background preference. Extracted so it is
    /// exercisable without a live SwiftUI hierarchy (see SettingsBindingsTests).
    func writeBack(_ bag: SettingsBindings) {
        backgroundEnabled = bag.backgroundEnabled
        backgroundFadePercent = bag.backgroundFadePercent
        backgroundPinned = bag.backgroundPinned
        textSize = bag.textSize
        allowsLandscape = bag.allowsLandscape
    }

    /// Fresh bag snapshotted from the current stored preferences on sheet open.
    func makeSettingsBag() -> SettingsBindings {
        SettingsBindings(
            backgroundEnabled: backgroundEnabled,
            backgroundFadePercent: backgroundFadePercent,
            backgroundPinned: backgroundPinned,
            textSize: textSize,
            allowsLandscape: allowsLandscape)
    }

    /// Stages an import/export chosen in the Settings menu and closes the sheet,
    /// so the root-owned file panel presents unobstructed.
    private func requestDataAction(_ action: SettingsDataAction) {
        dataActionQueue.stage(action)
        isShowingSettings = false
    }

    /// Opens the panel the Settings menu staged, once the settings sheet has
    /// dismissed.
    private func perform(_ action: SettingsDataAction) {
        switch action {
        case .export: beginExport()
        case .importChecklists: isImporting = true
        }
    }

    private func beginExport() {
        exportSelection = []
        isShowingExport = true
    }

    private func exportSelected() {
        isShowingExport = false
        let selected = store.checklists.filter { exportSelection.contains($0.id) }
        guard !selected.isEmpty else { return }
        do {
            exportDocument = try ChecklistExportDocument(checklists: selected)
            isExporting = true
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func importFile(at url: URL) {
        // Security-scoped URLs require an access/stop pair around the read; a
        // missing pair silently yields unreadable data on device.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // A read failure (missing file, permissions) is not a format
            // problem: report the system's description rather than mislabelling
            // it as an unreadable export.
            importErrorMessage = error.localizedDescription
            return
        }

        let session = ChecklistImportSession(store: store)
        do {
            try session.prepare(data: data)
        } catch let error as ChecklistImportError {
            importErrorMessage = error.message
            return
        } catch {
            importErrorMessage = "This file isn't a CheckStitch export."
            return
        }
        importSession = session
        conflict = session.pending.first
    }

    /// `conflict` is a snapshot of `pending.first`; each decision clears it before
    /// advancing, so SwiftUI's own dismissal (setter fires `false`) cannot
    /// double-handle the next candidate.
    private var conflictPresented: Binding<Bool> {
        Binding(
            get: { conflict != nil },
            set: { presented in
                guard !presented, let current = conflict else { return }
                conflict = nil
                importSession?.decide(.keepExisting, for: current.id)
                advanceConflict()
            }
        )
    }

    private func choose(_ decision: ImportDecision) {
        guard let current = conflict else { return }
        conflict = nil
        importSession?.decide(decision, for: current.id)
        advanceConflict()
    }

    /// Re-presents after the current dismissal completes, so the next conflict in
    /// the FIFO queue is shown until the queue is empty.
    private func advanceConflict() {
        DispatchQueue.main.async {
            conflict = importSession?.pending.first
        }
    }
}

/// Import/export entry points offered by the Settings menu.
enum SettingsDataAction: Equatable {
    case export
    case importChecklists
}

/// Stages a Settings-menu import/export request until the settings sheet has
/// dismissed and the root-owned file panel can present.
struct SettingsDataActionQueue {
    private var pending: SettingsDataAction?

    mutating func stage(_ action: SettingsDataAction) {
        pending = action
    }

    /// Hands the staged action over exactly once, so a dismissal callback that
    /// fires again cannot open a second panel.
    mutating func take() -> SettingsDataAction? {
        defer { pending = nil }
        return pending
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

/// Honest sync feedback: nothing when healthy, an activity line while syncing,
/// and the failure reason otherwise.
struct SyncStatusView: View {
    let outcome: SyncOutcome?
    let isSyncing: Bool

    /// Text shown under the list; `nil` when there is nothing to report.
    var message: String? {
        if isSyncing { return "Syncing…" }
        switch outcome {
        case .failed(let reason): return reason
        // Surfaced rather than swallowed: a newer-payload guard or a read
        // failure must not leave pull-to-refresh looking like a silent no-op.
        case .unavailable: return "iCloud unavailable"
        case .synced, .seeded, .none: return nil
        }
    }

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                if isSyncing { ProgressView().controlSize(.small) }
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(8)
            .accessibilityIdentifier("syncStatusView")
        }
    }
}

#Preview {
    let store = ChecklistStore()
    ContentView()
        .environment(store)
        // Construction only: the preview never triggers read/write/synchronize.
        .environment(ChecklistSyncService(sync: UbiquitousChecklistSync(), store: store))
}
