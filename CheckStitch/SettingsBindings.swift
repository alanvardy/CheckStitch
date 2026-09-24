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
        textSize: TextSize = .system,
        allowsLandscape: Bool = true) {
        self.backgroundEnabled = backgroundEnabled
        self.backgroundFadePercent = backgroundFadePercent
        self.backgroundPinned = backgroundPinned
        self.textSize = textSize
        self.allowsLandscape = allowsLandscape
    }

    var backgroundEnabled: Bool
    var backgroundFadePercent: Int
    var backgroundPinned: Bool
    var textSize: TextSize
    var allowsLandscape: Bool
}

/// Import/export entry points offered by the Settings menu.
enum SettingsDataAction: Equatable {
    case export
    case importChecklists
}

/// The panel a staged `SettingsDataAction` opens. Kept beside the action so the
/// root dispatcher's switch is exhaustive by construction (a new action case
/// fails to compile until it is routed).
enum SettingsDataActionRoute: Equatable {
    case export
    case importChecklists

    init(_ action: SettingsDataAction) {
        switch action {
        case .export: self = .export
        case .importChecklists: self = .importChecklists
        }
    }
}

/// Stages a Settings-menu import/export request until the settings sheet has
/// dismissed and the root-owned file panel can present.
struct SettingsDataActionQueue {
    private var pending: SettingsDataAction?

    mutating func stage(_ action: SettingsDataAction) {
        pending = action
    }

    /// Hands the staged action over exactly once, so a dismissal callback that
    /// fires again cannot open a second panel.
    mutating func take() -> SettingsDataAction? {
        defer { pending = nil }
        return pending
    }
}

/// The five prefs the settings sheet stages, read from the view's `@AppStorage`
/// before the sheet opens.
struct SettingsSnapshot: Equatable {
    var backgroundEnabled: Bool
    var backgroundFadePercent: Int
    var backgroundPinned: Bool
    var textSize: TextSize
    var allowsLandscape: Bool
}

/// The staged prefs handed back for the view to write to `@AppStorage`.
struct SettingsWriteback: Equatable {
    var backgroundEnabled: Bool
    var backgroundFadePercent: Int
    var backgroundPinned: Bool
    var textSize: TextSize
    var allowsLandscape: Bool
}
