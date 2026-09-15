import CheckStitchCore
import SwiftUI

/// Multi-select sheet. Export hands the selection back to the root view, which
/// owns `.fileExporter` (a sheet-nested exporter never presents its panel on macOS).
struct ExportChecklistsView: View {
    @Environment(ChecklistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<UUID>
    let onExport: () -> Void

    /// Pure, so the disable state is unit-testable without a live hierarchy.
    var canExport: Bool { !selection.isEmpty }

    /// Pure toggle helper, exposed for tests.
    static func toggled(_ selection: Set<UUID>, id: UUID) -> Set<UUID> {
        var next = selection
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        return next
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Checklists").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            Text("Select the checklists to include.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            List(store.checklists) { checklist in
                Button {
                    selection = Self.toggled(selection, id: checklist.id)
                } label: {
                    HStack {
                        Image(systemName: selection.contains(checklist.id)
                              ? "checkmark.circle.fill" : "circle")
                        Text(checklist.name)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("exportSelectionRow")
            }
            Button("Export") { onExport() }
                .disabled(!canExport)
                .accessibilityIdentifier("confirmExportButton")
                .padding()
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}