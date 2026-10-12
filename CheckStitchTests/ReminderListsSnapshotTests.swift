import CheckStitchCore
import Testing

/// The picker offers the system default list once — through its "Default" row —
/// even though EventKit also returns that list among `options`.
struct ReminderListsSnapshotTests {
    private func snapshot(
        options: [ReminderListOption] = [
            ReminderListOption(id: "list-inbox", title: "Inbox"),
            ReminderListOption(id: "list-groceries", title: "Groceries"),
        ],
        defaultIdentifier: String? = "list-inbox"
    ) -> ReminderListsSnapshot {
        ReminderListsSnapshot(options: options, defaultIdentifier: defaultIdentifier)
    }

    @Test
    func defaultListIsNotOfferedTwice() {
        let options = snapshot().selectableOptions

        #expect(options.map(\.title) == ["Groceries"])
        #expect(!options.contains { $0.title == "Inbox" })
    }

    @Test
    func everyOtherListIsOfferedInOrder() {
        let options = snapshot(
            options: [
                ReminderListOption(id: "list-inbox", title: "Inbox"),
                ReminderListOption(id: "list-groceries", title: "Groceries"),
                ReminderListOption(id: "list-work", title: "Work"),
            ])
            .selectableOptions

        #expect(options.map(\.id) == ["list-groceries", "list-work"])
    }

    /// Sad path: with no default list, nothing is dropped and the picker still
    /// lists every enumerated list.
    @Test
    func noDefaultListOffersEverything() {
        let options = snapshot(defaultIdentifier: nil).selectableOptions

        #expect(options.map(\.id) == ["list-inbox", "list-groceries"])
    }

    /// Sad path: a default identifier EventKit no longer enumerates must not
    /// filter an unrelated list away.
    @Test
    func unknownDefaultIdentifierOffersEverything() {
        let options = snapshot(defaultIdentifier: "list-gone").selectableOptions

        #expect(options.map(\.id) == ["list-inbox", "list-groceries"])
    }

    @Test
    func pickerShowsTheDefaultRowForTheDefaultList() {
        #expect(snapshot().pickerSelection(for: "list-inbox") == nil)
        #expect(snapshot().pickerSelection(for: nil) == nil)
    }

    @Test
    func pickerPassesOtherListsThrough() {
        #expect(snapshot().pickerSelection(for: "list-groceries") == "list-groceries")
    }

    /// The run path is untouched: the default list still resolves by identifier
    /// and by `nil`, even though the picker no longer offers it by name.
    @Test
    func resolveStillFindsTheDefaultList() {
        #expect(snapshot().resolve("list-inbox")?.title == "Inbox")
        #expect(snapshot().resolve(nil)?.title == "Inbox")
    }

    /// Hardening: an all-empty snapshot (no lists, no default) offers nothing to
    /// pick and resolves nothing — the run reports `.destinationMissing` and the
    /// VM shows the missing-destination text instead of an empty chooser.
    @Test
    func allEmptySnapshotOffersAndResolvesNothing() {
        let empty = ReminderListsSnapshot(options: [], defaultIdentifier: nil)

        #expect(empty.selectableOptions.isEmpty)
        #expect(empty.resolve("list-a") == nil)
        #expect(empty.resolve(nil) == nil)
    }

    /// The staleness detector's inputs: a stored `.list` id that is neither
    /// enumerated nor the default passes `pickerSelection` (so it is candidate
    /// stale) while staying out of `selectableOptions` — the detail view composes
    /// those two facts to flag a deleted list, and only such a `.list` flags.
    @Test
    func absentListPassesPickerSelectionWhileStayingUnselectable() {
        #expect(snapshot().pickerSelection(for: "list-gone") == "list-gone")
        #expect(!snapshot().selectableOptions.contains { $0.id == "list-gone" })
    }
}
