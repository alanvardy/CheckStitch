import CheckStitchCore
import SwiftUI

/// Multi-select sheet. Export hands the selection back to the root view, which
/// owns `.fileExporter` (a sheet-nested exporter never presents its panel on macOS).
struct ExportChecklistsView: View {
    @Environment(ChecklistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<UUID>
    let onExport: () -> Void

    var canExport: Bool { !selection.isEmpty }

    /// Kept as a forwarding shim so `ExportChecklistsViewTests` is unchanged.
    static func toggled(_ selection: Set<UUID>, id: UUID) -> Set<UUID> {
        ChecklistSelectionView.toggled(selection, id: id)
    }

    var body: some View {
        ChecklistSelectionView(
            title: "Export Checklists",
            rows: store.checklists.map {
                ChecklistSelectionRow(id: $0.id, name: $0.name, detail: nil)
            },
            selection: $selection,
            confirmTitle: "Export",
            onConfirm: onExport,
            onCancel: { dismiss() },
            rowAccessibilityID: "exportSelectionRow",
            confirmAccessibilityID: "confirmExportButton")
    }
}
