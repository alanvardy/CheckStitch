

    // MARK: - Create uniqueness

    func testRepeatedDefaultCreatesIncrementTheName() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let first = store.create()
        let second = store.create()
        let third = store.create()

        // A second "New checklist" is disambiguated instead of refused.
        XCTAssertEqual(first.name, "New checklist")
        XCTAssertEqual(second.name, "New checklist 2")
        XCTAssertEqual(third.name, "New checklist 3")
        XCTAssertEqual(store.checklists.count, 3)

        // The disambiguated names survive a reload unchanged.
        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.map(\.name), ["New checklist", "New checklist 2", "New checklist 3"])
    }

    func testCreateReusesAGapLeftByADeletedChecklist() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create()
        let second = store.create()
        store.delete(id: second.id)

        // With "New checklist 2" free again, the next create takes the lowest
        // free suffix rather than skipping to 3.
        let recreated = store.create()
        XCTAssertEqual(recreated.name, "New checklist 2")
        XCTAssertEqual(store.checklists.map(\.name), ["New checklist", "New checklist 2"])
    }

    func testCreateWithTypedNameSucceeds() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create(name: "Groceries")
        XCTAssertEqual(store.checklists.count, 1)
        XCTAssertEqual(store.checklist(id: created.id)?.name, "Groceries")
    }

    func testCreateWithDuplicateTypedNameIncrements() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create(name: "Groceries")

        // Case-insensitive collision: the requested casing is kept and a
        // numeric suffix disambiguates.
        let second = store.create(name: "groceries")
        XCTAssertEqual(second.name, "groceries 2")

        // A whitespace-padded duplicate is trimmed before the suffix is added,
        // and steps past the suffix already in use.
        let third = store.create(name: "  GROCERIES  ")
        XCTAssertEqual(third.name, "GROCERIES 3")

        XCTAssertEqual(store.checklists.map(\.name), ["Groceries", "groceries 2", "GROCERIES 3"])
    }

    // MARK: - Rename uniqueness

    func testRenameToUniqueNameSucceeds() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create(name: "Groceries")
        XCTAssertEqual(store.rename(id: created.id, to: "Errands"), .renamed)
        XCTAssertEqual(store.checklist(id: created.id)?.name, "Errands")
    }

    func testRenameKeepingOwnNameIsAllowed() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create(name: "Groceries")
        // The checklist being renamed is excluded, so keeping its own name —
        // including a case/whitespace variant of it — is never a conflict.
        XCTAssertEqual(store.rename(id: created.id, to: "Groceries"), .renamed)
        XCTAssertEqual(store.rename(id: created.id, to: "  groceries  "), .renamed)
        XCTAssertEqual(store.checklist(id: created.id)?.name, "  groceries  ")
    }

    func testRenameToAnotherChecklistsNameIsRejected() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create(name: "Groceries")
        let chores = store.create(name: "Chores")

        // A case variant and a trimmed variant of the other name are refused
        // and change nothing, so a reload still sees the pre-rename state.
        XCTAssertEqual(store.rename(id: chores.id, to: "GROCERIES"), .nameTaken)
        XCTAssertEqual(store.checklist(id: chores.id)?.name, "Chores")

        XCTAssertEqual(store.rename(id: chores.id, to: "  groceries  "), .nameTaken)
        XCTAssertEqual(store.checklist(id: chores.id)?.name, "Chores")

        XCTAssertEqual(store.checklists.map(\.name), ["Groceries", "Chores"])
        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.map(\.name), ["Groceries", "Chores"])
    }

    func testRenameUnknownIDReportsNotFound() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        XCTAssertEqual(store.rename(id: UUID(), to: "Groceries"), .notFound)
    }

    func testLegacyPayloadIsMigratedAndSavable() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        // A true v1 payload: v1 carried no sync state, so migration stamps it.
        let legacy = Data(#"{"version":1,"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(UUID().uuidString)","title":"Milk"}]}]}"#.utf8)
        suite.defaults.set(legacy, forKey: key)

        let store = makeStore(defaults: suite.defaults)
        XCTAssertEqual(store.checklists.count, 1)
        XCTAssertEqual(store.checklists.first?.revision, 1)
        XCTAssertEqual(store.checklists.first?.items.first?.revision, 1)

        // The migrated payload is savable, not stalled in memory.
        store.create()

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.count, 2)
        XCTAssertEqual(reloaded.checklists.first?.name, "Groceries")
    }

    func testDeviceIDIsStableAcrossInstances() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let first = makeStore(defaults: suite.defaults)
        let second = makeStore(defaults: suite.defaults)
        XCTAssertEqual(first.deviceID, second.deviceID)
        XCTAssertFalse(first.deviceID.isEmpty)
    }

    func testNewPayloadIsVersionTwo() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create()

        let data = try? XCTUnwrap(suite.defaults.data(forKey: key))
        guard case .loaded(let stored) = ChecklistCodec.classify(data ?? Data()) else {
            XCTFail("expected the stored payload to classify as loaded")
            return
        }
        XCTAssertEqual(stored.version, 2)
    }

    func testMutationsStampRevisionAndTimestamp() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let clock = Clock()
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })

        let created = store.create()
        XCTAssertEqual(created.revision, 1)
        XCTAssertEqual(created.modifiedAt, clock.now)

        clock.now = Date(timeIntervalSince1970: 1_000)
        store.rename(id: created.id, to: "Groceries")
        XCTAssertEqual(store.checklist(id: created.id)?.revision, 2)
        XCTAssertEqual(store.checklist(id: created.id)?.modifiedAt, clock.now)

        store.addItem(to: created.id)
        let item = try? XCTUnwrap(store.checklist(id: created.id)?.items.first)
        XCTAssertEqual(item?.revision, 1)
        XCTAssertEqual(item?.modifiedAt, clock.now)

        store.updateItem(checklistID: created.id, itemID: item?.id ?? UUID(), title: "Milk")
        XCTAssertEqual(store.checklist(id: created.id)?.items.first?.revision, 2)
    }

    func testDeleteLeavesChecklistTombstone() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.delete(id: created.id)

        XCTAssertEqual(store.tombstones.count, 1)
        XCTAssertEqual(store.tombstones.first?.checklistID, created.id)
        XCTAssertNil(store.tombstones.first?.itemID)
        XCTAssertEqual(store.tombstones.first?.revision, 2)
        XCTAssertTrue(store.checklists.isEmpty)

        // The tombstone survives a reload.
        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.tombstones.count, 1)
        XCTAssertEqual(reloaded.tombstones.first?.checklistID, created.id)
        XCTAssertNil(reloaded.tombstones.first?.itemID)
    }

    func testRemoveItemsLeavesItemTombstones() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.addItem(to: created.id)
        store.addItem(to: created.id)
        let items = try? XCTUnwrap(store.checklist(id: created.id)?.items)

        store.removeItems(from: created.id, at: IndexSet(integer: 1))
        store.removeItems(from: created.id, at: IndexSet(integer: 0))

        XCTAssertEqual(store.tombstones.count, 2)
        XCTAssertEqual(store.checklist(id: created.id)?.items.count, 0)
        let tombstoneIDs = store.tombstones.map(\.itemID)
        XCTAssertTrue(tombstoneIDs.contains(items?[0].id ?? UUID()))
        XCTAssertTrue(tombstoneIDs.contains(items?[1].id ?? UUID()))

        // Reload preserves the item tombstones.
        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.tombstones.count, 2)
    }

    func testApplyMergesRemoteChecklist() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        let remote = ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: "other-device",
            checklists: [Checklist(id: UUID(), name: "Remote", modifiedAt: Date(timeIntervalSince1970: 5_000), revision: 1)])

        XCTAssertTrue(store.apply(remote: remote))
        XCTAssertEqual(store.checklists.count, 2)
        XCTAssertEqual(store.checklists.map(\.name), ["New checklist", "Remote"])

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.count, 2)
        XCTAssertEqual(reloaded.checklists.map(\.name), ["New checklist", "Remote"])
    }

    func testApplyPropagatesRemoteTombstone() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        let remote = ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: "other-device",
            checklists: [],
            tombstones: [ChecklistTombstone(
                checklistID: created.id, itemID: nil,
                deletedAt: Date(timeIntervalSince1970: 9_999), revision: 1)])

        XCTAssertTrue(store.apply(remote: remote))
        XCTAssertTrue(store.checklists.isEmpty)
        XCTAssertEqual(store.tombstones.count, 1)
        XCTAssertEqual(store.tombstones.first?.checklistID, created.id)
    }

    func testApplyIsIdempotent() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create()
        let remote = ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: "other-device",
            checklists: [Checklist(id: UUID(), name: "Remote", modifiedAt: Date(timeIntervalSince1970: 5_000), revision: 1)])

        XCTAssertTrue(store.apply(remote: remote))
        let storedAfterFirst = try? XCTUnwrap(suite.defaults.data(forKey: key))

        XCTAssertFalse(store.apply(remote: remote))
        XCTAssertEqual(suite.defaults.data(forKey: key), storedAfterFirst)
    }

    func testApplyRefusesFutureVersion() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        let stored = try? XCTUnwrap(suite.defaults.data(forKey: key))
        let future = ChecklistEnvelope(
            version: 99,
            deviceID: "other-device",
            checklists: [Checklist(id: UUID(), name: "Future", modifiedAt: Date(timeIntervalSince1970: 5_000), revision: 1)])

        XCTAssertFalse(store.apply(remote: future))
        XCTAssertEqual(store.checklists.count, 1)
        XCTAssertEqual(store.checklists.first?.id, created.id)
        XCTAssertTrue(store.tombstones.isEmpty)
        XCTAssertEqual(suite.defaults.data(forKey: key), stored)
    }

    func testEnvelopeRoundTripsThroughCodec() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create()

        let encoded = try? XCTUnwrap(ChecklistCodec.encode(store.envelope))
        XCTAssertEqual(ChecklistCodec.classify(encoded ?? Data()), .loaded(store.envelope))
    }

    func testOnChangeFiresForLocalSavesButNotWhenApplyingRemote() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        var changes = 0
        store.onChange = { changes += 1 }

        store.create()
        XCTAssertEqual(changes, 1, "a local save notifies the sync coordinator")

        let remote = ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: "other-device",
            checklists: [Checklist(id: UUID(), name: "Remote", modifiedAt: Date(timeIntervalSince1970: 5_000), revision: 1)])
        XCTAssertTrue(store.apply(remote: remote))
        XCTAssertEqual(changes, 1, "applying remote state must not schedule a push back to the cloud")
    }
}
