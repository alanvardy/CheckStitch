# Research Questions

## Context

The CheckStitch app renders its main screen as a ZStack in `CheckStitch/ContentView.swift` with a `Color.systemBackground` fill, a photo layer (`CheckStitch/BackgroundPhotoLayer.swift`), and a `NavigationStack` on top, with platform-specific `#if os(...)` structure. The photo is supplied by `CheckStitch/BackgroundImageStore.swift` (disk + network path) and gated by user preferences stored via `@AppStorage` and bound through `CheckStitch/SettingsBindings.swift`. The macOS build target is produced by `make build-mac` / `make build-mac-signed` and tested by the suites in `CheckStitchTests/` (macOS-hosted) and `CheckStitchUITests/`.

## Questions

1. How is the main screen's view hierarchy composed in `CheckStitch/ContentView.swift`, and how does the macOS `NavigationStack` path differ from the iOS path in terms of container backgrounds and the layers above/below the `ZStack` photo layer? Enumerate every `#if os(...)` conditional that changes the view structure and what each platform's rendering path relies on (transparency, containerBackground, overlays).

2. How does `CheckStitch/BackgroundPhotoLayer.swift` draw the image on macOS vs iOS (NSImage vs UIImage decode, the `Color.clear.overlay { … .scaledToFill() }.ignoresSafeArea()` wrapper, opacity application), and what are the intrinsic-size / layout characteristics of that wrapper — i.e. what does the wrapper rely on to keep the photo pinned to the parent's bounds rather than collapsing or expanding layout?

3. How does `CheckStitch/BackgroundImageStore.swift` load and persist the background photo — where is the file and metadata read from on each platform (`defaultDirectory`, `.applicationSupportDirectory` sandboxing), what freshness / pin / single-flight gating controls whether a stored image is used or a network fetch happens, and how does the store's state reach the view?

4. How do the background settings (`backgroundEnabled`, `backgroundFadePercent`, `backgroundPinned`) flow from storage (`@AppStorage` / `UserDefaults` / `NSUbiquitousKeyValueStore`) through `CheckStitch/SettingsBindings.swift` and the settings views to `ContentView`, and are there any platform differences in storage location, sync, defaults, or the point at which `backgroundEnabled` is read?

5. What test patterns exist for platform-specific behavior and view rendering in this project — which suites in `CheckStitchTests/` exercise `ContentView`, `BackgroundPhotoLayer`, `SettingsBindings`, or `BackgroundImageStore`, which are gated with `#if os(...)` or otherwise platform-specific, what fakes/seams (e.g. `FakeBackgroundFetcher`, temp-directory injection) make the photo path testable, and what does `CheckStitchUITests/` cover?