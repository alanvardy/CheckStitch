import Foundation

/// App Group storage shared with the planned watch app (VAR-963). Falls back to
/// `.standard` where the group is unavailable (unregistered simulators,
/// previews) so first launch can never crash.
enum AppGroup {
    static let suiteName = "group.app.alanvardy.CheckStitch"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}