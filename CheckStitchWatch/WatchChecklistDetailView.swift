import CheckStitchCore
import SwiftUI

struct WatchChecklistDetailView: View {
    let checklist: Checklist
    @Environment(WatchChecklistStore.self) private var store
    @State private var runID: UUID?

    /// Blank rows are never turned into reminders, so the watch hides them too.
    private var visibleItems: [ChecklistItem] {
        checklist.items.filter { !$0.isBlank }
    }

    private var phase: RunPhase {
        runID.map { store.runPhase(runID: $0) } ?? .idle
    }

    private var buttonTitle: String {
        switch phase {
        case .sending: String(localized: "Sending…", table: "Localizable", bundle: .main)
        case .created: String(localized: "Created", table: "Localizable", bundle: .main)
        case .idle, .failed: String(localized: "Create reminders", table: "Localizable", bundle: .main)
        }
    }

    private var buttonDisabled: Bool {
        switch phase {
        case .sending, .created: true
        case .idle, .failed: visibleItems.isEmpty
        }
    }

    var body: some View {
        List(visibleItems) { item in
            VStack(alignment: .leading) {
                Text(item.title)
                if item.hasDescription {
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(checklist.name)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button(buttonTitle) {
                    runID = store.run(checklist)
                }
                .disabled(buttonDisabled)
                if case .failed(let reason) = phase {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}