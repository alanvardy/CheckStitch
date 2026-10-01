import Foundation

/// Pure description of the crash-reporting configuration. Imports no Sentry so it
/// stays unit-testable; `SentryBootstrap` maps it to `SentryOptions`.
struct SentryConfiguration: Equatable, Sendable {
    /// Build-config-derived environment tag; unit tests assert the Debug branch.
    static var currentEnvironment: String {
        #if DEBUG
            return "debug"
        #else
            return "production"
        #endif
    }

    let dsn: String
    let environment: String
    let maxBreadcrumbs: Int
    let sendDefaultPii: Bool
    let tracesSampleRate: Double

    /// `nil` when the DSN is missing/blank, which means "never call `SentrySDK.start`".
    static func make(dsn: String?, environment: String) -> Self? {
        guard let trimmed = dsn?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return Self(
            dsn: trimmed,
            environment: environment,
            maxBreadcrumbs: 20,
            sendDefaultPii: false,
            tracesSampleRate: 0)
    }
}