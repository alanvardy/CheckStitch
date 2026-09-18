import CheckStitchCore
import SwiftUI

struct WatchChecklistDetailView: View {
    let checklist: Checklist
    @Environment(WatchChecklistStore.self) private var store
    @State private var runID: UUID?

    /// The live copy from the store once a `notFound` refresh lands; the value
    /// this screen was pushed with is only the seed. Without this the screen
    /// would keep showing stale items after the watch self-corrects the list.
    private var current: Checklist {
        store.checklists.first { $0.id == checklist.id } ?? checklist
    }

    /// Blank rows are never turned into reminders, so the watch hides them too.
    private var visibleItems: [ChecklistItem] {
        current.items.filter { !$0.isBlank }
    }

    private var phase: RunPhase {
        runID.map { store.runPhase(runID: $0) } ?? .idle
    }

    private var buttonTitle: String {
        switch phase {
        case .sending: String(localized: "Sending…", table: "Localizable", bundle: .main)
        case .created, .partiallyCreated: String(localized: "Created", table: "Localizable", bundle: .main)
        case .idle, .failed: String(localized: "Create reminders", table: "Localizable", bundle: .main)
        }
    }

    private var buttonDisabled: Bool {
        switch phase {
        case .sending, .created, .partiallyCreated: true
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
        .navigationTitle(current.name)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button(buttonTitle) {
                    runID = store.run(checklist)
                }
                .disabled(buttonDisabled)
                if let detail = phase.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}