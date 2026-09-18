@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct AppLanguageSyncTests {
    @Test
    func languageRoundTripsThroughUserInfo() {
        let message = ChecklistSyncMessage.language("de")
        #expect(ChecklistSyncMessage(userInfo: message.userInfo) == message)
    }

    @Test
    func unknownLanguageStringIsRejectedNotCrashed() {
        #expect(ChecklistSyncMessage(userInfo: [ChecklistSyncKey.language: "xx"]) == nil)
        #expect(ChecklistSyncMessage(userInfo: [ChecklistSyncKey.language: 42]) == nil)
    }

    @Test
    func receivedLanguageAppliesAndPersists() {
        let defaults = makeIsolatedDefaults()
        let transport = FakeChecklistSyncTransport()
        let locale = AppLocaleState(language: .english, defaults: defaults)
        let store = WatchChecklistStore(transport: transport, locale: locale)
        store.start()

        transport.deliver(.language("ja"))

        #expect(locale.language == .japanese)
        #expect(AppLanguage.load(from: defaults) == .japanese)
    }

    @Test
    func persistedLanguageAppliesBeforeAnyMessage() {
        let defaults = makeIsolatedDefaults()
        AppLanguagePreference(defaults: defaults).setRawValue("ja")
        #expect(AppLanguagePreference(defaults: defaults).load() == .japanese)
    }

    @Test
    func garbageLanguageLeavesTheCurrentChoiceAlone() {
        let transport = FakeChecklistSyncTransport()
        let locale = AppLocaleState(language: .japanese, defaults: makeIsolatedDefaults())
        let store = WatchChecklistStore(transport: transport, locale: locale)
        store.start()

        transport.deliver(.language("xx"))

        #expect(locale.language == .japanese)
    }

    @Test
    func languageMessageDoesNotDisturbTheChecklists() throws {
        let transport = FakeChecklistSyncTransport()
        let locale = AppLocaleState(language: .english, defaults: makeIsolatedDefaults())
        let store = WatchChecklistStore(transport: transport, locale: locale)
        store.start()
        let expected = [Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")])]
        transport.deliver(.context(try ChecklistCodec.encode(ChecklistEnvelope(
            version: ChecklistCodec.currentVersion, deviceID: "", checklists: expected))))

        transport.deliver(.language("ja"))

        #expect(store.checklists == expected)
        #expect(locale.language == .japanese)
    }

    @Test
    func repeatedLanguageMessagesAreIdempotent() {
        let defaults = makeIsolatedDefaults()
        let transport = FakeChecklistSyncTransport()
        let locale = AppLocaleState(language: .english, defaults: defaults)
        let store = WatchChecklistStore(transport: transport, locale: locale)
        store.start()

        transport.deliver(.language("de"))
        transport.deliver(.language("de"))

        #expect(locale.language == .german)
        #expect(AppLanguage.load(from: defaults) == .german)
    }

    /// Each re-push request carries the language again: the cold-start push is
    /// one send, then every `requestChecklists` adds one more (the fake's
    /// `activate()` never fires `onActivated`, so no second cold-start push).
    @Test
    func repeatedRequestChecklistsRepushesTheSameLanguage() {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let coordinator = ChecklistSyncCoordinator(
            transport: transport, snapshot: { [] },
            createReminders: { await runner.run($0) }, language: { .german })
        coordinator.start()
        transport.deliver(.requestChecklists)
        transport.deliver(.requestChecklists)
        #expect(transport.sentMessages.filter { $0 == .language("de") }.count == 3)
    }
}