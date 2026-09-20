import CheckStitchCore
import SwiftUI

struct WatchChecklistDetailView: View {
    let checklist: Checklist
    @Environment(WatchChecklistViewModel.self) private var viewModel
    @State private var runID: UUID?

    /// Height of the pinned footer. `.safeAreaInset` places the footer over the
    /// bottom of the screen but does not stop a `List` from scrolling under it
    /// on watchOS, so the scroll content needs an explicit bottom margin
    /// matching the footer's measured height (see `FooterHeightPreferenceKey`).
    @State private var footerHeight: CGFloat = 0

    /// The live copy from the store once a `notFound` refresh lands; the value
    /// this screen was pushed with is only the seed. Without this the screen
    /// would keep showing stale items after the watch self-corrects the list.
    private var current: Checklist {
        viewModel.current(checklist)
    }

    /// Blank rows are never turned into reminders, so the watch hides them too.
    private var visibleItems: [ChecklistItem] {
        viewModel.visibleItems(of: checklist)
    }

    private var phase: RunPhase {
        viewModel.phase(runID: runID)
    }

    /// A resource, not an eager `String(localized:)`: `Button`'s `String`
    /// overload resolves against the process locale, so it would never follow
    /// the language the phone pushed. `Text(resource)` re-resolves it against
    /// the injected environment locale on every pass.
    private var buttonTitle: LocalizedStringResource {
        switch phase {
        case .sending: LocalizedStringResource("Sending…", table: "Localizable", bundle: .main)
        case .created, .partiallyCreated: LocalizedStringResource("Created", table: "Localizable", bundle: .main)
        case .idle, .failed: LocalizedStringResource("Create reminders", table: "Localizable", bundle: .main)
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
        // Keep the item rows cutting off cleanly above the pinned footer
        // instead of scrolling under the "Create reminders" button.
        .contentMargins(.bottom, footerHeight, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button {
                    runID = viewModel.run(checklist)
                } label: {
                    Text(buttonTitle)
                }
                .tint(.blue)
                .disabled(buttonDisabled)
                if let detail = phase.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: FooterHeightPreferenceKey.self, value: proxy.size.height)
                }
            )
        }
        .onPreferenceChange(FooterHeightPreferenceKey.self) { footerHeight = $0 }
    }
}

/// Carries the pinned footer's height up to the list so the scroll content can
/// be margined to stop above it.
private struct FooterHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
