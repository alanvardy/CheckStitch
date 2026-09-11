/// Minimal dependency container: a small struct of services, not a framework.
/// `AppEnvironment` (not `Environment`) — SwiftUI exports its own public
/// `Environment<Value>` property-wrapper type, so the bare name is ambiguous
/// in any module importing both SwiftUI and this package (approved rename).
public struct AppEnvironment: Sendable {
    public init(reminderCreator: ReminderCreating) {
        self.reminderCreator = reminderCreator
    }

    public let reminderCreator: ReminderCreating
}