import CheckStitchCore
import SwiftUI
import CheckStitchCore
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(ChecklistListViewModel.self) private var listVM
    @Environment(ChecklistRunViewModel.self) private var runVM
    @Environment(SettingsViewModel.self) private var settingsVM
    @Environment(ChecklistImportExportViewModel.self) private var importExportVM
    @Environment(BackgroundViewModel.self) private var backgroundVM
    @Environment(AppearanceViewModel.self) private var appearanceVM
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

    var body: some View {
        ZStack {
            Color.systemBackground.ignoresSafeArea()
            BackgroundPhotoLayer(
                imageData: backgroundVM.image.imageData,
                isEnabled: backgroundEnabled,
                opacity: BackgroundFade.opacity(for: backgroundFadePercent))
            NavigationStack(path: $path) {
                Group {
                    if listVM.checklists.isEmpty {
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
                        if !listVM.checklists.isEmpty {
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
                       isPresented: Binding(get: { importExportVM.importErrorMessage != nil },
                                            set: { if !$0 { importExportVM.clearImportError() } })) {
                    Button("OK", role: .cancel) {}
                } message: { Text(importExportVM.importErrorMessage ?? "") }
            }
            .onChange(of: appearanceMode) { _, new in
                appearanceVM.appearanceModeChanged(new)
            }
            .onChange(of: allowsLandscape) { _, new in
                appearanceVM.allowsLandscapeChanged(new)
            }
            #if os(macOS)
                // The canvas does not pick up the window-level NSWindow.appearance,
                // so thread the scheme through SwiftUI content as well
                // (mirrors the 974 macOS-canvas fix).
                .preferredColorScheme(appearanceMode.colorScheme)
            #endif
            .sheet(isPresented: Binding(get: { settingsVM.showsSettings },
                                        set: { settingsVM.showsSettings = $0 })) {
                if let bag = settingsVM.bag {
                    settingsSheetWritebacks(bag)
                }
            }
            .onChange(of: settingsVM.showsSettings) { _, showing in
                guard !showing else { return }
                settingsVM.sheetDidDismiss()
                guard let action = settingsVM.takeStaged() else { return }
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
            await backgroundVM.task(pinned: backgroundPinned)
        }
        .onChange(of: backgroundPinned) { _, pin in
            Task { await backgroundVM.setPinned(pin) }
        }
        .alert("Couldn't create reminders", isPresented: Binding(
            get: { runVM.runErrorMessage != nil },
            set: { if !$0 { runVM.clearRunError() } })
        ) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("runErrorMessageButton")
        } message: {
            Text(runVM.runErrorMessage ?? "")
        }
        .sheet(isPresented: Binding(get: { importExportVM.isShowingExport },
                                    set: { if !$0 { importExportVM.dismissExportSelection() } })) {
            ExportChecklistsView(
                selection: Binding(get: { importExportVM.exportSelection },
                                   set: { importExportVM.exportSelection = $0 })) {
                importExportVM.exportSelected()
            }
        }
        .fileExporter(isPresented: Binding(get: { importExportVM.isExporting },
                                           set: { if !$0 { importExportVM.dismissExport() } }),
                      document: importExportVM.exportDocument,
                      contentType: .json,
                      defaultFilename: ChecklistExport.filename()) { result in
            if case .failure(let error) = result { importExportVM.exportFailed(error) }
        }
        .fileImporter(isPresented: Binding(get: { importExportVM.isImporting },
                                           set: { if !$0 { importExportVM.dismissImport() } }),
                      allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): importExportVM.importFile(at: url)
            case .failure(let error): importExportVM.importFailed(error)
            }
        }
        .confirmationDialog("Name conflict",
                            isPresented: Binding(get: { importExportVM.conflict != nil },
                                                 set: { if !$0 { importExportVM.dismissConflict() } }),
                            presenting: importExportVM.conflict) { candidate in
            Button("Replace") { importExportVM.decide(.replace) }
            Button("Keep Both") { importExportVM.decide(.keepBoth) }
            Button("Keep Existing", role: .cancel) { importExportVM.decide(.keepExisting) }
        } message: { candidate in
            Text("“\(candidate.checklist.name)” already exists.")
        }
        .alert("Couldn't export",
               isPresented: Binding(get: { importExportVM.exportErrorMessage != nil },
                                    set: { if !$0 { importExportVM.clearExportError() } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(importExportVM.exportErrorMessage ?? "") }
        // Two-step removal gate, mirroring the detail screen: the per-row
        // minus only raises this dialog, and its destructive button performs
        // the removal.
        .confirmationDialog(
            "Remove Checklist",
            isPresented: Binding(get: { listVM.checklistPendingRemoval != nil },
                                 set: { if !$0 { listVM.checklistPendingRemoval = nil } }),
            presenting: listVM.checklistPendingRemoval
        ) { id in
            Button("Remove", role: .destructive) {
                // Clear the pending id explicitly rather than relying on the
                // dialog's dismissal to fire the `isPresented` setter.
                listVM.checklistPendingRemoval = nil
                withAnimation { listVM.removeChecklist(id: id) }
            }
            .accessibilityIdentifier("confirmRemoveChecklistButton")
            Button("Cancel", role: .cancel) { listVM.checklistPendingRemoval = nil }
                .accessibilityIdentifier("cancelRemoveChecklistButton")
        } message: { _ in
            Text("This removes the checklist and all its items.")
        }
        // Leave edit mode when the last checklist goes: the empty state has no
        // toggle, so a later create must not open into a stale edit state.
        .onChange(of: listVM.checklists.isEmpty) { _, isEmpty in
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
                settingsVM.begin(from: SettingsSnapshot(
                    backgroundEnabled: backgroundEnabled,
                    backgroundFadePercent: backgroundFadePercent,
                    backgroundPinned: backgroundPinned,
                    textSize: textSize,
                    allowsLandscape: allowsLandscape))
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
                settingsVM.begin(from: SettingsSnapshot(
                    backgroundEnabled: backgroundEnabled,
                    backgroundFadePercent: backgroundFadePercent,
                    backgroundPinned: backgroundPinned,
                    textSize: textSize,
                    allowsLandscape: allowsLandscape))
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
                        ForEach(listVM.checklists) { checklist in
                            checklistRow(for: checklist)
                            if checklist.id != listVM.checklists.last?.id {
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
                    listVM.checklistPendingRemoval = checklist.id
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
            Button { withAnimation { listVM.moveChecklist(id: checklist.id, up: true) } } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(listVM.checklists.first?.id == checklist.id)
            .accessibilityLabel("Move up")
            .accessibilityIdentifier("moveChecklistUp-\(checklist.id.uuidString)")

            Button { withAnimation { listVM.moveChecklist(id: checklist.id, up: false) } } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(listVM.checklists.last?.id == checklist.id)
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
            Task { await runVM.createReminders(for: id) }
        } label: {
            if runVM.creating.contains(id) {
                ProgressView()
                    .controlSize(.small)
            } else if runVM.created.contains(id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "play.circle.fill")
            }
        }
        .buttonStyle(.borderless)
        .disabled(runVM.creating.contains(id))
        .accessibilityLabel("Create reminders from checklist")
        .accessibilityIdentifier("createRemindersButton")
    }

    private func createChecklist() {
        // Creation runs through the list view model, which owns the mutation.
        path.append(listVM.createChecklist())
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
            backgroundImage: backgroundVM.image,
            onExport: { requestDataAction(.export) },
            onImport: { requestDataAction(.importChecklists) })
            .onChange(of: bag.backgroundEnabled) { _, _ in applySettings(settingsVM.writeBack(bag)) }
            .onChange(of: bag.backgroundFadePercent) { _, _ in applySettings(settingsVM.writeBack(bag)) }
            .onChange(of: bag.backgroundPinned) { _, _ in applySettings(settingsVM.writeBack(bag)) }
            .onChange(of: bag.textSize) { _, _ in applySettings(settingsVM.writeBack(bag)) }
            .onChange(of: bag.allowsLandscape) { _, _ in applySettings(settingsVM.writeBack(bag)) }
    }

    /// Applies the VM's staged writeback to the `@AppStorage`-backed properties.
    func applySettings(_ writeback: SettingsWriteback) {
        backgroundEnabled = writeback.backgroundEnabled
        backgroundFadePercent = writeback.backgroundFadePercent
        backgroundPinned = writeback.backgroundPinned
        textSize = writeback.textSize
        allowsLandscape = writeback.allowsLandscape
    }

    /// Stages an import/export chosen in the Settings menu and closes the sheet,
    /// so the root-owned file panel presents unobstructed. The VM owns the queue
    /// and fakes `isShowingSettings = false`.
    private func requestDataAction(_ action: SettingsDataAction) {
        settingsVM.stage(action)
    }

    /// Opens the panel the Settings menu staged, once the settings sheet has
    /// dismissed.
    private func perform(_ action: SettingsDataAction) {
        switch action {
        case .export: importExportVM.beginExport()
        case .importChecklists: importExportVM.beginImport()
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
        .environment(ChecklistListViewModel(store: store))
        .environment(ChecklistRunViewModel(store: store))
        .environment(ChecklistImportExportViewModel(store: store))
        .environment(BackgroundViewModel())
        .environment(AppearanceViewModel())
        // Construction only: the preview never triggers read/write/synchronize.
        .environment(ChecklistSyncService(sync: UbiquitousChecklistSync(), store: store))
}
