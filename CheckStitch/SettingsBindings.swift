import SwiftUI

/// Snapshot of the staged preferences, taken while the Settings sheet is
/// open. The background keys stage alongside the Interface keys; `appearanceMode`
/// keeps its direct `@Binding` because its side effect lives on `ContentView`.
@MainActor
@Observable
final class SettingsBindings {
    init(
        backgroundEnabled: Bool = true,
        backgroundFadePercent: Int = BackgroundFade.defaultValue,
        backgroundPinned: Bool = false,
        textSize: TextSize = .system) {
        self.backgroundEnabled = backgroundEnabled
        self.backgroundFadePercent = backgroundFadePercent
        self.backgroundPinned = backgroundPinned
        self.textSize = textSize
    }

    var backgroundEnabled: Bool
    var backgroundFadePercent: Int
    var backgroundPinned: Bool
    var textSize: TextSize
}
