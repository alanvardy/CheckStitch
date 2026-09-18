import Observation

/// Owns the staged settings bag and the Settings-menu action queue. The view
/// keeps the `@AppStorage` prefs and applies the VM's writeback to them.
@MainActor
@Observable
final class SettingsViewModel {
    var bag: SettingsBindings?
    var showsSettings = false
    private var dataActionQueue = SettingsDataActionQueue()

    /// Snapshots the current prefs into a fresh staging bag and presents the
    /// sheet. Returns the bag for convenience.
    @discardableResult
    func begin(from snapshot: SettingsSnapshot) -> SettingsBindings {
        let bag = SettingsBindings(
            backgroundEnabled: snapshot.backgroundEnabled,
            backgroundFadePercent: snapshot.backgroundFadePercent,
            backgroundPinned: snapshot.backgroundPinned,
            textSize: snapshot.textSize,
            allowsLandscape: snapshot.allowsLandscape)
        self.bag = bag
        showsSettings = true
        return bag
    }

    /// Projects the staged bag into the values the view persists.
    func writeBack(_ bag: SettingsBindings) -> SettingsWriteback {
        SettingsWriteback(
            backgroundEnabled: bag.backgroundEnabled,
            backgroundFadePercent: bag.backgroundFadePercent,
            backgroundPinned: bag.backgroundPinned,
            textSize: bag.textSize,
            allowsLandscape: bag.allowsLandscape)
    }

    /// Stages an import/export request and closes the sheet so the root-owned
    /// file panel presents unobstructed.
    func stage(_ action: SettingsDataAction) {
        dataActionQueue.stage(action)
        showsSettings = false
    }

    /// Hands the staged action over exactly once.
    func takeStaged() -> SettingsDataAction? {
        dataActionQueue.take()
    }

    /// Clears the staging bag once the sheet has dismissed.
    func sheetDidDismiss() {
        bag = nil
    }
}