import CheckStitchCore
import SwiftUI

/// Multi-select sheet. Export hands the selection back to the root view, which
/// owns `.fileExporter` (a sheet-nested exporter never presents its panel on macOS).
struct ExportChecklistsView: View {
    @Environment(ChecklistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<UUID>
    let onExport: () -> Void
    let onShare: () -> Void

    var canExport: Bool { !selection.isEmpty }

    /// Kept as a forwarding shim so `ExportChecklistsViewTests` is unchanged.
    static func toggled(_ selection: Set<UUID>, id: UUID) -> Set<UUID> {
        ChecklistSelectionView.toggled(selection, id: id)
    }

    /// Pure: the full selection when every active checklist is chosen.
    /// Exposed so the select-all logic is unit-testable without a live hierarchy.
    static func selectAll(_ checklists: [Checklist]) -> Set<UUID> {
        Set(checklists.map { $0.id })
    }

    var body: some View {
        ChecklistSelectionView(
            title: "Export Checklists",
            rows: store.activeChecklists.map {
                ChecklistSelectionRow(id: $0.id, name: $0.name, detail: nil)
            },
            selection: $selection,
            confirmTitle: "Export",
            onConfirm: onExport,
            onCancel: { dismiss() },
            rowAccessibilityID: "exportSelectionRow",
            confirmAccessibilityID: "confirmExportButton",
            secondaryTitle: "Share…",
            secondaryAccessibilityID: "shareChecklistsButton",
            onSecondary: onShare,
            selectAllTitle: "Select All",
            selectAllAccessibilityID: "selectAllChecklistsButton",
            onSelectAll: { selection = Self.selectAll(store.activeChecklists) })
    }
}