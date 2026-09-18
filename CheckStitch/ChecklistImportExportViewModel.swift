import CheckStitchCore
import Foundation
import Observation

/// Drives the root screen's import/export flow: the export multi-select, the
/// export document, the file read, and the FIFO conflict queue. The view owns
/// the panels/alerts and presents them from this state.
@MainActor
@Observable
final class ChecklistImportExportViewModel {
    init(store: ChecklistStore) {
        self.store = store
    }

    var exportSelection: Set<UUID> = []
    var exportDocument: ChecklistExportDocument?
    var conflict: ChecklistImportCandidate?
    var isShowingExport = false
    private(set) var isExporting = false
    private(set) var isImporting = false
    private(set) var importErrorMessage: String?
    private(set) var exportErrorMessage: String?
    private var importSession: ChecklistImportSession?

    /// Opens the export multi-select with nothing selected.
    func beginExport() {
        exportSelection = []
        isShowingExport = true
    }

    /// Opens the file importer.
    func beginImport() {
        isImporting = true
    }

    func dismissExportSelection() { isShowingExport = false }
    func dismissExport() { isExporting = false }
    func dismissImport() { isImporting = false }
    func clearImportError() { importErrorMessage = nil }
    func clearExportError() { exportErrorMessage = nil }

    /// Builds the document for the current selection and hands it to the
    /// exporter. An empty selection exports nothing.
    func exportSelected() {
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

    func exportFailed(_ error: Error) {
        exportErrorMessage = error.localizedDescription
    }

    func importFailed(_ error: Error) {
        importErrorMessage = error.localizedDescription
    }

    /// Reads the picked file under a security-scoped access/stop pair, then
    /// prepares an import session. A read failure reports the system message;
    /// a format failure reports the CheckStitch-specific one.
    func importFile(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
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

    /// Applies one decision to the current conflict and advances the queue.
    func decide(_ decision: ImportDecision) {
        guard let current = conflict else { return }
        conflict = nil
        importSession?.decide(decision, for: current.id)
        advanceConflict()
    }

    /// Handles SwiftUI's own dismissal of the conflict dialog (setter fires
    /// `false`): keep the existing checklist and advance, exactly once.
    func dismissConflict() {
        guard let current = conflict else { return }
        conflict = nil
        importSession?.decide(.keepExisting, for: current.id)
        advanceConflict()
    }

    /// Re-presents after the current dismissal completes, so the next conflict
    /// in the FIFO queue is shown until the queue is empty.
    private func advanceConflict() {
        Task { @MainActor in
            conflict = importSession?.pending.first
        }
    }

    private let store: ChecklistStore
}
