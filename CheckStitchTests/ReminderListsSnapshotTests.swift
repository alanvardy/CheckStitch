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
}
