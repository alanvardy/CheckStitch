@testable import CheckStitchCore
import Foundation
import Testing

/// Counts reload requests without touching WidgetKit.
@MainActor
private final class ReloadSpy {
    private(set) var count = 0
    func record() { count += 1 }
}

@MainActor
struct WidgetRunStateStoreTests {
    private func makeStore(spy: ReloadSpy? = nil) -> WidgetRunStateStore {
        WidgetRunStateStore(
            defaults: makeIsolatedDefaults(),
            minimumSpinner: 0,
            onChange: { spy?.record() })
    }

    private let now = Date()

    @Test
    func unknownChecklistShowsPlay() {
        let store = makeStore()
        #expect(store.indicator(for: UUID(), at: now) == .play)
    }

    @Test
    func runInFlightShowsSpinner() {
        let store = makeStore()
        let id = UUID()
        store.beginRun(id: id, at: now)
        #expect(store.indicator(for: id, at: now) == .spinner)
    }

    @Test
    func successfulRunShowsCheckmarkThenRevertsToPlay() {
        let store = makeStore()
        let id = UUID()
        store.beginRun(id: id, at: now)
        store.finishRun(id: id, didCreate: true, at: now)

        #expect(store.indicator(for: id, at: now) == .checkmark)
        // Still inside the check window, at its edge.
        let justInside = now.addingTimeInterval(WidgetRunStateStore.checkmarkDuration - 0.1)
        #expect(store.indicator(for: id, at: justInside) == .checkmark)
        // Past the window the button is a play icon again.
        let after = now.addingTimeInterval(WidgetRunStateStore.checkmarkDuration)
        #expect(store.indicator(for: id, at: after) == .play)
    }

    @Test(arguments: [false])
    func unsuccessfulRunNeverShowsCheckmark(_ didCreate: Bool) {
        let store = makeStore()
        let id = UUID()
        store.beginRun(id: id, at: now)
        store.finishRun(id: id, didCreate: didCreate, at: now)

        #expect(store.indicator(for: id, at: now) == .play)
    }

    /// A killed intent leaves a `.running` record behind; the spinner must not
    /// stick forever.
    @Test
    func abandonedRunRevertsToPlayAfterTheTimeout() {
        let store = makeStore()
        let id = UUID()
        store.beginRun(id: id, at: now)

        let before = now.addingTimeInterval(WidgetRunStateStore.abandonedRunTimeout - 1)
        #expect(store.indicator(for: id, at: before) == .spinner)
        let after = now.addingTimeInterval(WidgetRunStateStore.abandonedRunTimeout)
        #expect(store.indicator(for: id, at: after) == .play)
    }

    /// Validated-read convention: a payload from a newer/broken build reads as
    /// "no run" rather than throwing or sticking the spinner.
    @Test
    func corruptPayloadReadsAsNoRun() {
        let defaults = makeIsolatedDefaults()
        defaults.set(Data("not json".utf8), forKey: WidgetRunStateStore.defaultsKey)
        let store = WidgetRunStateStore(defaults: defaults, minimumSpinner: 0, onChange: {})

        #expect(store.records.isEmpty)
        #expect(store.indicator(for: UUID(), at: now) == .play)
    }

    @Test
    func phaseChangesAskForAReload() {
        let spy = ReloadSpy()
        let store = makeStore(spy: spy)
        let id = UUID()

        store.beginRun(id: id, at: now)
        #expect(spy.count == 1)
        store.finishRun(id: id, didCreate: true, at: now)
        #expect(spy.count == 2)
    }

    @Test
    func recordsSurviveANewStoreInstance() {
        let defaults = makeIsolatedDefaults()
        let id = UUID()
        let writer = WidgetRunStateStore(defaults: defaults, minimumSpinner: 0, onChange: {})
        writer.beginRun(id: id, at: now)
        writer.finishRun(id: id, didCreate: true, at: now)

        let reader = WidgetRunStateStore(defaults: defaults, minimumSpinner: 0, onChange: {})
        #expect(reader.indicator(for: id, at: now) == .checkmark)
    }

    @Test
    func aSecondRunReplacesTheFirstForTheSameChecklist() {
        let store = makeStore()
        let id = UUID()
        store.beginRun(id: id, at: now)
        store.finishRun(id: id, didCreate: true, at: now)
        store.beginRun(id: id, at: now.addingTimeInterval(10))

        #expect(store.records.count == 1)
        #expect(store.indicator(for: id, at: now.addingTimeInterval(10)) == .spinner)
    }

    /// A finish without a matching begin (the process died between them) still
    /// records the outcome rather than silently doing nothing.
    @Test
    func finishWithoutBeginStillRecords() {
        let store = makeStore()
        let id = UUID()
        store.finishRun(id: id, didCreate: true, at: now)

        #expect(store.indicator(for: id, at: now) == .checkmark)
    }

    @Test
    func indicatorsMapEveryRecordedChecklist() {
        let store = makeStore()
        let spinning = UUID()
        let done = UUID()
        store.beginRun(id: spinning, at: now)
        store.beginRun(id: done, at: now)
        store.finishRun(id: done, didCreate: true, at: now)

        let indicators = store.indicators(at: now)
        #expect(indicators[spinning] == .spinner)
        #expect(indicators[done] == .checkmark)
        #expect(store.indicators(at: now.addingTimeInterval(600))[spinning] == .play)
    }

    @Test
    func checkmarkEndsAtReportsTheRevertMoment() {
        let store = makeStore()
        let id = UUID()
        store.beginRun(id: id, at: now)
        store.finishRun(id: id, didCreate: true, at: now)

        #expect(store.checkmarkEndsAt(at: now)
            == now.addingTimeInterval(WidgetRunStateStore.checkmarkDuration))
        // No check on screen → no transition to schedule.
        #expect(store.checkmarkEndsAt(at: now.addingTimeInterval(60)) == nil)
    }

    /// The array is capped so a long-lived install cannot grow it without
    /// bound; the newest records survive.
    @Test
    func recordsAreBounded() {
        let store = makeStore()
        for _ in 0..<40 {
            let id = UUID()
            store.beginRun(id: id, at: now)
            store.finishRun(id: id, didCreate: true, at: now)
        }
        #expect(store.records.count == 32)
    }
}