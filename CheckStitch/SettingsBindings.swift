import SwiftUI

/// Snapshot of the background preferences, staged while the Settings sheet is
/// open. Only the three background keys live here; `appearanceMode` keeps its
/// direct `@Binding` because its side effect lives on `ContentView`.
@MainActor
@Observable
final class SettingsBindings {
    init(
        backgroundEnabled: Bool = true,
        backgroundFadePercent: Int = BackgroundFade.defaultValue,
        backgroundPinned: Bool = false) {
        self.backgroundEnabled = backgroundEnabled
        self.backgroundFadePercent = backgroundFadePercent
        self.backgroundPinned = backgroundPinned
    }

    var backgroundEnabled: Bool
    var backgroundFadePercent: Int
    var backgroundPinned: Bool
}
