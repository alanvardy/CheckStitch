# Task

Port the background functionality from the reference app SingleThread into
CheckStitch (Swift/SwiftUI, iOS + macOS targets): (1) render a background
image behind the card containing the checklists, (2) add a Background section
to Settings matching SingleThread's background settings, (3) match
SingleThread's settings surface — enable toggle, fade percent picker, pinned
toggle, refresh button, and Unsplash credit footer.

SingleThread's implementation (the reference to port): a `BackgroundImageStore`
(@MainActor @Observable) that fetches from `https://vardy.cc/unsplash`
(6h-cached cold launch) and `/unsplash/random` (explicit refresh), validates
the decodable payload (image + photographer credit), and persists
`background.jpg` + `background.json` atomically in Application Support; a
`BackgroundPhotoLayer` view (Color.clear.overlay(image.scaledToFill())
.ignoresSafeArea().opacity(fade).allowsHitTesting(false)); a `BackgroundFade`
percent enum; and a `BackgroundSettingsView` pushed from a Settings row.

CheckStitch today is a single screen (`ContentView.swift`, one checklist card
of two stroked buttons), one Settings sheet with a single AppearanceMode picker
(`SettingsView.swift`), and UserDefaults via @AppStorage. It has no network
code, no image pipeline, and no background assets — this is the app's first
network integration, first disk image persistence, and first settings
subscreen.