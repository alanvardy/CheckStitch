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
percent enum; and a `BackgroundSettingsView` pushed from a Settings row. The
ticket cites this as the desired behavior and settings parity.

CheckStitch today is a single screen (`ContentView.swift`, one checklist card
of two stroked buttons), one Settings sheet with a single AppearanceMode picker
(`SettingsView.swift`), and UserDefaults via @AppStorage. It has no network
code, no image pipeline, and no background assets — this is the app's first
network integration, first disk image persistence, and first settings
subscreen.

## Why LARGE

- **NEW_SURFACE** — new subsystem/integration for this codebase, not a
  localized change: first network fetch, first decodable-API contract
  (vardy.cc/unsplash), first disk persistence outside UserDefaults, first
  background layer, first settings subscreen.
- **CROSS_CUTTING** — touches UI surfaces (background layer + settings) AND
  API/contracts (network endpoints, payload decoding) AND storage
  (background.jpg/json on disk); layering has no CheckStitch precedent.
- **UNKNOWNS** — research needed: dual-platform image handling (UIImage on
  iOS vs NSImage on macOS since the target also builds for macosx), no
  background assets exist in the asset catalog (runtime fetch vs bundled
  fallback), Unsplash attribution requirements, cache/refresh behavior, and
  scope decisions on network parity.

## Key files

Recon (codebase-locator) flagged:

- CheckStitch to change: `CheckStitch/ContentView.swift` (ZStack with
  background layer behind the card; new @AppStorage prefs),
  `CheckStitch/SettingsView.swift` (new Background section), plus new files
  mirroring SingleThread's `BackgroundImageStore.swift`,
  `BackgroundPhotoLayer`, `BackgroundFade.swift`, and a background settings
  view.
- Reference to port: `/Users/vardy/dev/SingleThread` —
  `SingleThread/ContentView.swift:86-93,164-171`,
  `SingleThread/BackgroundImageStore.swift` (~295 lines),
  `SingleThread/BackgroundFade.swift`, `SingleThread/BackgroundSettingsView.swift`,
  `SingleThread/SettingsView.swift:107-119`.
- No test target (gate is `make build` + shellcheck); SingleThread has
  `BackgroundImageStoreTests`/`BackgroundCardTests` worth adapting as a
  pattern.