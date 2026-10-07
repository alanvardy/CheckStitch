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
    @Environment(\.colorScheme) private var colorScheme
    let title: LocalizedStringKey
    let rows: [ChecklistSelectionRow]
    @Binding var selection: Set<UUID>
    let confirmTitle: LocalizedStringKey
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let rowAccessibilityID: String
    let confirmAccessibilityID: String
    /// Optional action drawn after the confirm button — the export sheet's
    /// "Share…". The import sheet has only a confirm and leaves these nil.
    var secondaryTitle: LocalizedStringKey?
    var secondaryAccessibilityID: String?
    var onSecondary: (() -> Void)?
    /// Optional leading "Select All"/"Deselect All" toggle (ahead of Export and
    /// Share) — the export sheet's convenience so every active checklist is chosen
    /// at once, then cleared again. The import sheet has only a confirm and leaves
    /// these nil.
    var selectAllTitle: LocalizedStringKey?
    var deselectAllTitle: LocalizedStringKey?
    var selectAllAccessibilityID: String?
    var onSelectAll: (() -> Void)?
    var onDeselectAll: (() -> Void)?

    /// Pure, so the disable state is unit-testable without a live hierarchy.
    var canConfirm: Bool { !selection.isEmpty }

    /// Pure: every row is already selected, which flips the toggle's label to
    /// "Deselect All" and its action to clearing the selection.
    var allRowsSelected: Bool { !rows.isEmpty && selection.count == rows.count }

    /// Pure: the toggle is enabled whenever there is at least one row to act on —
    /// it offers Select All when not every row is chosen, and Deselect All once
    /// they all are.
    var canSelectAll: Bool { !rows.isEmpty }

    /// Pure toggle helper, exposed for tests.
    static func toggled(_ selection: Set<UUID>, id: UUID) -> Set<UUID> {
        var next = selection
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        return next
    }

    /// An action button drawn as an outlined plate — the app's chrome treatment
    /// (`CardPlate.cornerRadius` over `CardPlate.iconPlateFill`, plus a 2pt tint
    /// stroke) — so a two-action row reads as two separate targets instead of
    /// two bare words. The plate sits inside the button's label, so the whole
    /// outline is tappable, not just the text.
    private func actionButton(_ title: LocalizedStringKey,
                             identifier: String,
                             action: @escaping () -> Void,
                             enabled: Bool = true) -> some View {
        Button(action: action) {
            Text(title)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                        .fill(CardPlate.iconPlateFill(for: colorScheme))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                        .stroke(.tint, lineWidth: 2)
                }
                .contentShape(RoundedRectangle(cornerRadius: CardPlate.cornerRadius))
        }
        .disabled(!enabled)
        .checkStitchButton()
        .accessibilityIdentifier(identifier)
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
                    // A plain button hit-tests only its drawn subviews, so the
                    // `Spacer()` region would swallow taps on the row's right
                    // side. The explicit rect makes the whole row tappable.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(rowAccessibilityID)
            }
            HStack(spacing: 16) {
                #if os(iOS)
                // The share presenter is iOS-only, so macOS never draws the
                // Select All or second actions (the export sheet there is unchanged).
                // The leading toggle reads "Select All" until every row is chosen,
                // then flips to "Deselect All".
                if let selectAllTitle, let deselectAllTitle, let onSelectAll, let onDeselectAll {
                    actionButton(allRowsSelected ? deselectAllTitle : selectAllTitle,
                                 identifier: selectAllAccessibilityID ?? "",
                                 action: allRowsSelected ? onDeselectAll : onSelectAll,
                                 enabled: canSelectAll)
                }
                #endif
                actionButton(confirmTitle,
                             identifier: confirmAccessibilityID,
                             action: onConfirm,
                             enabled: canConfirm)
                #if os(iOS)
                if let secondaryTitle, let onSecondary {
                    actionButton(secondaryTitle,
                                 identifier: secondaryAccessibilityID ?? "",
                                 action: onSecondary,
                                 enabled: canConfirm)
                }
                #endif
            }
            .padding()
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}
