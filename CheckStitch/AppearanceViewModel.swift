import Observation

/// Forwards appearance/orientation preference changes to the platform
/// delegates. Stateless: the `@AppStorage` prefs remain the source of truth.
@MainActor
@Observable
final class AppearanceViewModel {
    func appearanceModeChanged(_ mode: AppearanceMode) {
        #if os(iOS)
            AppDelegate.applyAppearance(mode)
        #endif
        #if os(macOS)
            MacAppDelegate.applyAppearance(mode)
        #endif
    }

    func allowsLandscapeChanged(_ allowsLandscape: Bool) {
        #if os(iOS)
            AppDelegate.applyLock(allowsLandscape: allowsLandscape)
        #endif
    }
}
