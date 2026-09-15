@testable import CheckStitch
import Testing

/// Pins the Settings-menu staging queue. A request must be handed over exactly
/// once: the settings-sheet dismissal callback can fire again, and a replay
/// would open a second file panel behind the first.
@MainActor
struct SettingsDataActionQueueTests {
    @Test
    func takeReturnsTheStagedActionExactlyOnce() {
        var queue = SettingsDataActionQueue()
        queue.stage(.export)

        #expect(queue.take() == .export)
        #expect(queue.take() == nil, "a staged action must not replay")
    }

    @Test
    func takeWithNothingStagedReturnsNil() {
        var queue = SettingsDataActionQueue()

        #expect(queue.take() == nil, "an untouched queue must not fabricate an action")
    }

    @Test
    func stagingAgainReplacesThePendingAction() {
        var queue = SettingsDataActionQueue()
        queue.stage(.export)
        queue.stage(.importChecklists)

        #expect(queue.take() == .importChecklists)
    }
}