import Observation

/// Owns the background-image store's lifecycle so `ContentView` only renders its
/// state. The `@AppStorage("backgroundPinned")` pref still drives it.
@MainActor
@Observable
final class BackgroundViewModel {
    var image: BackgroundImageStore
    private let isUITesting: Bool

    init(image: BackgroundImageStore = BackgroundImageStore(), isUITesting: Bool = false) {
        self.image = image
        self.isUITesting = isUITesting
    }

    /// Pins BEFORE the first refresh so a pinned cold launch never refetches a
    /// stale stored image (mirrors SingleThread's ordering).
    func task(pinned: Bool) async {
        await image.setPinned(pinned)
        if isUITesting {
            image.loadStoredImage()   // disk only; no network
            return
        }
        await image.refreshIfNeeded()
    }

    func setPinned(_ pinned: Bool) async {
        await image.setPinned(pinned)
    }
}
