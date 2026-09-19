import Foundation
import SwiftUI

/// One selectable row: a checklist identity, its display name, optional caption.
/// `detail` is a localizable key (`LocalizedStringKey`), so the conflict caption
/// resolves through the app's string catalog.
struct ChecklistSelectionRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let detail: LocalizedStringKey?
}

/// Shared checkmark multi-select sheet for export and import. Pure selection
/// helpers (`toggled`, `canConfirm`) are exposed for tests. `title` and
/// `confirmTitle` are keys, not verbatim strings, so both sheets localize.
struct ChecklistSelectionView: View {
    let title: LocalizedStringKey
    let rows: [ChecklistSelectionRow]
    @Binding var selection: Set<UUID>
    let confirmTitle: LocalizedStringKey
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let rowAccessibilityID: String
    let confirmAccessibilityID: String

    /// Pure, so the disable state is unit-testable without a live hierarchy.
    var canConfirm: Bool { !selection.isEmpty }

    /// Pure toggle helper, exposed for tests.
    static func toggled(_ selection: Set<UUID>, id: UUID) -> Set<UUID> {
        var next = selection
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        return next
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
            }
            .padding()
            Text("Select the checklists to include.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            List(rows) { row in
                Button {
                    selection = Self.toggled(selection, id: row.id)
                } label: {
                    HStack {
                        Image(systemName: selection.contains(row.id)
                              ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                            if let detail = row.detail {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(rowAccessibilityID)
            }
            Button(confirmTitle) { onConfirm() }
                .disabled(!canConfirm)
                .accessibilityIdentifier(confirmAccessibilityID)
                .padding()
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}
