@testable import CheckStitchCore
import Testing

@MainActor
struct AppEnvironmentTests {
    @Test
    func environmentIsUsableWithInjectedSeams() {
        let environment = AppEnvironment(reminderCreator: SpyReminderCreator())
        #expect(environment.reminderCreator is SpyReminderCreator)
    }
}